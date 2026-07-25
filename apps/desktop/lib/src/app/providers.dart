import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';

import '../domain/desktop_service.dart';

/// Riverpod, not Bloc.
///
/// The decision is recorded in `docs/adr/0002-state-management.md`; the short
/// version is that this app is mostly *streams of derived state* — connected
/// devices, latency, clipboard status, pairing requests — rather than a set of
/// complex state machines. Riverpod expresses that with a provider per stream
/// and compile-checked dependency injection, where Bloc would need an event
/// class, a state class, and a mapper for each one. The state machines that do
/// exist (handshake, reconnection) live in `rl_transport` as plain Dart and are
/// tested without any state-management library at all.

/// Where identity, trust, and settings are stored.
final appDirectoryProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationSupportDirectory();
  final directory = Directory('${base.path}/RemoteLink');
  if (!directory.existsSync()) {
    await directory.create(recursive: true);
  }
  return directory;
});

/// This computer's long-term identity, generated once and reused forever.
///
/// The private key currently lives in a file with owner-only permissions. That
/// is honest but not final: the OS keystores — DPAPI on Windows, Keychain on
/// macOS — are the correct home for it and are tracked as the first hardening
/// task after milestone 1. The threat this leaves open is an attacker who
/// already has read access to the user's profile, who at that point has larger
/// opportunities than impersonating a remote-control server.
final identityProvider = FutureProvider<DeviceIdentity>((ref) async {
  final directory = await ref.watch(appDirectoryProvider.future);
  final keyFile = File('${directory.path}/identity.key');

  if (keyFile.existsSync()) {
    final bytes = await keyFile.readAsBytes();
    return DeviceIdentity.fromPrivateKey(bytes);
  }

  final identity = await DeviceIdentity.generate();
  final privateKey = await identity.extractPrivateKey();
  await keyFile.writeAsBytes(privateKey, flush: true);

  // Owner-only. Best effort: the call is a no-op on filesystems without POSIX
  // permissions, which is why the keystore migration matters.
  if (!Platform.isWindows) {
    await Process.run('chmod', <String>['600', keyFile.path]);
  }

  Log.scoped('desktop.identity').info(
    'generated a new device identity',
    fields: <String, Object?>{'id': identity.id.value},
  );
  return identity;
});

/// Paired devices, persisted to disk.
final trustStoreProvider = FutureProvider<TrustStore>((ref) async {
  final directory = await ref.watch(appDirectoryProvider.future);
  final store = FileTrustStore(File('${directory.path}/trusted.json'));
  await store.load();
  ref.onDispose(store.dispose);
  return store;
});

/// The name shown to phones. Defaults to the machine's hostname.
final deviceNameProvider = StateProvider<String>((ref) => Platform.localHostname);

/// Injectable clock, so tests can drive timing without waiting.
final clockProvider = Provider<Clock>((ref) => SystemClock());

/// The running service.
final desktopServiceProvider = FutureProvider<DesktopService>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  final trustStore = await ref.watch(trustStoreProvider.future);
  final name = ref.watch(deviceNameProvider);

  final service = DesktopService(
    identity: identity,
    trustStore: trustStore,
    deviceName: name,
    appVersion: '0.1.0',
    clock: ref.watch(clockProvider),
  );

  await service.start();
  ref.onDispose(service.stop);
  return service;
});

/// Connected devices, live.
final connectedDevicesProvider = StreamProvider<List<ConnectedDevice>>((ref) {
  final service = ref.watch(desktopServiceProvider).valueOrNull;
  if (service == null) return const Stream<List<ConnectedDevice>>.empty();
  // The current list is emitted first so a widget that mounts after devices
  // connected still shows them, rather than waiting for the next change.
  return service.deviceChanges.asBroadcastStream();
});

/// Pairing requests waiting on the user.
final pairingRequestProvider = StreamProvider<PendingPairing>((ref) {
  final service = ref.watch(desktopServiceProvider).valueOrNull;
  if (service == null) return const Stream<PendingPairing>.empty();
  return service.pairingRequests;
});

/// Every paired device, connected or not.
final trustedPeersProvider = FutureProvider<List<TrustedPeer>>((ref) async {
  final store = await ref.watch(trustStoreProvider.future);
  return store.listPeers();
});

/// Whether input injection is currently possible.
///
/// False on macOS until Accessibility permission is granted, which is the
/// single most common reason a fresh install appears connected but does
/// nothing.
final inputAvailabilityProvider = Provider<({bool available, String? reason})>(
  (ref) {
    final service = ref.watch(desktopServiceProvider).valueOrNull;
    if (service == null) {
      return (available: false, reason: 'service is still starting');
    }
    return (
      available: service.inputAvailable,
      reason: service.inputUnavailableReason,
    );
  },
);

/// Which platform this build is on, for UI copy that differs by OS.
final platformProvider = Provider<PlatformKind>(
  (ref) => NativeBackends.currentPlatform,
);
