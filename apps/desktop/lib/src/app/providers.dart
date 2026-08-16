import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';

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
final deviceNameProvider =
    StateProvider<String>((ref) => Platform.localHostname);

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

/// The service state rendered by the home screen.
///
/// Keeping this projection separate from [desktopServiceProvider] lets the UI
/// be exercised without constructing the native-backed service. Commands still
/// reach the service when the user invokes them, while passive rendering only
/// depends on these inert values.
final desktopStatusProvider = FutureProvider<DesktopStatus>((ref) async {
  final service = await ref.watch(desktopServiceProvider.future);
  return DesktopStatus(
    isRunning: service.isRunning,
    deviceName: service.deviceName,
    boundPort: service.boundPort,
    localAddresses: service.localAddresses,
    deviceId: service.identity.id.value,
  );
});

/// Render-only state exposed by [desktopStatusProvider].
final class DesktopStatus {
  const DesktopStatus({
    required this.isRunning,
    required this.deviceName,
    required this.boundPort,
    required this.localAddresses,
    required this.deviceId,
  });

  final bool isRunning;
  final String deviceName;
  final int boundPort;
  final List<String> localAddresses;
  final String deviceId;
}

/// Connected devices, live.
final connectedDevicesProvider =
    StreamProvider<List<ConnectedDevice>>((ref) async* {
  final service = await ref.watch(desktopServiceProvider.future);

  // The current snapshot is emitted before the change stream. `deviceChanges`
  // only fires when something *changes*, so without this the provider sits in
  // its loading state forever on a quiet network — and the UI shows a spinner
  // caption instead of the empty state that explains what to do next.
  yield service.devices;
  yield* service.deviceChanges;
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
/// A [StreamProvider], not a plain [Provider].
///
/// Permission can be granted while the app is running, and a plain provider is
/// computed once and never re-evaluated — so the banner would stay up forever
/// even after the user did what it asked. That is a particularly bad failure:
/// the user follows the instructions, nothing changes, and they conclude the
/// app is broken.
final inputAvailabilityProvider =
    StreamProvider<({bool available, String? reason})>((ref) async* {
  final service = await ref.watch(desktopServiceProvider.future);

  yield (
    available: service.inputAvailable,
    reason: service.inputUnavailableReason,
  );

  await for (final _ in service.inputAvailabilityChanges) {
    yield (
      available: service.inputAvailable,
      reason: service.inputUnavailableReason,
    );
  }
});

/// Which platform this build is on, for UI copy that differs by OS.
final platformProvider = Provider<PlatformKind>(
  (ref) => NativeBackends.currentPlatform,
);

/// In-memory log buffer backing the diagnostics panel.
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

/// Diagnostic snapshot provider for the diagnostics panel.
///
/// Keeping this projection separate from [desktopServiceProvider] lets the UI
/// be exercised without constructing the native-backed service.
final desktopDiagnosticsProvider =
    StreamProvider<DiagnosticsInfo>((ref) async* {
  final service = await ref.watch(desktopServiceProvider.future);

  DiagnosticsInfo buildSnapshot() => DiagnosticsInfo(
        serviceStatus: DesktopStatus(
          isRunning: service.isRunning,
          deviceName: service.deviceName,
          boundPort: service.boundPort,
          localAddresses: service.localAddresses,
          deviceId: service.identity.id.value,
        ),
        dispatcherCounters: DispatcherCounters(
          applied: service.commandAppliedCount,
          denied: service.commandDeniedCount,
          unsupported: service.commandUnsupportedCount,
        ),
        backends: BackendAvailability(
          input: BackendDiagnostic(
            name: 'Input injection',
            isAvailable: service.inputAvailable,
            unavailableReason: service.inputUnavailableReason,
          ),
          clipboard: BackendDiagnostic(
            name: 'Clipboard sync',
            isAvailable: service.clipboardAvailable,
            unavailableReason: service.clipboardUnavailableReason,
          ),
          media: BackendDiagnostic(
            name: 'Media control',
            isAvailable: service.mediaAvailable,
            unavailableReason: service.mediaUnavailableReason,
          ),
        ),
        devices: <DeviceDiagnostic>[
          for (final device in service.devices)
            DeviceDiagnostic(
              id: device.id.value,
              name: device.name,
              address: device.address,
              tier: device.tier,
              roundTripMillis: device.quality.roundTripMillis,
              qualityBars: device.quality.bars,
              awaitingPairing: device.awaitingPairing,
            ),
        ],
      );

  yield buildSnapshot();

  final controller = StreamController<void>();
  final sub1 = service.deviceChanges.listen((_) => controller.add(null));
  final sub2 =
      service.inputAvailabilityChanges.listen((_) => controller.add(null));
  final timer =
      Timer.periodic(const Duration(seconds: 1), (_) => controller.add(null));

  ref.onDispose(() {
    sub1.cancel();
    sub2.cancel();
    timer.cancel();
    controller.close();
  });

  await for (final _ in controller.stream) {
    yield buildSnapshot();
  }
});

/// Diagnostic snapshot data structure.
final class DiagnosticsInfo {
  const DiagnosticsInfo({
    required this.serviceStatus,
    required this.dispatcherCounters,
    required this.backends,
    required this.devices,
  });

  final DesktopStatus serviceStatus;
  final DispatcherCounters dispatcherCounters;
  final BackendAvailability backends;
  final List<DeviceDiagnostic> devices;
}

/// Statistics from [CommandDispatcher].
final class DispatcherCounters {
  const DispatcherCounters({
    required this.applied,
    required this.denied,
    required this.unsupported,
  });

  final int applied;
  final int denied;
  final int unsupported;
}

/// Status and optional unavailable reason for a single native backend.
final class BackendDiagnostic {
  const BackendDiagnostic({
    required this.name,
    required this.isAvailable,
    this.unavailableReason,
  });

  final String name;
  final bool isAvailable;
  final String? unavailableReason;
}

/// Availability of all platform backends.
final class BackendAvailability {
  const BackendAvailability({
    required this.input,
    required this.clipboard,
    required this.media,
  });

  final BackendDiagnostic input;
  final BackendDiagnostic clipboard;
  final BackendDiagnostic media;
}

/// Diagnostic view of a connected peer device.
final class DeviceDiagnostic {
  const DeviceDiagnostic({
    required this.id,
    required this.name,
    required this.address,
    required this.tier,
    required this.roundTripMillis,
    required this.qualityBars,
    this.awaitingPairing = false,
  });

  final String id;
  final String name;
  final String address;
  final PermissionTier tier;
  final double roundTripMillis;
  final int qualityBars;
  final bool awaitingPairing;
}
