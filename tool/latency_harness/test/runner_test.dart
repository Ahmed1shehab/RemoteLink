import 'dart:io';

import 'package:latency_harness/latency_harness.dart';
import 'package:test/test.dart';

void main() {
  group('HarnessRunner baseline comparison integration', () {
    late Directory tempDir;
    late File baselineFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('harness_test_');
      baselineFile = File('${tempDir.path}/baseline.json');

      final baselineResult = LatencyResult(
        mode: 'transport',
        timestamp: DateTime.utc(2026),
        sampleCount: 1000,
        targetRateHz: 120,
        loadProfile: 'idle',
        percentiles: const PercentileStats(
          count: 1000,
          p50: 2000.0,
          p95: 4000.0,
          p99: 6000.0,
          p999: 10000.0,
          max: 15000.0,
          min: 1000.0,
        ),
      );

      await baselineFile.writeAsString(
        JsonFormatter.formatResult(baselineResult),
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('baseline JSON file can be read and parsed accurately', () {
      expect(baselineFile.existsSync(), isTrue);
      final content = baselineFile.readAsStringSync();
      final parsed = JsonFormatter.parseResult(content);

      expect(parsed.mode, 'transport');
      expect(parsed.sampleCount, 1000);
      expect(parsed.percentiles.p50, 2000.0);
      expect(parsed.percentiles.p99, 6000.0);
    });

    test('BaselineComparison detects passing and failing thresholds accurately',
        () {
      final baseline =
          JsonFormatter.parseResult(baselineFile.readAsStringSync());

      final passingResult = LatencyResult(
        mode: 'transport',
        timestamp: DateTime.utc(2026),
        sampleCount: 1000,
        targetRateHz: 120,
        loadProfile: 'idle',
        percentiles: const PercentileStats(
          count: 1000,
          p50: 2100.0, // +5% (pass)
          p95: 4200.0, // +5% (pass)
          p99: 6300.0, // +5% (pass)
          p999: 10500.0, // +5% (pass)
          max: 15500.0, // +3.3% (pass)
          min: 1000.0,
        ),
      );

      final passingComp = BaselineComparison.compare(
        current: passingResult,
        baseline: baseline,
        thresholdPercent: 20.0,
      );

      expect(passingComp.hasRegressions, isFalse);
      expect(passingComp.regressionCount, 0);

      final regressedResult = LatencyResult(
        mode: 'transport',
        timestamp: DateTime.utc(2026),
        sampleCount: 1000,
        targetRateHz: 120,
        loadProfile: 'idle',
        percentiles: const PercentileStats(
          count: 1000,
          p50: 2100.0,
          p95: 4200.0,
          p99: 9000.0, // +50% regression (FAIL)
          p999: 10500.0,
          max: 15500.0,
          min: 1000.0,
        ),
      );

      final regressedComp = BaselineComparison.compare(
        current: regressedResult,
        baseline: baseline,
        thresholdPercent: 20.0,
      );

      expect(regressedComp.hasRegressions, isTrue);
      expect(regressedComp.regressionCount, 1);
    });
  });
}
