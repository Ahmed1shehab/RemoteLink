import 'package:meta/meta.dart';

import 'calibration.dart';
import 'percentiles.dart';

/// Complete benchmark result for a latency harness run.
@immutable
final class LatencyResult {
  const LatencyResult({
    required this.mode,
    required this.timestamp,
    required this.sampleCount,
    required this.targetRateHz,
    required this.loadProfile,
    required this.percentiles,
    this.rawPercentiles,
    this.calibration,
    this.rawSamples,
    this.calibratedSamples,
  });

  /// Mode under which the benchmark ran: `transport`, `e2e`, or `reconnect`.
  final String mode;

  /// Time when benchmark was executed.
  final DateTime timestamp;

  /// Number of samples collected.
  final int sampleCount;

  /// Target sampling rate in Hz.
  final int targetRateHz;

  /// Active load profile during measurement.
  final String loadProfile;

  /// Effective (calibrated) percentiles.
  final PercentileStats percentiles;

  /// Uncalibrated raw percentiles (if calibration was performed).
  final PercentileStats? rawPercentiles;

  /// Local calibration results (if applicable).
  final CalibrationResult? calibration;

  /// Raw sample timings in microseconds.
  final List<int>? rawSamples;

  /// Calibrated sample timings in microseconds.
  final List<double>? calibratedSamples;

  double get p50Millis => percentiles.p50Millis;
  double get p95Millis => percentiles.p95Millis;
  double get p99Millis => percentiles.p99Millis;
  double get p999Millis => percentiles.p999Millis;
  double get maxMillis => percentiles.maxMillis;
  double get minMillis => percentiles.minMillis;

  double? get calibrationOverheadMicros => calibration?.overheadMicros;
  double? get calibrationOverheadMillis => calibration?.overheadMillis;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': mode,
      'timestamp': timestamp.toIso8601String(),
      'sampleCount': sampleCount,
      'targetRateHz': targetRateHz,
      'loadProfile': loadProfile,
      if (calibration != null) 'calibration': calibration!.toJson(),
      if (rawPercentiles != null) ...<String, Object?>{
        'rawPercentilesMicros': rawPercentiles!.toJson(),
        'rawPercentilesMillis': <String, double>{
          'p50': rawPercentiles!.p50Millis,
          'p95': rawPercentiles!.p95Millis,
          'p99': rawPercentiles!.p99Millis,
          'p999': rawPercentiles!.p999Millis,
          'max': rawPercentiles!.maxMillis,
          'min': rawPercentiles!.minMillis,
        },
      },
      'percentilesMicros': percentiles.toJson(),
      'percentilesMillis': <String, double>{
        'p50': percentiles.p50Millis,
        'p95': percentiles.p95Millis,
        'p99': percentiles.p99Millis,
        'p999': percentiles.p999Millis,
        'max': percentiles.maxMillis,
        'min': percentiles.minMillis,
      },
    };
  }

  factory LatencyResult.fromJson(Map<String, Object?> json) {
    final mode = json['mode'] as String? ?? 'unknown';
    final timestamp = json['timestamp'] != null
        ? DateTime.parse(json['timestamp'] as String)
        : DateTime.now();
    final sampleCount = (json['sampleCount'] as num?)?.toInt() ?? 0;
    final targetRateHz = (json['targetRateHz'] as num?)?.toInt() ?? 120;
    final loadProfile = json['loadProfile'] as String? ?? 'idle';

    final calibrationJson = json['calibration'] as Map<String, Object?>?;
    final calibration = calibrationJson != null
        ? CalibrationResult.fromJson(calibrationJson)
        : null;

    final rawJson = json['rawPercentilesMicros'] as Map<String, Object?>?;
    final rawPercentiles =
        rawJson != null ? PercentileStats.fromJson(rawJson) : null;

    final percentilesJson = (json['percentilesMicros'] ?? json['percentiles'])
        as Map<String, Object?>?;
    if (percentilesJson == null) {
      throw const FormatException('Missing percentiles in JSON');
    }
    final percentiles = PercentileStats.fromJson(percentilesJson);

    return LatencyResult(
      mode: mode,
      timestamp: timestamp,
      sampleCount: sampleCount,
      targetRateHz: targetRateHz,
      loadProfile: loadProfile,
      percentiles: percentiles,
      rawPercentiles: rawPercentiles,
      calibration: calibration,
    );
  }
}
