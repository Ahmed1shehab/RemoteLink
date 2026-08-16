import 'dart:async';
import 'dart:math' as math;

import 'package:rl_core/rl_core.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../load/load_profile.dart';
import '../stats/calibration.dart';
import '../stats/latency_result.dart';
import '../stats/percentiles.dart';

/// Runs the End-to-End benchmark measuring network delivery + OS cursor arrival.
final class E2eBenchmark {
  const E2eBenchmark({
    required this.session,
    required this.input,
    required this.loadProfile,
    required this.clock,
    this.sampleCount = 10000,
    this.targetRateHz = 120,
    this.calibrationSamples = 1000,
    this.sampleTimeout = const Duration(seconds: 5),
  });

  final Session session;
  final InputBackend input;
  final LoadProfile loadProfile;
  final Clock clock;
  final int sampleCount;
  final int targetRateHz;
  final int calibrationSamples;
  final Duration sampleTimeout;

  /// Target normalized coordinates cycled through during measurement.
  static const List<(double, double)> _targetCoordinates = <(double, double)>[
    (0.25, 0.25),
    (0.75, 0.75),
    (0.25, 0.75),
    (0.75, 0.25),
  ];

  Future<LatencyResult> run({
    void Function(String phase, int current, int total)? onProgress,
  }) async {
    if (!input.isAvailable) {
      throw StateError(
        'Input backend is unavailable on this system: '
        '${input.unavailableReason ?? 'permission denied or unsupported OS'}. '
        'End-to-End mode requires local cursor read access.',
      );
    }
    if (session.state == SessionState.closed) {
      throw StateError('Cannot run E2E benchmark on closed session');
    }

    onProgress?.call(
        'Calibrating local move-and-read overhead...', 0, calibrationSamples);
    final calibration = calibrateLocalInput(
      input,
      clock: clock,
      sampleCount: calibrationSamples,
    );
    onProgress?.call(
      'Calibration complete: ${calibration.overheadMillis.toStringAsFixed(3)}ms overhead',
      calibrationSamples,
      calibrationSamples,
    );

    final rawSamples = <int>[];
    final bounds = input.virtualBounds;
    final width = bounds.width > 0 ? bounds.width : 1920;
    final height = bounds.height > 0 ? bounds.height : 1080;

    try {
      await loadProfile.start(session);

      final targetIntervalMicros = (1000000 / targetRateHz).round();

      for (var i = 0; i < sampleCount; i++) {
        if (session.state == SessionState.closed) {
          throw StateError('Session closed unexpectedly during benchmark');
        }

        final (nx, ny) = _targetCoordinates[i % _targetCoordinates.length];
        final expectedX = bounds.x + (nx * width).round();
        final expectedY = bounds.y + (ny * height).round();

        final t0 = clock.monotonicMicros();
        await session.send(MouseMoveAbsolute(x: nx, y: ny));

        // Poll for cursor arrival at expected physical coordinates
        while (true) {
          final (curX, curY) = input.cursorPosition;
          if ((curX - expectedX).abs() <= 1 && (curY - expectedY).abs() <= 1) {
            break;
          }

          final now = clock.monotonicMicros();
          if (now - t0 > sampleTimeout.inMicroseconds) {
            throw TimeoutException(
              'Cursor did not arrive at ($expectedX, $expectedY) within '
              '${sampleTimeout.inSeconds}s (current pos: ($curX, $curY))',
            );
          }
        }

        final t1 = clock.monotonicMicros();
        final elapsed = t1 - t0;
        if (elapsed >= 0) {
          rawSamples.add(elapsed);
        }

        onProgress?.call('Measuring E2E latency', i + 1, sampleCount);

        final totalElapsed = clock.monotonicMicros() - t0;
        final remainingDelay = math.max(0, targetIntervalMicros - totalElapsed);
        if (remainingDelay > 0 && i + 1 < sampleCount) {
          await clock.delay(Duration(microseconds: remainingDelay));
        }
      }
    } finally {
      await loadProfile.stop();
    }

    if (rawSamples.isEmpty) {
      throw StateError('Benchmark collected 0 valid samples');
    }

    final calibratedSamples = calibration.subtractFrom(rawSamples);
    final rawPercentiles = PercentileStats.fromSamples(rawSamples);
    final calibratedPercentiles =
        PercentileStats.fromSamples(calibratedSamples);

    return LatencyResult(
      mode: 'e2e',
      timestamp: clock.now(),
      sampleCount: rawSamples.length,
      targetRateHz: targetRateHz,
      loadProfile: loadProfile.name,
      percentiles: calibratedPercentiles,
      rawPercentiles: rawPercentiles,
      calibration: calibration,
      rawSamples: rawSamples,
      calibratedSamples: calibratedSamples,
    );
  }
}
