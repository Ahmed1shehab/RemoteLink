import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotelink_desktop/src/app/providers.dart';
import 'package:remotelink_desktop/src/domain/command_dispatcher.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';
import 'package:remotelink_desktop/src/domain/transfer_model.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// Fake diagnostics snapshot for widget testing.
const fakeDiagnostics = DiagnosticsInfo(
  serviceStatus: const DesktopStatus(
    isRunning: true,
    deviceName: 'Test computer',
    boundPort: 41234,
    localAddresses: <String>['192.168.1.100', '10.0.0.5'],
    deviceId: 'test-device-id',
  ),
  dispatcherCounters: const DispatcherCounters(
    applied: 128,
    denied: 7,
    unsupported: 3,
  ),
  backends: const BackendAvailability(
    input: BackendDiagnostic(
      name: 'Input injection',
      isAvailable: false,
      unavailableReason:
          'RemoteLink needs Accessibility permission. Enable it in System Settings.',
    ),
    clipboard: BackendDiagnostic(
      name: 'Clipboard sync',
      isAvailable: true,
      unavailableReason: null,
    ),
    media: BackendDiagnostic(
      name: 'Media control',
      isAvailable: false,
      unavailableReason: 'Media control is not supported on this platform',
    ),
  ),
  devices: const <DeviceDiagnostic>[
    DeviceDiagnostic(
      id: 'test-phone-1',
      name: 'Pixel 8 Pro',
      address: '192.168.1.50',
      tier: PermissionTier.standard,
      roundTripMillis: 12.5,
      qualityBars: 4,
    ),
  ],
);

/// Fake memory log sink pre-populated with test log records.
MemoryLogSink createFakeMemoryLogSink() {
  final sink = MemoryLogSink();
  sink.write(
    LogRecord(
      level: LogLevel.info,
      scope: 'desktop.service',
      message: 'desktop service started',
      time: DateTime(2026, 8, 16, 12, 0, 0),
      fields: const <String, Object?>{'port': 41234},
    ),
  );
  sink.write(
    LogRecord(
      level: LogLevel.debug,
      scope: 'desktop.dispatcher',
      message: 'dispatching MouseMove',
      time: DateTime(2026, 8, 16, 12, 0, 1),
    ),
  );
  sink.write(
    LogRecord(
      level: LogLevel.warn,
      scope: 'desktop.service',
      message: 'rate limit warning',
      time: DateTime(2026, 8, 16, 12, 0, 2),
    ),
  );
  sink.write(
    LogRecord(
      level: LogLevel.error,
      scope: 'native.input',
      message: 'permission missing error',
      time: DateTime(2026, 8, 16, 12, 0, 3),
    ),
  );
  return sink;
}

final fakeMemoryLogSink = createFakeMemoryLogSink();

/// Safe provider state for rendering the desktop home screen in widget tests.
///
/// These overrides deliberately stop at the UI-facing providers. In
/// particular, they never construct [DesktopService], whose constructor loads
/// native backends and whose startup opens real network services.
final List<Override> desktopHomeOverrides = <Override>[
  desktopStatusProvider.overrideWith(
    (ref) async => const DesktopStatus(
      isRunning: false,
      deviceName: 'Test computer',
      boundPort: 41234,
      localAddresses: <String>[],
      deviceId: 'test-device-id',
    ),
  ),
  connectedDevicesProvider.overrideWith(
    (ref) => Stream<List<ConnectedDevice>>.value(const <ConnectedDevice>[]),
  ),
  inputAvailabilityProvider.overrideWith(
    (ref) => Stream<({bool available, String? reason})>.value(
      (available: true, reason: null),
    ),
  ),
  pairingRequestProvider.overrideWith(
    (ref) => const Stream<PendingPairing>.empty(),
  ),
  incomingTransferRequestProvider.overrideWith(
    (ref) => const Stream<PendingIncomingTransfer>.empty(),
  ),
  transfersProvider.overrideWith(
    (ref) => Stream<List<TransferRecord>>.value(const <TransferRecord>[]),
  ),
  desktopDiagnosticsProvider.overrideWith(
    (ref) => Stream<DiagnosticsInfo>.value(fakeDiagnostics),
  ),
  memoryLogSinkProvider.overrideWithValue(fakeMemoryLogSink),
];

/// Helper to create a [CommandDispatcher] for testing.
CommandDispatcher createTestDispatcher({
  InputBackend? input,
  PlatformKind platform = PlatformKind.macos,
  void Function(PowerCommand)? onPowerCommand,
  void Function(LaunchApplication)? onLaunchApplication,
  void Function(OpenUrl)? onOpenUrl,
  void Function(RunCommand)? onRunCommand,
  void Function(ClipboardUpdate)? onClipboardUpdate,
  void Function(MediaCommand)? onMediaCommand,
  void Function(VolumeCommand)? onVolumeCommand,
  void Function(BrightnessCommand)? onBrightnessCommand,
  void Function(DeviceRename)? onDeviceRename,
  void Function(Message)? onFileTransferMessage,
}) =>
    CommandDispatcher(
      input: input ?? const UnsupportedInputBackend('test'),
      platform: platform,
      onPowerCommand: onPowerCommand ?? (_) {},
      onLaunchApplication: onLaunchApplication ?? (_) {},
      onOpenUrl: onOpenUrl ?? (_) {},
      onRunCommand: onRunCommand ?? (_) {},
      onClipboardUpdate: onClipboardUpdate ?? (_) {},
      onMediaCommand: onMediaCommand ?? (_) {},
      onVolumeCommand: onVolumeCommand ?? (_) {},
      onBrightnessCommand: onBrightnessCommand ?? (_) {},
      onDeviceRename: onDeviceRename ?? (_) {},
      onFileTransferMessage: onFileTransferMessage ?? (_) {},
    );
