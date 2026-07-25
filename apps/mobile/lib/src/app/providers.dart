import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

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

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

const String _identityKey = 'remotelink.identity.private';
const String _trustKey = 'remotelink.trust.peers';

/// This phone's long-term identity.
///
/// Stored in the platform keystore rather than in a file: the Android Keystore
/// and the iOS Keychain are hardware-backed on modern devices, so the private
/// key is not readable even from a rooted or jailbroken device with a full
/// filesystem dump. On desktop the equivalent migration is still outstanding —
/// see `docs/SECURITY.md`.
///
/// `first_unlock` accessibility on iOS is chosen so the app can reconnect in
/// the background after a reboot, while still keeping the key unreadable until
/// the user has unlocked the device once.
final identityProvider = FutureProvider<DeviceIdentity>((ref) async {
  final stored = await _secureStorage.read(key: _identityKey);
  if (stored != null) {
    return DeviceIdentity.fromPrivateKey(base64Decode(stored));
  }

  final identity = await DeviceIdentity.generate();
  final privateKey = await identity.extractPrivateKey();
  await _secureStorage.write(
    key: _identityKey,
    value: base64Encode(privateKey),
  );
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
  final store = InMemoryTrustStore();
  ref.onDispose(store.dispose);

  final raw = await _secureStorage.read(key: _trustKey);
  if (raw != null) {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        final id = DeviceId.tryParse(entry['id'] as String? ?? '');
        final key = entry['publicKey'] as String?;
        if (id == null || key == null) continue;
        await store.upsert(
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
  return store;
});

/// Writes the trust store back to secure storage.
Future<void> persistTrustStore(TrustStore store) async {
  final peers = await store.listPeers();
  await _secureStorage.write(
    key: _trustKey,
    value: jsonEncode(<Map<String, Object?>>[
      for (final peer in peers)
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

final clockProvider = Provider<Clock>((ref) => SystemClock());

/// Discovers computers on the local network.
///
/// Kept alive for the app's lifetime rather than started per screen: discovery
/// takes a moment to populate, and restarting it every time the user navigates
/// back to the device list would make the list appear empty each time.
final discoveryProvider = FutureProvider<DiscoveryBackend>((ref) async {
  final trustStore = await ref.watch(trustStoreProvider.future);
  final peers = await trustStore.activePeers();

  final backend = UdpDiscoveryClient(
    clock: ref.watch(clockProvider),
    isTrusted: (fingerprint) => peers.any(
      (peer) => Primitives.constantTimeEquals(
        Uint8List.sublistView(peer.publicKey, 0, 8),
        fingerprint,
      ),
    ),
  );

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
