import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';

final class SpySystemInfoBackend implements SystemInfoBackend {
  int metricsCallCount = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<SystemMetrics> metrics() async {
    metricsCallCount++;
    return const SystemMetrics(
      batteryPercent: 90,
      isCharging: true,
      cpuPercent: 10.0,
      memoryPercent: 50.0,
      uptimeSeconds: 120,
    );
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('system watch performs zero collection when no device is connected',
      () async {
    final identity = await DeviceIdentity.generate();
    final trustStore = InMemoryTrustStore();
    final spySystemInfo = SpySystemInfoBackend();

    final service = DesktopService(
      identity: identity,
      trustStore: trustStore,
      deviceName: 'Test Computer',
      appVersion: '0.1.0',
      clock: SystemClock(),
      input: const UnsupportedInputBackend('test'),
      clipboardBackend: const UnsupportedClipboardBackend(),
      media: const UnsupportedMediaBackend(),
      systemInfo: spySystemInfo,
    );

    await service.start();

    // Verify no devices are connected.
    expect(service.devices, isEmpty);

    // Wait past the 5-second periodic timer tick.
    await Future<void>.delayed(const Duration(milliseconds: 5500));

    // Must be ZERO collection when no device is connected.
    expect(
      spySystemInfo.metricsCallCount,
      0,
      reason: 'Watcher must do ZERO work when _devices is empty',
    );

    await service.stop();
  });
}
