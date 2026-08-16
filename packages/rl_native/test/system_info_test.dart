import 'dart:io';

import 'package:rl_native/rl_native.dart';
import 'package:test/test.dart';

void main() {
  group('SystemMetrics', () {
    test('constructs with optional fields', () {
      const metrics = SystemMetrics(
        batteryPercent: 85,
        isCharging: true,
        cpuPercent: 15.5,
        memoryPercent: 42.0,
        uptimeSeconds: 3600,
      );

      expect(metrics.batteryPercent, 85);
      expect(metrics.isCharging, isTrue);
      expect(metrics.cpuPercent, 15.5);
      expect(metrics.memoryPercent, 42.0);
      expect(metrics.uptimeSeconds, 3600);
    });

    test('constructs with all fields null', () {
      const metrics = SystemMetrics();
      expect(metrics.batteryPercent, isNull);
      expect(metrics.isCharging, isNull);
      expect(metrics.cpuPercent, isNull);
      expect(metrics.memoryPercent, isNull);
      expect(metrics.uptimeSeconds, isNull);
    });
  });

  group('NativeBackends.createSystemInfo', () {
    test('creates backend for the current platform', () async {
      final backend = NativeBackends.createSystemInfo();
      if (Platform.isMacOS || Platform.isWindows) {
        expect(backend.isAvailable, isTrue);
        final metrics = await backend.metrics();
        if (Platform.isMacOS) {
          expect(metrics.uptimeSeconds, isNotNull);
          expect(metrics.uptimeSeconds, greaterThan(0));
          expect(metrics.memoryPercent, isNotNull);
          expect(metrics.memoryPercent, inInclusiveRange(0.0, 100.0));
        }
      }
      backend.dispose();
    });
  });
}
