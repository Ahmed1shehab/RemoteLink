import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../features/devices/bonjour_discovery.dart';
import '../features/input/pointer_controller.dart';

/// What this phone can do, advertised during the handshake.
const Capabilities kMobileCapabilities = Capabilities(
  Capabilities.mouse |
      Capabilities.keyboard |
      Capabilities.clipboardText |
      Capabilities.mediaControl |
      Capabilities.mediaMetadata |
      Capabilities.presentation |
      Capabilities.gamepad |
      Capabilities.compression |
      Capabilities.sessionResumption |
      Capabilities.gestures,
);

const String _identityKey = 'remotelink.identity.private';
const String _trustKey = 'remotelink.trust.peers';
const String _deviceNameKey = 'remotelink.device.name';
const String _pointerSettingsKey = 'remotelink.settings.pointer';
const String _clipboardSettingsKey = 'remotelink.settings.clipboard';

/// Where hardware addresses of paired computers are persisted.
///
/// Public, unlike its neighbours, so a test can seed realistic stored state and
/// exercise the same load path the app uses rather than a parallel one.
const String kWakeAddressesKey = 'remotelink.wake.addresses';

/// Where the client keeps its long-term key and trust list.
///
/// Two implementations, chosen by platform rather than by preference. The
/// platform keystore is the right home for a private key and is used wherever
/// the app actually ships. It is *not* used on desktop, for a concrete reason:
/// reaching the macOS Keychain from a sandboxed app needs a
/// `keychain-access-groups` entitlement, that entitlement resolves
/// `$(AppIdentifierPrefix)` from a provisioning profile, and requiring one
/// breaks `flutter run` under ad-hoc signing. Since the desktop build of the
/// client exists only as a development convenience, paying for it with a
/// signing setup would be a bad trade.
abstract interface class IdentityStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// iOS and Android: hardware-backed keystore.
///
/// `first_unlock` on iOS lets the app reconnect in the background after a
/// reboot while keeping the key unreadable until the device has been unlocked
/// once.
final class KeystoreIdentityStore implements IdentityStore {
  const KeystoreIdentityStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Desktop: an owner-only file under the application support directory.
///
/// The same trade-off the desktop companion makes, and documented in
/// `docs/SECURITY.md` as gap 1. Acceptable here because this build is a test
/// harness; it would not be acceptable in something shipped.
final class FileIdentityStore implements IdentityStore {
  const FileIdentityStore(this.directory);

  final Directory directory;

  File _fileFor(String key) => File('${directory.path}/$key');

  @override
  Future<String?> read(String key) async {
    final file = _fileFor(key);
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String key, String value) async {
    final file = _fileFor(key);
    await file.writeAsString(value, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['600', file.path]);
    }
  }
}

/// Picks the store for the running platform.
final identityStoreProvider = FutureProvider<IdentityStore>((ref) async {
  if (Platform.isIOS || Platform.isAndroid) {
    return const KeystoreIdentityStore();
  }
  final base = await getApplicationSupportDirectory();
  final directory = Directory('${base.path}/RemoteLink');
  if (!directory.existsSync()) {
    await directory.create(recursive: true);
  }
  return FileIdentityStore(directory);
});

/// This phone's long-term identity, generated once and reused forever.
///
/// On iOS and Android this lands in the hardware-backed keystore, so the
/// private key is not readable even from a rooted or jailbroken device with a
/// full filesystem dump. On desktop builds it falls back to an owner-only file
/// — see [IdentityStore] for why, and `docs/SECURITY.md` gap 1.
final identityProvider = FutureProvider<DeviceIdentity>((ref) async {
  final store = await ref.watch(identityStoreProvider.future);

  final stored = await store.read(_identityKey);
  if (stored != null) {
    return DeviceIdentity.fromPrivateKey(base64Decode(stored));
  }

  final identity = await DeviceIdentity.generate();
  final privateKey = await identity.extractPrivateKey();
  await store.write(_identityKey, base64Encode(privateKey));
  return identity;
});

/// Computers this phone has paired with.
///
/// Persisted through the same secure storage as the identity. The contents are
/// only public keys, so the confidentiality is incidental — what matters is
/// integrity: an attacker who could rewrite this file could substitute their
/// own key for a trusted computer's and the phone would connect to them
/// without any prompt.
final trustStoreProvider = FutureProvider<TrustStore>((ref) async {
  final peers = InMemoryTrustStore();
  ref.onDispose(peers.dispose);

  final storage = await ref.watch(identityStoreProvider.future);
  final raw = await storage.read(_trustKey);
  if (raw != null) {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        final id = DeviceId.tryParse(entry['id'] as String? ?? '');
        final key = entry['publicKey'] as String?;
        if (id == null || key == null) continue;
        await peers.upsert(
          TrustedPeer(
            id: id,
            publicKey: Uint8List.fromList(base64Decode(key)),
            name: entry['name'] as String? ?? id.short,
            platform: PlatformKind.fromWire(entry['platform'] as int? ?? 0),
            pairedAt: DateTime.tryParse(entry['pairedAt'] as String? ?? '') ??
                DateTime.now(),
            permissionTier: entry['permissionTier'] as int? ?? 2,
          ),
        );
      }
    }
  }
  return peers;
});

/// Writes the trust store back to persistent storage.
///
/// Takes the [IdentityStore] explicitly rather than reaching for a global: the
/// backing store is platform-dependent, and passing it keeps that decision in
/// one place instead of duplicating the platform check here.
Future<void> persistTrustStore(TrustStore store, IdentityStore storage) async {
  final saved = await store.listPeers();
  await storage.write(
    _trustKey,
    jsonEncode(<Map<String, Object?>>[
      for (final peer in saved)
        <String, Object?>{
          'id': peer.id.value,
          'publicKey': base64Encode(peer.publicKey),
          'name': peer.name,
          'platform': peer.platform.wireValue,
          'pairedAt': peer.pairedAt.toIso8601String(),
          'permissionTier': peer.permissionTier,
        },
    ]),
  );
}

/// Hardware addresses of paired computers, keyed by device ID.
///
/// Stored beside the trust store rather than inside it. `TrustedPeer` lives in
/// `rl_crypto` and its persisted shape is shared with the desktop, where a MAC
/// has no meaning — the desktop reads its own from the OS. This is phone-side
/// state about a paired computer, so it is keyed by the same device ID and
/// written through the same [IdentityStore], and a peer the user un-pairs
/// simply stops being looked up.
///
/// An address here is a convenience, never a trust input: it decides which
/// bytes get broadcast to a sleeping machine, and the woken machine still has
/// to complete the same handshake as ever.
final class WakeAddressesNotifier
    extends StateNotifier<Map<String, MacAddress>> {
  WakeAddressesNotifier(this._ref) : super(const <String, MacAddress>{}) {
    unawaited(_load());
  }

  final Ref _ref;

  Future<void> _load() async {
    final storage = await _ref.read(identityStoreProvider.future);
    final raw = await storage.read(kWakeAddressesKey);
    if (raw == null) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      state = <String, MacAddress>{
        for (final entry in decoded.entries)
          if (entry.value is String)
            if (MacAddress.tryParse(entry.value as String) case final mac?)
              entry.key: mac,
      };
    } on FormatException {
      // A corrupt file costs the user a Wake button until the computer next
      // reports its address. Not worth failing the launch over.
    }
  }

  /// Records [mac] for [peerId], persisting only when it actually changed.
  Future<void> remember(DeviceId peerId, MacAddress mac) async {
    if (state[peerId.value] == mac) return;
    state = <String, MacAddress>{...state, peerId.value: mac};

    final storage = await _ref.read(identityStoreProvider.future);
    await storage.write(
      kWakeAddressesKey,
      jsonEncode(<String, String>{
        for (final entry in state.entries) entry.key: entry.value.canonical,
      }),
    );
  }

  /// The address stored for [peerId], if this computer ever reported one.
  MacAddress? addressFor(DeviceId? peerId) =>
      peerId == null ? null : state[peerId.value];
}

final wakeAddressesProvider =
    StateNotifierProvider<WakeAddressesNotifier, Map<String, MacAddress>>(
  WakeAddressesNotifier.new,
);

/// Whether automatic discovery can work on this device and network.
///
/// False on an iPhone without Apple's multicast entitlement, and on networks
/// with client isolation. Surfaced so the UI can say so — an empty list with no
/// explanation is indistinguishable from "the computer is not running", and
/// sends the user looking in the wrong place.
final discoveryOperationalProvider = StreamProvider<bool>((ref) async* {
  final backend = await ref.watch(discoveryProvider.future);
  yield backend.isOperational;
  yield* backend.operational;
});

/// Computers this phone has paired with, discovered or not.
///
/// Kept separate from discovery on purpose. A paired computer must remain
/// reachable when discovery cannot see it — on a network that blocks multicast,
/// or on iOS without the multicast entitlement — by dialling the address it was
/// last reached at. Without this the device list would be empty on exactly the
/// networks where the user most needs it to work.
final trustedPeersProvider = FutureProvider<List<TrustedPeer>>((ref) async {
  final store = await ref.watch(trustStoreProvider.future);
  return store.activePeers();
});

final clockProvider = Provider<Clock>((ref) => SystemClock());

/// Discovers computers on the local network.
///
/// Kept alive for the app's lifetime rather than started per screen: discovery
/// takes a moment to populate, and restarting it every time the user navigates
/// back to the device list would make the list appear empty each time.
final discoveryProvider = FutureProvider<DiscoveryBackend>((ref) async {
  final trustStore = await ref.watch(trustStoreProvider.future);
  final peers = await trustStore.activePeers();

  bool isTrusted(Uint8List fingerprint) => peers.any(
        (peer) => Primitives.constantTimeEquals(
          Uint8List.sublistView(peer.publicKey, 0, 8),
          fingerprint,
        ),
      );

  final clock = ref.watch(clockProvider);

  // Bonjour first: on iOS it is the only route that works, and where both are
  // available its resolved addresses are as good as the beacon's. The UDP
  // backend stays as a second route for networks that filter mDNS and for
  // platforms where the plugin is unavailable.
  final backend = CompositeDiscoveryBackend(<DiscoveryBackend>[
    BonjourDiscoveryBackend(clock: clock, isTrusted: isTrusted),
    UdpDiscoveryClient(clock: clock, isTrusted: isTrusted),
  ]);

  await backend.start();
  ref.onDispose(backend.stop);
  return backend;
});

/// Computers currently visible on the network.
final discoveredDevicesProvider =
    StreamProvider<List<DiscoveredDevice>>((ref) async* {
  final backend = await ref.watch(discoveryProvider.future);
  // The current snapshot comes first so a screen that mounts after discovery
  // started shows the devices immediately instead of appearing empty until the
  // next beacon arrives two seconds later.
  yield backend.current;
  yield* backend.devices;
});

/// The connection supervisor. One per app; it handles reconnection itself.
final clientProvider = FutureProvider<RemoteLinkClient>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  final client = RemoteLinkClient(
    identity: identity,
    capabilities: kMobileCapabilities,
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Connection state, for the status indicator.
final clientStateProvider = StreamProvider<ClientState>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  yield client.state;
  yield* client.states;
});

/// Link quality of the current session, refreshed each heartbeat.
final connectionQualityProvider =
    StreamProvider<ConnectionQuality>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  await for (final session in client.sessions) {
    yield* session.quality;
  }
});

/// The connected computer's identity, once it has told us.
///
/// Chiefly so the rendered keyboard can label the modifier key Command or
/// Windows. Guessing that from the phone's own platform would be wrong exactly
/// when it matters — an iPhone driving a Windows PC is a normal thing to do.
///
/// Falls back to the trust store while the message is in flight, so a
/// reconnect to a known computer never briefly shows the wrong key.
final connectedPeerProvider = StreamProvider<DeviceInfo?>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  yield null;

  await for (final message in client.messages) {
    if (message is! DeviceInfoMessage) continue;
    final info = message.info;
    yield info;

    // Write it back to the trust store. A device paired by typing an address
    // was recorded with an unknown platform and an address for a name; without
    // this correction it would be re-guessed on every launch, and the device
    // list would keep showing an IP where a name belongs.
    unawaited(_rememberPeerDetails(ref, info));
  }
});

Future<void> _rememberPeerDetails(Ref ref, DeviceInfo info) async {
  final store = await ref.read(trustStoreProvider.future);
  final peer = await store.findById(info.id);
  if (peer == null) return;

  // Recorded while the computer is awake and talking, because that is the only
  // time it can be: once it is asleep there is nothing left to ask.
  if (info.macAddress case final mac? when mac.isWakeable) {
    await ref.read(wakeAddressesProvider.notifier).remember(info.id, mac);
  }

  final needsUpdate = peer.platform != info.platform || peer.name != info.name;
  if (!needsUpdate) return;

  // `TrustedPeer.copyWith` cannot change the platform — it is derived from the
  // pairing and treated as immutable there — so the record is rebuilt. The
  // public key is carried across untouched: it is the thing trust rests on and
  // must never be taken from a message.
  await store.upsert(
    TrustedPeer(
      id: peer.id,
      publicKey: peer.publicKey,
      name: info.name,
      platform: info.platform,
      pairedAt: peer.pairedAt,
      permissionTier: peer.permissionTier,
      lastSeenAt: DateTime.now(),
      lastAddress: peer.lastAddress,
      revoked: peer.revoked,
    ),
  );
  await persistTrustStore(store, await ref.read(identityStoreProvider.future));
  ref.invalidate(trustedPeersProvider);
}

/// Platform of the computer being controlled, best effort.
final connectedPlatformProvider = Provider<PlatformKind>((ref) {
  final reported = ref.watch(connectedPeerProvider).valueOrNull?.platform;
  if (reported != null && reported != PlatformKind.unknown) return reported;

  // Before the identity message arrives, use what pairing recorded.
  final session = ref.watch(clientProvider).valueOrNull?.session;
  final peers = ref.watch(trustedPeersProvider).valueOrNull;
  if (session != null && peers != null) {
    for (final peer in peers) {
      if (peer.id == session.peerId) return peer.platform;
    }
  }
  return PlatformKind.unknown;
});

/// Inbound messages from the desktop, flattened across reconnects.
final desktopMessagesProvider = StreamProvider<Message>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  yield* client.messages;
});

/// Live permission tier of the current session, updated on [PermissionGrant] messages.
final currentPermissionTierProvider =
    StreamProvider<PermissionTier?>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  // The grant the client already saw comes first, then any later ones. Without
  // the seed this only ever reported a tier for a device whose tier *changed*
  // while a screen happened to be watching: the desktop sends the grant as
  // soon as a trusted session is established, `messages` is a broadcast
  // stream, and nothing is subscribed that early. So this yielded null and
  // stayed there, and the screen-share button — which checks the tier before
  // offering itself — never appeared on any normally connected phone.
  yield client.grantedTier;
  await for (final message in client.messages) {
    if (message is PermissionGrant) {
      yield message.tier;
    }
  }
});

/// Host telemetry (battery, load, memory, uptime), pushed from the desktop.
final systemStatusProvider = StreamProvider<SystemStatus?>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  yield null;
  await for (final message in client.messages) {
    if (message is SystemStatus) yield message;
  }
});

/// The user-visible name of this phone, persisted in [IdentityStore].
final class DeviceNameNotifier extends StateNotifier<String> {
  DeviceNameNotifier(this._ref) : super(_defaultName()) {
    unawaited(_load());
  }

  final Ref _ref;

  static String _defaultName() {
    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty) return host;
    } catch (_) {}
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isAndroid) return 'Android Phone';
    return 'Phone';
  }

  Future<void> _load() async {
    final storage = await _ref.read(identityStoreProvider.future);
    final stored = await storage.read(_deviceNameKey);
    if (stored != null) {
      final sanitised = sanitiseDeviceName(stored);
      if (sanitised != null) {
        state = sanitised;
      }
    }
  }

  /// Sets the device name if valid according to [sanitiseDeviceName].
  ///
  /// Returns null on success, or an error message if [newName] is invalid.
  Future<String?> setDeviceName(String newName) async {
    final sanitised = sanitiseDeviceName(newName);
    if (sanitised == null) {
      return 'Invalid name: 1–64 characters, no control codes or line breaks.';
    }

    state = sanitised;
    final storage = await _ref.read(identityStoreProvider.future);
    await storage.write(_deviceNameKey, sanitised);

    final client = _ref.read(clientProvider).valueOrNull;
    if (client != null && client.isConnected) {
      try {
        await client.send(DeviceRename(sanitised));
      } catch (_) {}
    }
    return null;
  }
}

final deviceNameProvider = StateNotifierProvider<DeviceNameNotifier, String>(
  DeviceNameNotifier.new,
);

/// Pointer settings notifier backed by [IdentityStore].
final class PointerSettingsNotifier extends StateNotifier<PointerSettings> {
  PointerSettingsNotifier(this._ref) : super(const PointerSettings()) {
    unawaited(_load());
  }

  final Ref _ref;

  Future<void> _load() async {
    final storage = await _ref.read(identityStoreProvider.future);
    final raw = await storage.read(_pointerSettingsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          state = PointerSettings.fromJson(decoded);
        }
      } on FormatException {
        // Corrupted settings, keep defaults.
      }
    }
  }

  Future<void> update(PointerSettings settings) async {
    state = settings;
    final storage = await _ref.read(identityStoreProvider.future);
    await storage.write(_pointerSettingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> setSensitivity(double sensitivity) =>
      update(state.copyWith(sensitivity: sensitivity));

  Future<void> setNaturalScrolling(bool naturalScrolling) =>
      update(state.copyWith(naturalScrolling: naturalScrolling));

  Future<void> setTapToClick(bool tapToClick) =>
      update(state.copyWith(tapToClick: tapToClick));
}

final pointerSettingsProvider =
    StateNotifierProvider<PointerSettingsNotifier, PointerSettings>(
  PointerSettingsNotifier.new,
);

/// Independent toggles for clipboard synchronization directions.
@immutable
final class ClipboardSettings {
  const ClipboardSettings({
    this.syncFromDesktop = true,
    this.syncToDesktop = true,
  });

  final bool syncFromDesktop;
  final bool syncToDesktop;

  ClipboardSettings copyWith({
    bool? syncFromDesktop,
    bool? syncToDesktop,
  }) =>
      ClipboardSettings(
        syncFromDesktop: syncFromDesktop ?? this.syncFromDesktop,
        syncToDesktop: syncToDesktop ?? this.syncToDesktop,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'syncFromDesktop': syncFromDesktop,
        'syncToDesktop': syncToDesktop,
      };

  factory ClipboardSettings.fromJson(Map<String, dynamic> json) =>
      ClipboardSettings(
        syncFromDesktop: json['syncFromDesktop'] as bool? ?? true,
        syncToDesktop: json['syncToDesktop'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipboardSettings &&
          other.syncFromDesktop == syncFromDesktop &&
          other.syncToDesktop == syncToDesktop;

  @override
  int get hashCode => Object.hash(syncFromDesktop, syncToDesktop);
}

final class ClipboardSettingsNotifier extends StateNotifier<ClipboardSettings> {
  ClipboardSettingsNotifier(this._ref) : super(const ClipboardSettings()) {
    unawaited(_load());
  }

  final Ref _ref;

  Future<void> _load() async {
    final storage = await _ref.read(identityStoreProvider.future);
    final raw = await storage.read(_clipboardSettingsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          state = ClipboardSettings.fromJson(decoded);
        }
      } on FormatException {
        // Corrupted settings, keep defaults.
      }
    }
  }

  Future<void> update(ClipboardSettings settings) async {
    state = settings;
    final storage = await _ref.read(identityStoreProvider.future);
    await storage.write(_clipboardSettingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> setSyncFromDesktop(bool enabled) =>
      update(state.copyWith(syncFromDesktop: enabled));

  Future<void> setSyncToDesktop(bool enabled) =>
      update(state.copyWith(syncToDesktop: enabled));
}

final clipboardSettingsProvider =
    StateNotifierProvider<ClipboardSettingsNotifier, ClipboardSettings>(
  ClipboardSettingsNotifier.new,
);

/// In-memory log buffer backing the diagnostics view.
final memoryLogSinkProvider = Provider<MemoryLogSink>((ref) {
  final sink = Log.sink;
  if (sink is MemoryLogSink) return sink;
  if (sink is MultiLogSink) {
    for (final s in sink.sinks) {
      if (s is MemoryLogSink) return s;
    }
  }
  return MemoryLogSink();
});
