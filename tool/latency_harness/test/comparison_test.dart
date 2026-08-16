import 'package:latency_harness/latency_harness.dart';
import 'package:test/test.dart';

void main() {
  group('MetricComparison', () {
    test('computes delta and percentage change correctly', () {
      const metric = MetricComparison(
        metricName: 'p99',
        baselineMicros: 10000.0,
        currentMicros: 11500.0,
        thresholdPercent: 20.0,
      );

      expect(metric.deltaMicros, 1500.0);
      expect(metric.deltaMillis, 1.5);
      expect(metric.baselineMillis, 10.0);
      expect(metric.currentMillis, 11.5);
      expect(metric.percentageChange, closeTo(15.0, 1e-6));
      expect(metric.isRegression, isFalse);
      expect(metric.status, ComparisonStatus.pass);
    });

    test('flags regression when change exceeds threshold', () {
      const metric = MetricComparison(
        metricName: 'p99',
        baselineMicros: 10000.0,
        currentMicros: 12500.0,
        thresholdPercent: 20.0,
      );

      expect(metric.percentageChange, closeTo(25.0, 1e-6));
      expect(metric.isRegression, isTrue);
      expect(metric.status, ComparisonStatus.regression);
    });

    test('exact threshold boundary is not considered a regression', () {
      const metric = MetricComparison(
        metricName: 'p50',
        baselineMicros: 1000.0,
        currentMicros: 1200.0, // Exactly +20%
        thresholdPercent: 20.0,
      );

      expect(metric.percentageChange, closeTo(20.0, 1e-6));
      expect(metric.isRegression, isFalse);
    });

    test('handles latency improvements (negative delta)', () {
      const metric = MetricComparison(
        metricName: 'max',
        baselineMicros: 20000.0,
        currentMicros: 15000.0,
        thresholdPercent: 20.0,
      );

      expect(metric.deltaMicros, -5000.0);
      expect(metric.percentageChange, closeTo(-25.0, 1e-6));
      expect(metric.isRegression, isFalse);
      expect(metric.isImprovement, isTrue);
      expect(metric.status, ComparisonStatus.pass);
    });
  });

  group('BaselineComparison', () {
    LatencyResult createResult(PercentileStats stats) {
      return LatencyResult(
        mode: 'transport',
        timestamp: DateTime.utc(2026),
        sampleCount: 10000,
        targetRateHz: 120,
        loadProfile: 'idle',
        percentiles: stats,
      );
    }

    test('passes when all metrics are within threshold', () {
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
        p50: 2200.0, // +10% (pass)
        p95: 4400.0, // +10% (pass)
        p99: 7000.0, // +16.67% (pass)
        p999: 11000.0, // +10% (pass)
        max: 16000.0, // +6.67% (pass)
        min: 1000.0,
      );

      final comparison = BaselineComparison.compare(
        current: createResult(currentStats),
        baseline: createResult(baselineStats),
        thresholdPercent: 20.0,
      );

      expect(comparison.hasRegressions, isFalse);
      expect(comparison.regressionCount, 0);
    });

    test('fails when a single percentile regresses beyond threshold', () {
      const baselineStats = PercentileStats(
        count: 10000,
        p50: 2000.0,
        p95: 4000.0,
        p99: 6000.0,
        p999: 10000.0,
        max: 15000.0,
        min: 1000.0,
      );

      // Only p99 regressed from 6.0ms to 8.0ms (+33.3%)
      const currentStats = PercentileStats(
        count: 10000,
        p50: 2100.0, // +5% (pass)
        p95: 4100.0, // +2.5% (pass)
        p99: 8000.0, // +33.3% (FAIL)
        p999: 10500.0, // +5% (pass)
        max: 15500.0, // +3.3% (pass)
        min: 1000.0,
      );

      final comparison = BaselineComparison.compare(
        current: createResult(currentStats),
        baseline: createResult(baselineStats),
        thresholdPercent: 20.0,
      );

      expect(comparison.hasRegressions, isTrue);
      expect(comparison.regressionCount, 1);

      final p99Comparison =
          comparison.metrics.firstWhere((m) => m.metricName == 'p99');
      expect(p99Comparison.isRegression, isTrue);
      expect(p99Comparison.status, ComparisonStatus.regression);
    });

    test('counts multiple regressions correctly', () {
      const baselineStats = PercentileStats(
        count: 10000,
        p50: 2000.0,
        p95: 4000.0,
        p99: 6000.0,
        p999: 10000.0,
        max: 15000.0,
        min: 1000.0,
      );

      // p95 and max regressed
      const currentStats = PercentileStats(
        count: 10000,
        p50: 2000.0,
        p95: 5500.0, // +37.5% (FAIL)
        p99: 6500.0, // +8.3% (pass)
        p999: 11000.0, // +10% (pass)
        max: 22000.0, // +46.7% (FAIL)
        min: 1000.0,
      );

      final comparison = BaselineComparison.compare(
        current: createResult(currentStats),
        baseline: createResult(baselineStats),
        thresholdPercent: 20.0,
      );

      expect(comparison.hasRegressions, isTrue);
      expect(comparison.regressionCount, 2);
    });
  });
}
