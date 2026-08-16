import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'beacon.dart';

/// How often the desktop re-announces itself.
///
/// Two seconds is the compromise between a phone that just joined the network
/// seeing the computer quickly and not flooding the LAN. It matters less than
/// it looks, because a client sends a query on launch and gets an immediate
/// answer — the interval only governs how fast a *passive* listener notices.
const Duration kAnnounceInterval = Duration(seconds: 2);

/// How long a device stays in the list without being heard from.
///
/// Three missed announcements. Shorter would make the list flicker on a busy
/// Wi-Fi network where the occasional multicast datagram is dropped.
const Duration kDeviceTimeout = Duration(seconds: 7);

/// Pluggable discovery mechanism.
///
/// The abstraction exists so a DNS-SD backend can be added later — or a
/// Bluetooth LE one for finding a computer that is not on the same Wi-Fi —
/// without the UI or connection layer changing at all.
abstract interface class DiscoveryBackend {
  /// Devices currently visible, updated as beacons arrive and expire.
  Stream<List<DiscoveredDevice>> get devices;

  /// Snapshot of the current list.
  List<DiscoveredDevice> get current;

  /// Whether this backend can actually operate here.
  ///
  /// False when the platform or the network refuses the traffic discovery
  /// depends on — an iPhone without Apple's multicast entitlement, or a Wi-Fi
  /// network with client isolation. Modelling this explicitly matters: without
  /// it the only symptom is an empty list, which is indistinguishable from
  /// "the computer is not running" and leaves the user with nothing to act on.
  bool get isOperational;

  /// Emits when [isOperational] changes.
  Stream<bool> get operational;

  /// Begins listening.
  Future<void> start();

  /// Asks every server to announce itself immediately.
  Future<void> refresh();

  Future<void> stop();
}

/// UDP multicast implementation of [DiscoveryBackend].
///
/// Binds one socket per usable network interface rather than one wildcard
/// socket. This is not paranoia — a laptop routinely has Wi-Fi, Ethernet, and
/// several virtual adapters (Docker, VPN, VirtualBox), and a wildcard multicast
/// join lands on whichever the OS picks, which is frequently a virtual adapter
/// that reaches nothing. Joining explicitly on each real interface is the
/// difference between "sometimes finds my PC" and "always finds my PC".
final class UdpDiscoveryClient implements DiscoveryBackend {
  UdpDiscoveryClient({
    required Clock clock,
    this.port = kDiscoveryPort,
    this.deviceTimeout = kDeviceTimeout,
    this.isTrusted,
  }) : _clock = clock;

  final Clock _clock;
  final int port;
  final Duration deviceTimeout;

  /// Optional predicate marking a fingerprint as already paired.
  final bool Function(Uint8List fingerprint)? isTrusted;

  final Log _log = Log.scoped('transport.discovery.client');
  final List<RawDatagramSocket> _sockets = <RawDatagramSocket>[];
  final Map<String, DiscoveredDevice> _devices = <String, DiscoveredDevice>{};
  final StreamController<List<DiscoveredDevice>> _controller =
      StreamController<List<DiscoveredDevice>>.broadcast();

  final List<StreamSubscription<RawSocketEvent>> _subscriptions =
      <StreamSubscription<RawSocketEvent>>[];

  Timer? _reaper;
  bool _running = false;

  /// Errno values that mean "this platform or network will not carry the
  /// datagrams discovery needs".
  ///
  /// `EHOSTUNREACH` (65) is the one iOS returns when an app sends to a
  /// multicast group without `com.apple.developer.networking.multicast`. These
  /// are *expected states*, not faults, and are reported once and calmly
  /// rather than as a stack trace per socket per target — which on a phone with
  /// several interfaces means roughly twenty identical traces at launch,
  /// burying anything genuinely useful.
  static const Set<int> _refusedErrnos = <int>{
    1, // EPERM        — sandbox or entitlement denial
    49, // EADDRNOTAVAIL
    50, // ENETDOWN
    51, // ENETUNREACH
    65, // EHOSTUNREACH — iOS without the multicast entitlement
  };

  bool _refused = false;
  final StreamController<bool> _operational =
      StreamController<bool>.broadcast();

  @override
  Stream<List<DiscoveredDevice>> get devices => _controller.stream;

  @override
  List<DiscoveredDevice> get current => _snapshot();

  @override
  bool get isOperational => !_refused;

  @override
  Stream<bool> get operational => _operational.stream;

  /// Classifies a send failure, reporting a refusal exactly once.
  void _noteSendFailure(Object error) {
    final code = error is SocketException ? error.osError?.errorCode : null;
    if (code == null || !_refusedErrnos.contains(code)) {
      _log.debug(() => 'discovery send failed: $error');
      return;
    }
    if (_refused) return;

    _refused = true;
    _log.info(
      'automatic discovery is unavailable on this device or network; '
      'connect by address instead',
      fields: <String, Object?>{'errno': code},
    );
    if (!_operational.isClosed) _operational.add(false);
  }

  void _trySend(Uint8List payload, RawDatagramSocket socket, String target) {
    try {
      socket.send(payload, InternetAddress(target), port);
    } on SocketException catch (e) {
      _noteSendFailure(e);
    }
  }

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;

    final interfaces = await _usableInterfaces();
    if (interfaces.isEmpty) {
      _log.warn('no usable network interfaces; discovery will find nothing');
    }

    for (final interface in interfaces) {
      await _bindInterface(interface);
    }

    _reaper = Timer.periodic(const Duration(seconds: 1), (_) => _reap());
    await refresh();
  }

  Future<void> _bindInterface(NetworkInterface interface) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: Platform.isMacOS || Platform.isIOS,
      );

      // Loopback matters more than it sounds: it is how a developer running the
      // desktop and a simulator on one machine sees anything at all.
      socket
        ..multicastLoopback = true
        ..broadcastEnabled = true;

      try {
        socket.joinMulticast(InternetAddress(kMulticastGroupV4), interface);
      } on OSError catch (e) {
        // A virtual adapter that refuses the join is normal and not worth
        // failing the whole scan over.
        _log.debug(
          () => 'multicast join failed on ${interface.name}',
          fields: <String, Object?>{'error': e.message},
        );
      }

      _subscriptions.add(
        socket.listen(
          (event) => _onSocketEvent(socket, event),
          // Datagram send failures surface here as well as by throwing, so
          // both routes go through the same classifier — otherwise a refused
          // multicast is reported twice, once calmly and once as a stack trace.
          onError: _noteSendFailure,
          cancelOnError: false,
        ),
      );
      _sockets.add(socket);
    } on SocketException catch (e) {
      _log.warn(
        'could not bind discovery socket on ${interface.name}',
        fields: <String, Object?>{'error': e.message},
      );
    }
  }

  void _onSocketEvent(RawDatagramSocket socket, RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;

    final beacon = Beacon.tryParse(datagram.data);
    if (beacon == null) return;

    switch (beacon.kind) {
      case BeaconKind.announce:
        _record(beacon, datagram.address.address);
      case BeaconKind.goodbye:
        if (_devices.remove(beacon.deviceId.value) != null) _publish();
      case BeaconKind.query:
        // Another client looking for servers. Not our concern.
        break;
    }
  }

  void _record(Beacon beacon, String address) {
    final now = _clock.now();
    final existing = _devices[beacon.deviceId.value];
    final trusted = isTrusted?.call(beacon.publicKeyFingerprint) ?? false;

    _devices[beacon.deviceId.value] = existing == null
        ? DiscoveredDevice(
            beacon: beacon,
            address: address,
            firstSeen: now,
            lastSeen: now,
            isTrusted: trusted,
          )
        : existing.copyWith(
            beacon: beacon,
            address: address,
            lastSeen: now,
            isTrusted: trusted,
          );

    // Publishing on every announcement would rebuild the list twice a second
    // per device for no visible change. Only structural changes are pushed.
    final isNew = existing == null;
    final moved = existing != null && existing.address != address;
    final renamed = existing != null && existing.beacon.name != beacon.name;
    if (isNew || moved || renamed) _publish();
  }

  void _reap() {
    final now = _clock.now();
    final before = _devices.length;
    _devices.removeWhere((_, device) => device.isStale(now, deviceTimeout));
    if (_devices.length != before) _publish();
  }

  @override
  Future<void> refresh() async {
    final query = Beacon(
      kind: BeaconKind.query,
      deviceId: const DeviceId('00000000000000000000000000'),
      name: '',
      platform: PlatformKind.unknown,
      servicePort: 1,
      protocolVersion: 1,
      publicKeyFingerprint: Uint8List(0),
      capabilities: const Capabilities(0),
    ).encode();

    for (final socket in _sockets) {
      _trySend(query, socket, kMulticastGroupV4);
      // Directed broadcast as a fallback for access points that filter
      // multicast between wireless clients — a common consumer-router
      // "feature" that would otherwise make discovery silently fail. Sent
      // independently of the multicast attempt: if the first is refused, the
      // second may still get through, and a shared try block would skip it.
      _trySend(query, socket, '255.255.255.255');
    }
  }

  List<DiscoveredDevice> _snapshot() {
    final list = _devices.values.toList()
      ..sort((a, b) {
        // Trusted devices first, then alphabetically. The computer the user
        // already paired is almost always the one they want.
        if (a.isTrusted != b.isTrusted) return a.isTrusted ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return List<DiscoveredDevice>.unmodifiable(list);
  }

  void _publish() {
    if (_controller.hasListener) _controller.add(_snapshot());
  }

  @override
  Future<void> stop() async {
    _running = false;
    _reaper?.cancel();
    _reaper = null;

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
    _devices.clear();

    await _controller.close();
    await _operational.close();
  }
}

/// Broadcasts this computer's presence.
final class UdpDiscoveryServer {
  UdpDiscoveryServer({
    required Beacon Function() describe,
    this.port = kDiscoveryPort,
    this.interval = kAnnounceInterval,
  }) : _describe = describe;

  /// Called for every announcement rather than holding a fixed [Beacon], so
  /// live fields — session count, whether pairing is currently open — are
  /// always current without the caller having to remember to push updates.
  final Beacon Function() _describe;

  final int port;
  final Duration interval;

  final Log _log = Log.scoped('transport.discovery.server');
  final List<RawDatagramSocket> _sockets = <RawDatagramSocket>[];
  final List<StreamSubscription<RawSocketEvent>> _subscriptions =
      <StreamSubscription<RawSocketEvent>>[];

  Timer? _timer;
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    for (final interface in await _usableInterfaces()) {
      try {
        final socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: true,
          reusePort: Platform.isMacOS || Platform.isIOS,
        );
        socket
          ..multicastLoopback = true
          ..broadcastEnabled = true;

        try {
          socket.joinMulticast(InternetAddress(kMulticastGroupV4), interface);
        } on OSError catch (_) {
          // Non-fatal; this interface simply will not receive queries.
        }

        _subscriptions.add(
          socket.listen(
            (event) => _onSocketEvent(socket, event),
            onError: (Object error, StackTrace stack) => _log.warn(
              'announce socket error',
              error: error,
              stackTrace: stack,
            ),
            cancelOnError: false,
          ),
        );
        _sockets.add(socket);
      } on SocketException catch (e) {
        _log.warn(
          'could not bind announce socket on ${interface.name}',
          fields: <String, Object?>{'error': e.message},
        );
      }
    }

    _timer = Timer.periodic(interval, (_) => announce());
    announce();
  }

  void _onSocketEvent(RawDatagramSocket socket, RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;

    final beacon = Beacon.tryParse(datagram.data);
    if (beacon?.kind != BeaconKind.query) return;

    // Reply directly to the asker rather than to the group. A phone that just
    // opened the app gets an answer in one round trip, and the other twenty
    // devices on the network are not woken up to ignore it.
    _sendTo(socket, datagram.address, BeaconKind.announce);
  }

  /// Sends one announcement on every bound socket.
  void announce() {
    for (final socket in _sockets) {
      _sendTo(socket, InternetAddress(kMulticastGroupV4), BeaconKind.announce);
    }
  }

  void _sendTo(
      RawDatagramSocket socket, InternetAddress target, BeaconKind kind) {
    try {
      final beacon = _describe();
      final payload = kind == beacon.kind
          ? beacon.encode()
          : Beacon(
              kind: kind,
              deviceId: beacon.deviceId,
              name: beacon.name,
              platform: beacon.platform,
              servicePort: beacon.servicePort,
              protocolVersion: beacon.protocolVersion,
              publicKeyFingerprint: beacon.publicKeyFingerprint,
              capabilities: beacon.capabilities,
              acceptsNewPairings: beacon.acceptsNewPairings,
              activeSessions: beacon.activeSessions,
            ).encode();
      socket.send(payload, target, port);
    } on SocketException catch (e) {
      _log.debug(() => 'announce send failed: ${e.message}');
    }
  }

  /// Announces departure so clients drop the entry immediately instead of
  /// waiting for it to time out.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    _timer?.cancel();
    _timer = null;

    for (final socket in _sockets) {
      _sendTo(socket, InternetAddress(kMulticastGroupV4), BeaconKind.goodbye);
    }

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
  }
}

/// Network interfaces worth binding to.
///
/// Loopback is included deliberately — it is the only way desktop-and-simulator
/// development on one machine works.
Future<List<NetworkInterface>> _usableInterfaces() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: true,
      type: InternetAddressType.IPv4,
    );
    return interfaces.where((i) => i.addresses.isNotEmpty).toList();
  } on SocketException {
    return const <NetworkInterface>[];
  }
}
