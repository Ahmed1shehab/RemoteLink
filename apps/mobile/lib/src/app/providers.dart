import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../features/devices/bonjour_discovery.dart';

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
      Capabilities.sessionResumption,
);

const String _identityKey = 'remotelink.identity.private';
const String _trustKey = 'remotelink.trust.peers';

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

/// Inbound messages from the desktop, flattened across reconnects.
final desktopMessagesProvider = StreamProvider<Message>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  yield* client.messages;
});
