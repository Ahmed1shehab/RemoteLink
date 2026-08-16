import 'package:meta/meta.dart';

import 'latency_result.dart';
import 'percentiles.dart';

/// Status of a single metric comparison against a baseline.
enum ComparisonStatus {
  pass,
  regression,
}

/// Comparison of a single percentile metric between a baseline and current run.
@immutable
final class MetricComparison {
  const MetricComparison({
    required this.metricName,
    required this.baselineMicros,
    required this.currentMicros,
    required this.thresholdPercent,
  });

  final String metricName;
  final double baselineMicros;
  final double currentMicros;
  final double thresholdPercent;

  double get baselineMillis => baselineMicros / 1000.0;
  double get currentMillis => currentMicros / 1000.0;

  double get deltaMicros => currentMicros - baselineMicros;
  double get deltaMillis => deltaMicros / 1000.0;

  /// Percentage change relative to the baseline.
  ///
  /// Positive means latency increased (worse); negative means decreased (better).
  double get percentageChange {
    if (baselineMicros <= 0) {
      return currentMicros > 0 ? 100.0 : 0.0;
    }
    return ((currentMicros - baselineMicros) / baselineMicros) * 100.0;
  }

  /// Whether this metric regressed beyond the permitted threshold.
  bool get isRegression => percentageChange > thresholdPercent;

  bool get isImprovement => percentageChange < 0;

  ComparisonStatus get status =>
      isRegression ? ComparisonStatus.regression : ComparisonStatus.pass;

  Map<String, Object?> toJson() => <String, Object?>{
        'metric': metricName,
        'baselineMicros': baselineMicros,
        'currentMicros': currentMicros,
        'baselineMillis': baselineMillis,
        'currentMillis': currentMillis,
        'deltaMillis': deltaMillis,
        'percentageChange': percentageChange,
        'thresholdPercent': thresholdPercent,
        'isRegression': isRegression,
        'status': status.name,
      };
}

/// Compares a benchmark run against a baseline file or previous run.
@immutable
final class BaselineComparison {
  const BaselineComparison({
    required this.current,
    required this.baseline,
    required this.thresholdPercent,
    required this.metrics,
  });

  final LatencyResult current;
  final LatencyResult baseline;
  final double thresholdPercent;
  final List<MetricComparison> metrics;

  /// Whether ANY tracked percentile regressed beyond [thresholdPercent].
  bool get hasRegressions => metrics.any((m) => m.isRegression);

  /// Number of regressed metrics.
  int get regressionCount => metrics.where((m) => m.isRegression).length;

  /// Compares [current] results against [baseline] using [thresholdPercent].
  factory BaselineComparison.compare({
    required LatencyResult current,
    required LatencyResult baseline,
    double thresholdPercent = 20.0,
  }) {
    final metricNames = <String>['p50', 'p95', 'p99', 'p999', 'max'];
    final comparisons = <MetricComparison>[];

    final currentMap = current.percentiles.toMap();
    final baselineMap = baseline.percentiles.toMap();

    for (final name in metricNames) {
      final cur = currentMap[name] ?? 0.0;
      final base = baselineMap[name] ?? 0.0;

      comparisons.add(
        MetricComparison(
          metricName: name,
          baselineMicros: base,
          currentMicros: cur,
          thresholdPercent: thresholdPercent,
        ),
      );
    }

    return BaselineComparison(
      current: current,
      baseline: baseline,
      thresholdPercent: thresholdPercent,
      metrics: comparisons,
    );
  }

  /// Compares two raw [PercentileStats] directly.
  static List<MetricComparison> comparePercentiles({
    required PercentileStats current,
    required PercentileStats baseline,
    double thresholdPercent = 20.0,
  }) {
    final metricNames = <String>['p50', 'p95', 'p99', 'p999', 'max'];
    final comparisons = <MetricComparison>[];

    final currentMap = current.toMap();
    final baselineMap = baseline.toMap();

    for (final name in metricNames) {
      final cur = currentMap[name] ?? 0.0;
      final base = baselineMap[name] ?? 0.0;

      comparisons.add(
        MetricComparison(
          metricName: name,
          baselineMicros: base,
          currentMicros: cur,
          thresholdPercent: thresholdPercent,
        ),
      );
    }

    return comparisons;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'thresholdPercent': thresholdPercent,
        'hasRegressions': hasRegressions,
        'regressionCount': regressionCount,
        'metrics': metrics.map((m) => m.toJson()).toList(),
      };
}
