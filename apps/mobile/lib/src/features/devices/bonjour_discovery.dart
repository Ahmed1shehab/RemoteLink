import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

/// DNS-SD service type RemoteLink registers under.
///
/// The name portion must be 15 characters or fewer per RFC 6763, which
/// `remotelink` satisfies with room to spare.
const String kBonjourServiceType = '_remotelink._tcp';

// TXT record keys. Deliberately terse: a DNS-SD TXT record is limited to 255
// bytes per string, and long keys buy nothing since nothing outside RemoteLink
// reads them.
const String _txtDeviceId = 'id';
const String _txtFingerprint = 'fp';
const String _txtCapabilities = 'cap';
const String _txtPlatform = 'plat';
const String _txtProtocol = 'pv';
const String _txtPairing = 'pair';

/// Discovery over Bonjour / DNS-SD.
///
/// ## Why this exists alongside the UDP backend
///
/// ADR 0001 chose custom UDP multicast over mDNS, and that reasoning still
/// holds on desktop and Android. iOS invalidates it: since iOS 14, sending to a
/// multicast group or a broadcast address requires
/// `com.apple.developer.networking.multicast`, which Apple grants by manual
/// application and may refuse. Every send fails with `EHOSTUNREACH` until then.
///
/// Bonjour is explicitly exempt from that entitlement — it is the mechanism
/// Apple wants apps to use, which is precisely why they gate the raw one. So on
/// iOS this is not a nicety, it is the only route to automatic discovery that
/// works without Apple's permission.
///
/// The UDP backend is kept rather than replaced: it needs no native plugin, it
/// works where Bonjour is unavailable, and having two independent routes means
/// a failure in either still leaves discovery working.
final class BonjourDiscoveryBackend implements DiscoveryBackend {
  BonjourDiscoveryBackend({
    required Clock clock,
    this.deviceTimeout = kDeviceTimeout,
    this.isTrusted,
  }) : _clock = clock;

  final Clock _clock;
  final Duration deviceTimeout;
  final bool Function(Uint8List fingerprint)? isTrusted;

  final Log _log = Log.scoped('mobile.discovery.bonjour');
  final Map<String, DiscoveredDevice> _devices = <String, DiscoveredDevice>{};
  final StreamController<List<DiscoveredDevice>> _controller =
      StreamController<List<DiscoveredDevice>>.broadcast();
  final StreamController<bool> _operational =
      StreamController<bool>.broadcast();

  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  bool _failed = false;

  /// Guards against a restart storm: the new browse can fail the same way.
  bool _restarting = false;

  @override
  Stream<List<DiscoveredDevice>> get devices => _controller.stream;

  @override
  List<DiscoveredDevice> get current =>
      List<DiscoveredDevice>.unmodifiable(_devices.values);

  @override
  bool get isOperational => !_failed;

  @override
  Stream<bool> get operational => _operational.stream;

  @override
  Future<void> start() async {
    if (_discovery != null) return;
    try {
      final discovery = BonsoirDiscovery(type: kBonjourServiceType);
      await discovery.ready;

      _subscription = discovery.eventStream?.listen(
        _onEvent,
        // Not a debug line. A browse that errors is a browse that has stopped
        // finding things, and the observed one — `-65569 DefunctConnection`,
        // mDNSResponder dropping the connection on a network change or a
        // sleep/wake — leaves the subscription alive and permanently silent.
        // Logged and ignored, that is a phone that says it is searching and
        // never will again, for the rest of the app's life.
        onError: (Object error, StackTrace stack) =>
            unawaited(_onStreamError(error)),
        cancelOnError: false,
      );

      await discovery.start();
      _discovery = discovery;
      _log.info('browsing for $kBonjourServiceType');
    } on Object catch (e) {
      // Never fatal. A missing or misbehaving plugin must degrade to the UDP
      // backend, not take discovery down with it.
      _markFailed(e);
    }
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceFound:
        // A found service carries only a name; the address and TXT records
        // arrive after an explicit resolve.
        event.service?.resolve(_discovery!.serviceResolver);

      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        final service = event.service;
        if (service is ResolvedBonsoirService) _record(service);

      case BonsoirDiscoveryEventType.discoveryServiceLost:
        final name = event.service?.name;
        if (name == null) return;
        final removed = _devices.entries
            .where((entry) => entry.value.name == name)
            .map((entry) => entry.key)
            .toList();
        for (final key in removed) {
          _devices.remove(key);
        }
        if (removed.isNotEmpty) _publish();

      default:
        break;
    }
  }

  void _record(ResolvedBonsoirService service) {
    final host = service.host;
    if (host == null) return;

    final attributes = service.attributes;
    final id = DeviceId.tryParse(attributes[_txtDeviceId] ?? '');
    if (id == null) {
      // Something else is squatting our service type, or an older build is
      // advertising without the identity. Either way it is not connectable.
      _log.debug(() => 'ignoring ${service.name}: no usable device id');
      return;
    }

    final fingerprint = _decodeFingerprint(attributes[_txtFingerprint]);
    final beacon = Beacon(
      kind: BeaconKind.announce,
      deviceId: id,
      name: service.name,
      platform: PlatformKind.fromWire(
        int.tryParse(attributes[_txtPlatform] ?? '') ?? 0,
      ),
      servicePort: service.port,
      protocolVersion:
          int.tryParse(attributes[_txtProtocol] ?? '') ?? kProtocolVersion,
      publicKeyFingerprint: fingerprint,
      capabilities:
          Capabilities(int.tryParse(attributes[_txtCapabilities] ?? '') ?? 0),
      acceptsNewPairings: attributes[_txtPairing] != '0',
    );

    final now = _clock.now();
    final existing = _devices[id.value];
    _devices[id.value] = existing == null
        ? DiscoveredDevice(
            beacon: beacon,
            address: host,
            firstSeen: now,
            lastSeen: now,
            isTrusted: isTrusted?.call(fingerprint) ?? false,
          )
        : existing.copyWith(
            beacon: beacon,
            address: host,
            lastSeen: now,
            isTrusted: isTrusted?.call(fingerprint) ?? false,
          );
    _publish();
  }

  static Uint8List _decodeFingerprint(String? encoded) {
    if (encoded == null || encoded.isEmpty) return Uint8List(0);
    try {
      return Uint8List.fromList(base64Url.decode(base64Url.normalize(encoded)));
    } on FormatException {
      return Uint8List(0);
    }
  }

  /// Restarts a browse that the platform tore down, once.
  ///
  /// `DefunctConnection` and its relatives are ordinary on a phone: the daemon
  /// restarts, the Wi-Fi changes, the device wakes. They are recoverable by
  /// starting a new browse, which is why this tries rather than giving up — but
  /// only once per failure, because a browse that cannot be re-established is a
  /// platform saying no, and retrying it forever would be a background loop
  /// nobody asked for.
  Future<void> _onStreamError(Object error) async {
    _log.warn('bonjour discovery stopped', error: error);
    if (_restarting || _failed) return;
    _restarting = true;

    try {
      await _subscription?.cancel();
      _subscription = null;
      try {
        await _discovery?.stop();
      } on Object catch (_) {
        // Already gone; that is the situation being recovered from.
      }
      _discovery = null;

      // A moment for the daemon to come back. Immediately re-asking a
      // responder that just died reliably fails again.
      await Future<void>.delayed(const Duration(seconds: 2));
      await start();

      if (_discovery == null) {
        _markFailed(error);
      } else {
        _log.info('bonjour discovery restarted after an error');
      }
    } on Object catch (e) {
      _markFailed(e);
    } finally {
      _restarting = false;
    }
  }

  void _markFailed(Object error) {
    if (_failed) return;
    _failed = true;
    _log.info(
      'Bonjour discovery unavailable; relying on the UDP backend',
      fields: <String, Object?>{'reason': error.toString()},
    );
    if (!_operational.isClosed) _operational.add(false);
  }

  void _publish() {
    if (!_controller.isClosed) _controller.add(current);
  }

  @override
  Future<void> refresh() async {
    // DNS-SD pushes changes rather than answering polls, so there is nothing to
    // re-request. Restarting the browse would drop and re-add every service,
    // making the list flicker for no benefit.
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _discovery?.stop();
    } on Object catch (e) {
      _log.debug(() => 'bonjour stop failed: $e');
    }
    _discovery = null;
    _devices.clear();
    await _controller.close();
    await _operational.close();
  }
}

/// Runs several discovery backends together and merges what they find.
///
/// The two routes are genuinely complementary rather than redundant: UDP works
/// without a native plugin and on networks where Bonjour is filtered, Bonjour
/// works on iOS where UDP multicast is refused outright. Merging by device ID
/// means a computer found by both appears once.
final class CompositeDiscoveryBackend implements DiscoveryBackend {
  CompositeDiscoveryBackend(this.backends);

  final List<DiscoveryBackend> backends;

  final StreamController<List<DiscoveredDevice>> _controller =
      StreamController<List<DiscoveredDevice>>.broadcast();
  final StreamController<bool> _operational =
      StreamController<bool>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  @override
  Stream<List<DiscoveredDevice>> get devices => _controller.stream;

  @override
  List<DiscoveredDevice> get current {
    final merged = <String, DiscoveredDevice>{};
    for (final backend in backends) {
      for (final device in backend.current) {
        // First writer wins, and backends are ordered by preference, so a
        // Bonjour result does not overwrite a UDP one that already resolved.
        merged.putIfAbsent(device.id.value, () => device);
      }
    }
    final list = merged.values.toList()
      ..sort((a, b) {
        if (a.isTrusted != b.isTrusted) return a.isTrusted ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return List<DiscoveredDevice>.unmodifiable(list);
  }

  /// Operational if *any* backend is.
  ///
  /// This is why the UI can stop telling an iPhone user that discovery is
  /// impossible: multicast is still refused, but Bonjour works, so discovery
  /// as a whole does.
  @override
  bool get isOperational => backends.any((backend) => backend.isOperational);

  @override
  Stream<bool> get operational => _operational.stream;

  @override
  Future<void> start() async {
    for (final backend in backends) {
      await backend.start();
      _subscriptions
        ..add(backend.devices.listen((_) => _publish()))
        ..add(backend.operational.listen((_) => _publishOperational()));
    }
    _publish();
    _publishOperational();
  }

  void _publish() {
    if (!_controller.isClosed) _controller.add(current);
  }

  void _publishOperational() {
    if (!_operational.isClosed) _operational.add(isOperational);
  }

  @override
  Future<void> refresh() async {
    for (final backend in backends) {
      await backend.refresh();
    }
  }

  @override
  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (final backend in backends) {
      await backend.stop();
    }
    await _controller.close();
    await _operational.close();
  }
}
