import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_native/rl_native.dart';

import 'percentiles.dart';

/// Subtracts [overheadMicros] from each sample in [rawSamples], clamping at 0.0.
List<double> applyCalibration(List<num> rawSamples, double overheadMicros) {
  return rawSamples
      .map((s) => math.max(0.0, s.toDouble() - overheadMicros))
      .toList();
}

/// Results of calibrating the local platform input move-and-read overhead.
@immutable
final class CalibrationResult {
  const CalibrationResult({
    required this.overheadMicros,
    required this.stats,
    this.samples = const <int>[],
  });

  /// The median (p50) cost in microseconds to perform a local move and read.
  final double overheadMicros;

  /// Full percentile statistics of the calibration loop.
  final PercentileStats stats;

  /// Raw calibration sample timings.
  final List<int> samples;

  double get overheadMillis => overheadMicros / 1000.0;

  /// Subtracts this calibration overhead from a list of raw latency measurements.
  List<double> subtractFrom(List<num> rawSamples) =>
      applyCalibration(rawSamples, overheadMicros);

  /// Subtracts this calibration overhead from a single raw latency value.
  double subtractFromValue(num rawValue) =>
      math.max(0.0, rawValue.toDouble() - overheadMicros);

  Map<String, Object?> toJson() => <String, Object?>{
        'overheadMicros': overheadMicros,
        'overheadMillis': overheadMillis,
        'stats': stats.toJson(),
      };

  factory CalibrationResult.fromJson(Map<String, Object?> json) {
    final overhead = (json['overheadMicros'] as num).toDouble();
    final statsJson = json['stats'] as Map<String, Object?>?;
    final stats = statsJson != null
        ? PercentileStats.fromJson(statsJson)
        : PercentileStats(
            count: 0,
            p50: overhead,
            p95: overhead,
            p99: overhead,
            p999: overhead,
            max: overhead,
            min: overhead,
          );
    return CalibrationResult(
      overheadMicros: overhead,
      stats: stats,
    );
  }
}

/// Measures the local no-op move and read cursor position overhead.
///
/// Moving and reading back the cursor position via OS APIs (such as Quartz Event
/// Services or Win32 GetCursorPos) incurs non-zero time. Without subtracting
/// this overhead, an end-to-end benchmark would measure the harness itself.
CalibrationResult calibrateLocalInput(
  InputBackend input, {
  required Clock clock,
  int sampleCount = 1000,
}) {
  if (!input.isAvailable) {
    throw StateError(
      'Cannot calibrate input backend: '
      '${input.unavailableReason ?? 'input is unavailable'}',
    );
  }

  final bounds = input.virtualBounds;
  final centerX = bounds.x + (bounds.width ~/ 2);
  final centerY = bounds.y + (bounds.height ~/ 2);

  final samples = <int>[];

  for (var i = 0; i < sampleCount; i++) {
    final t0 = clock.monotonicMicros();
    input.moveCursorTo(centerX, centerY);
    // Read back cursor position
    input.cursorPosition;
    final t1 = clock.monotonicMicros();
    final elapsed = t1 - t0;
    if (elapsed >= 0) {
      samples.add(elapsed);
    }
  }

  if (samples.isEmpty) {
    throw StateError('Calibration produced zero valid samples');
  }

  final stats = PercentileStats.fromSamples(samples);
  return CalibrationResult(
    overheadMicros: stats.p50,
    stats: stats,
    samples: samples,
  );
}
