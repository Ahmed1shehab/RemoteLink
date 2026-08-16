import 'package:meta/meta.dart';

/// Computes the exact [p]-th percentile (0.0 .. 100.0) from [sortedSamples]
/// using linear interpolation between closest ranks.
///
/// Throws [ArgumentError] if [sortedSamples] is empty or [p] is out of range.
double calculatePercentile(List<num> sortedSamples, double p) {
  if (sortedSamples.isEmpty) {
    throw ArgumentError.value(
      sortedSamples,
      'sortedSamples',
      'Cannot calculate percentile on an empty sample list',
    );
  }
  if (p < 0.0 || p > 100.0) {
    throw ArgumentError.value(
      p,
      'p',
      'Percentile rank must be in range [0.0, 100.0]',
    );
  }

  final length = sortedSamples.length;
  if (length == 1) return sortedSamples.first.toDouble();

  final rank = (p / 100.0) * (length - 1);
  final lowerIndex = rank.floor();
  final fraction = rank - lowerIndex;

  if (lowerIndex >= length - 1) {
    return sortedSamples.last.toDouble();
  }

  final lowerValue = sortedSamples[lowerIndex].toDouble();
  final upperValue = sortedSamples[lowerIndex + 1].toDouble();

  return lowerValue + fraction * (upperValue - lowerValue);
}

/// Exact percentile metrics computed over raw latency samples.
///
/// All values are stored in microseconds unless specifically accessed through
/// millisecond getters.
@immutable
final class PercentileStats {
  const PercentileStats({
    required this.count,
    required this.p50,
    required this.p95,
    required this.p99,
    required this.p999,
    required this.max,
    required this.min,
  });

  /// Computes exact percentiles from raw samples.
  ///
  /// Preserves every raw sample during sorting to produce exact rather than
  /// bucketed or estimated percentiles.
  factory PercentileStats.fromSamples(List<num> rawSamples) {
    if (rawSamples.isEmpty) {
      throw ArgumentError.value(
        rawSamples,
        'rawSamples',
        'Cannot compute percentiles from empty samples',
      );
    }

    final sorted = List<num>.from(rawSamples)..sort();
    return PercentileStats(
      count: sorted.length,
      p50: calculatePercentile(sorted, 50.0),
      p95: calculatePercentile(sorted, 95.0),
      p99: calculatePercentile(sorted, 99.0),
      p999: calculatePercentile(sorted, 99.9),
      max: sorted.last.toDouble(),
      min: sorted.first.toDouble(),
    );
  }

  factory PercentileStats.fromJson(Map<String, Object?> json) {
    return PercentileStats(
      count: (json['count'] as num?)?.toInt() ?? 0,
      p50: (json['p50'] as num).toDouble(),
      p95: (json['p95'] as num).toDouble(),
      p99: (json['p99'] as num).toDouble(),
      p999: (json['p999'] as num).toDouble(),
      max: (json['max'] as num).toDouble(),
      min: (json['min'] as num?)?.toDouble() ?? 0.0,
    );
  }

  final int count;

  /// 50th percentile (median) in microseconds.
  final double p50;

  /// 95th percentile in microseconds.
  final double p95;

  /// 99th percentile in microseconds.
  final double p99;

  /// 99.9th percentile in microseconds.
  final double p999;

  /// Maximum observed value in microseconds.
  final double max;

  /// Minimum observed value in microseconds.
  final double min;

  double get p50Millis => p50 / 1000.0;
  double get p95Millis => p95 / 1000.0;
  double get p99Millis => p99 / 1000.0;
  double get p999Millis => p999 / 1000.0;
  double get maxMillis => max / 1000.0;
  double get minMillis => min / 1000.0;

  Map<String, double> toMap() => <String, double>{
        'p50': p50,
        'p95': p95,
        'p99': p99,
        'p999': p999,
        'max': max,
        'min': min,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'count': count,
        'p50': p50,
        'p95': p95,
        'p99': p99,
        'p999': p999,
        'max': max,
        'min': min,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PercentileStats &&
          runtimeType == other.runtimeType &&
          count == other.count &&
          p50 == other.p50 &&
          p95 == other.p95 &&
          p99 == other.p99 &&
          p999 == other.p999 &&
          max == other.max &&
          min == other.min;

  @override
  int get hashCode => Object.hash(count, p50, p95, p99, p999, max, min);

  @override
  String toString() =>
      'PercentileStats(count: $count, p50: ${p50Millis.toStringAsFixed(3)}ms, '
      'p95: ${p95Millis.toStringAsFixed(3)}ms, p99: ${p99Millis.toStringAsFixed(3)}ms, '
      'p999: ${p999Millis.toStringAsFixed(3)}ms, max: ${maxMillis.toStringAsFixed(3)}ms)';
}
