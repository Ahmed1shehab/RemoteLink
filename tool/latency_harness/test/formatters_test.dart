import 'dart:convert';

import 'package:latency_harness/latency_harness.dart';
import 'package:test/test.dart';

void main() {
  group('TableFormatter', () {
    test('formats uncalibrated LatencyResult containing all percentiles', () {
      const stats = PercentileStats(
        count: 10000,
        p50: 2500.0,
        p95: 4100.0,
        p99: 7800.0,
        p999: 12000.0,
        max: 18500.0,
        min: 1200.0,
      );

      final result = LatencyResult(
        mode: 'transport',
        timestamp: DateTime.utc(2026),
        sampleCount: 10000,
        targetRateHz: 120,
        loadProfile: 'idle',
        percentiles: stats,
      );

      final output = TableFormatter.formatResult(result);

      expect(output, contains('RemoteLink Latency Harness Benchmark Report'));
      expect(output, contains('TRANSPORT'));
      expect(output, contains('p50 (Median)'));
      expect(output, contains('2.500 ms'));
      expect(output, contains('p95'));
      expect(output, contains('4.100 ms'));
      expect(output, contains('p99'));
      expect(output, contains('7.800 ms'));
      expect(output, contains('p99.9'));
      expect(output, contains('12.000 ms'));
      expect(output, contains('Max'));
      expect(output, contains('18.500 ms'));
    });

    test(
        'formats calibrated LatencyResult with both raw and calibrated columns',
        () {
      const rawStats = PercentileStats(
        count: 10000,
        p50: 2550.0,
        p95: 4150.0,
        p99: 7850.0,
        p999: 12050.0,
        max: 18550.0,
        min: 1250.0,
      );

      const calStats = PercentileStats(
        count: 10000,
        p50: 2500.0,
        p95: 4100.0,
        p99: 7800.0,
        p999: 12000.0,
        max: 18500.0,
        min: 1200.0,
      );

      const calibration = CalibrationResult(
        overheadMicros: 50.0,
        stats: PercentileStats(
          count: 1000,
          p50: 50.0,
          p95: 55.0,
          p99: 60.0,
          p999: 70.0,
          max: 80.0,
          min: 40.0,
        ),
      );

      final result = LatencyResult(
        mode: 'e2e',
        timestamp: DateTime.utc(2026),
        sampleCount: 10000,
        targetRateHz: 120,
        loadProfile: 'idle',
        percentiles: calStats,
        rawPercentiles: rawStats,
        calibration: calibration,
      );

      final output = TableFormatter.formatResult(result);

      expect(output, contains('E2E'));
      expect(output,
          contains('Calibration Overhead: 0.050 ms (50.0 µs subtracted)'));
      expect(output, contains('Raw Latency'));
      expect(output, contains('Calibrated Latency'));
      expect(output, contains('2.550 ms'));
      expect(output, contains('2.500 ms'));
    });

    test('formats BaselineComparison table', () {
      const baselineStats = PercentileStats(
        count: 10000,
        p50: 2000.0,
        p95: 4000.0,
        p99: 6000.0,
        p999: 10000.0,
        max: 15000.0,
        min: 1000.0,
      );

      const currentStats = PercentileStats(
        count: 10000,
        p50: 2100.0,
        p95: 4100.0,
        p99: 8000.0, // Regressed +33.3%
        p999: 10500.0,
        max: 15500.0,
        min: 1000.0,
      );

      final comparison = BaselineComparison.compare(
        current: LatencyResult(
          mode: 'transport',
          timestamp: DateTime.utc(2026),
          sampleCount: 10000,
          targetRateHz: 120,
          loadProfile: 'idle',
          percentiles: currentStats,
        ),
        baseline: LatencyResult(
          mode: 'transport',
          timestamp: DateTime.utc(2026),
          sampleCount: 10000,
          targetRateHz: 120,
          loadProfile: 'idle',
          percentiles: baselineStats,
        ),
        thresholdPercent: 20.0,
      );

      final output = TableFormatter.formatComparison(comparison);

      expect(output,
          contains('Baseline Comparison (Regression Threshold: +20.0%)'));
      expect(output, contains('p50'));
      expect(output, contains('p99'));
      expect(output, contains('FAIL (REG)'));
      expect(output, contains('RESULT: FAILED'));
    });
  });

  group('JsonFormatter', () {
    test('serializes and parses LatencyResult round-trip', () {
      const stats = PercentileStats(
        count: 10000,
        p50: 2500.0,
        p95: 4100.0,
        p99: 7800.0,
        p999: 12000.0,
        max: 18500.0,
        min: 1200.0,
      );

      final original = LatencyResult(
        mode: 'transport',
        timestamp: DateTime.utc(2026, 8, 16, 12, 0, 0),
        sampleCount: 10000,
        targetRateHz: 120,
        loadProfile: 'idle',
        percentiles: stats,
      );

      final jsonString = JsonFormatter.formatResult(original);
      expect(jsonDecode(jsonString), isA<Map<String, Object?>>());

      final restored = JsonFormatter.parseResult(jsonString);

      expect(restored.mode, original.mode);
      expect(restored.sampleCount, original.sampleCount);
      expect(restored.targetRateHz, original.targetRateHz);
      expect(restored.loadProfile, original.loadProfile);
      expect(restored.percentiles.p50, original.percentiles.p50);
      expect(restored.percentiles.p99, original.percentiles.p99);
      expect(restored.percentiles.max, original.percentiles.max);
    });

    test('serializes BaselineComparison to valid JSON', () {
      const stats = PercentileStats(
        count: 100,
        p50: 100,
        p95: 200,
        p99: 300,
        p999: 400,
        max: 500,
        min: 50,
      );

      final result = LatencyResult(
        mode: 'transport',
        timestamp: DateTime.utc(2026),
        sampleCount: 100,
        targetRateHz: 120,
        loadProfile: 'idle',
        percentiles: stats,
      );

      final comparison = BaselineComparison.compare(
        current: result,
        baseline: result,
        thresholdPercent: 20.0,
      );

      final jsonString = JsonFormatter.formatComparison(comparison);
      final dynamic decoded = jsonDecode(jsonString);

      expect(decoded, isA<Map<String, Object?>>());
      expect((decoded as Map<String, Object?>)['hasRegressions'], isFalse);
    });
  });
}
