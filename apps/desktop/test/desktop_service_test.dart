import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// Counts how many times the host was actually asked for metrics.
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
      cpuPercent: 10,
      memoryPercent: 50,
      uptimeSeconds: 120,
    );
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Builds a service with every native backend stubbed out.
  ///
  /// Note this never calls `start()`. Starting binds a TCP listener, a UDP
  /// multicast beacon on a fixed port, and a Bonjour advertiser — which
  /// collide as soon as two test runs overlap, and which have nothing to do
  /// with the property under test.
  Future<(DesktopService, SpySystemInfoBackend)> buildService() async {
    final spy = SpySystemInfoBackend();
    final service = DesktopService(
      identity: await DeviceIdentity.generate(),
      trustStore: InMemoryTrustStore(),
      deviceName: 'Test Computer',
      appVersion: '0.1.0',
      clock: SystemClock(),
      input: const UnsupportedInputBackend('test'),
      clipboardBackend: const UnsupportedClipboardBackend(),
      media: const UnsupportedMediaBackend(),
      brightness: const UnsupportedBrightnessBackend('test'),
      systemInfo: spy,
    );
    return (service, spy);
  }

  test('the telemetry watcher does no work when no device is connected',
      () async {
    final (service, spy) = await buildService();

    expect(service.devices, isEmpty);

    // Drive the watcher's own tick directly, several times over. The timer
    // calls exactly this method, so the guarantee is being asserted against the
    // real code path rather than a reimplementation of it.
    for (var i = 0; i < 5; i++) {
      await service.telemetryTick();
    }

    expect(
      spy.metricsCallCount,
      0,
      reason: 'the host must not be polled while nobody is watching — that is '
          'battery cost for nobody\'s benefit',
    );
  });

  group('buildCapabilities gesture advertising', () {
    test('advertises Capabilities.gestures only when gesturesAvailable is true',
        () {
      final capsWithoutGestures = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        gesturesAvailable: false,
      );
      expect(capsWithoutGestures.has(Capabilities.gestures), isFalse);

      final capsWithGestures = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        gesturesAvailable: true,
      );
      expect(capsWithGestures.has(Capabilities.gestures), isTrue);
    });

    test(
        'currentCapabilities does not advertise gestures for unsupported backend',
        () async {
      final (service, _) = await buildService();
      expect(service.currentCapabilities.has(Capabilities.gestures), isFalse);
    });
  });

  group('buildCapabilities brightness advertising', () {
    test(
        'advertises Capabilities.brightness only when brightnessAvailable is true',
        () {
      final capsWithoutBrightness = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        brightnessAvailable: false,
      );
      expect(capsWithoutBrightness.has(Capabilities.brightness), isFalse);

      final capsWithBrightness = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        brightnessAvailable: true,
      );
      expect(capsWithBrightness.has(Capabilities.brightness), isTrue);
    });

    test(
        'currentCapabilities does not advertise brightness for unsupported backend',
        () async {
      final (service, _) = await buildService();
      expect(service.currentCapabilities.has(Capabilities.brightness), isFalse);
    });
  });
}
