import 'package:latency_harness/latency_harness.dart';
import 'package:test/test.dart';

void main() {
  group('calculatePercentile', () {
    test('computes exact percentiles on 0..100 array', () {
      final samples = List<double>.generate(101, (i) => i.toDouble());

      expect(calculatePercentile(samples, 0.0), closeTo(0.0, 1e-9));
      expect(calculatePercentile(samples, 50.0), closeTo(50.0, 1e-9));
      expect(calculatePercentile(samples, 95.0), closeTo(95.0, 1e-9));
      expect(calculatePercentile(samples, 99.0), closeTo(99.0, 1e-9));
      expect(calculatePercentile(samples, 99.9), closeTo(99.9, 1e-9));
      expect(calculatePercentile(samples, 100.0), closeTo(100.0, 1e-9));
    });

    test('computes exact percentiles on 1..1000 array', () {
      final samples = List<double>.generate(1000, (i) => (i + 1).toDouble());

      // Linear rank: r = p/100 * 999
      // p50: r = 499.5 -> samples[499] + 0.5 * (samples[500] - samples[499]) = 500 + 0.5 = 500.5
      expect(calculatePercentile(samples, 50.0), closeTo(500.5, 1e-9));
      // p95: r = 949.05 -> 950.05
      expect(calculatePercentile(samples, 95.0), closeTo(950.05, 1e-9));
      // p99: r = 989.01 -> 990.01
      expect(calculatePercentile(samples, 99.0), closeTo(990.01, 1e-9));
      // p99.9: r = 998.001 -> 999.001
      expect(calculatePercentile(samples, 99.9), closeTo(999.001, 1e-9));
      expect(calculatePercentile(samples, 100.0), closeTo(1000.0, 1e-9));
    });

    test('handles single-element array', () {
      final samples = <double>[42.0];
      expect(calculatePercentile(samples, 0.0), 42.0);
      expect(calculatePercentile(samples, 50.0), 42.0);
      expect(calculatePercentile(samples, 99.0), 42.0);
      expect(calculatePercentile(samples, 100.0), 42.0);
    });

    test('handles array with identical elements', () {
      final samples = List<double>.filled(50, 15.0);
      expect(calculatePercentile(samples, 50.0), 15.0);
      expect(calculatePercentile(samples, 99.0), 15.0);
    });

    test('throws ArgumentError on empty list', () {
      expect(
        () => calculatePercentile(<double>[], 50.0),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on out-of-range percentile rank', () {
      final samples = <double>[1.0, 2.0, 3.0];
      expect(() => calculatePercentile(samples, -1.0), throwsArgumentError);
      expect(() => calculatePercentile(samples, 100.1), throwsArgumentError);
    });
  });

  group('PercentileStats', () {
    test('sorts raw input and computes exact percentiles', () {
      // Unsorted array with tail latency
      final raw = <int>[
        1000,
        2000,
        1500,
        1200,
        1100,
        1800,
        1300,
        1400,
        1600,
        20000,
      ];

      final stats = PercentileStats.fromSamples(raw);

      expect(stats.count, 10);
      expect(stats.min, 1000.0);
      expect(stats.max, 20000.0);
      expect(stats.minMillis, 1.0);
      expect(stats.maxMillis, 20.0);
      expect(stats.p50, greaterThanOrEqualTo(1400.0));
      expect(stats.p50, lessThanOrEqualTo(1500.0));
      expect(stats.p99, greaterThan(15000.0));
    });

    test('JSON serialization round-trips cleanly', () {
      const original = PercentileStats(
        count: 100,
        p50: 2500.0,
        p95: 4200.0,
        p99: 8100.0,
        p999: 12500.0,
        max: 18000.0,
        min: 1100.0,
      );

      final json = original.toJson();
      final restored = PercentileStats.fromJson(json);

      expect(restored, equals(original));
      expect(restored.p50Millis, 2.5);
      expect(restored.p95Millis, 4.2);
      expect(restored.p99Millis, 8.1);
      expect(restored.p999Millis, 12.5);
      expect(restored.maxMillis, 18.0);
      expect(restored.minMillis, 1.1);
    });

    test('equality and hashCode work correctly', () {
      const a = PercentileStats(
        count: 10,
        p50: 100,
        p95: 200,
        p99: 300,
        p999: 400,
        max: 500,
        min: 50,
      );
      const b = PercentileStats(
        count: 10,
        p50: 100,
        p95: 200,
        p99: 300,
        p999: 400,
        max: 500,
        min: 50,
      );
      const c = PercentileStats(
        count: 10,
        p50: 101,
        p95: 200,
        p99: 300,
        p999: 400,
        max: 500,
        min: 50,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
