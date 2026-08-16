import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../load/load_profile.dart';
import '../stats/latency_result.dart';
import '../stats/percentiles.dart';

/// Runs the transport-mode benchmark measuring Ping/Pong round-trip time.
final class TransportBenchmark {
  const TransportBenchmark({
    required this.session,
    required this.loadProfile,
    required this.clock,
    this.sampleCount = 10000,
    this.targetRateHz = 120,
    this.sampleTimeout = const Duration(seconds: 5),
  });

  final Session session;
  final LoadProfile loadProfile;
  final Clock clock;
  final int sampleCount;
  final int targetRateHz;
  final Duration sampleTimeout;

  /// Executes the transport benchmark and returns exact percentile metrics.
  Future<LatencyResult> run({
    void Function(int current, int total)? onProgress,
  }) async {
    if (session.state == SessionState.closed) {
      throw StateError('Cannot run transport benchmark on closed session');
    }

    final rawSamples = <int>[];
    final pongWaiters = Queue<Completer<int>>();

    final qualitySub = session.quality.listen((_) {
      if (pongWaiters.isNotEmpty) {
        final waiter = pongWaiters.removeFirst();
        if (!waiter.isCompleted) {
          waiter.complete(clock.monotonicMicros());
        }
      }
    });

    try {
      await loadProfile.start(session);

      final targetIntervalMicros = (1000000 / targetRateHz).round();

      for (var i = 0; i < sampleCount; i++) {
        if (session.state == SessionState.closed) {
          throw StateError('Session closed unexpectedly during benchmark');
        }

        final t0 = clock.monotonicMicros();
        final waiter = Completer<int>();
        pongWaiters.add(waiter);

        await session.send(Ping(senderMicros: t0));

        final int t1;
        try {
          t1 = await waiter.future.timeout(sampleTimeout);
        } on TimeoutException {
          throw TimeoutException(
            'Ping #$i timed out after ${sampleTimeout.inSeconds}s',
          );
        }

        final rtt = t1 - t0;
        if (rtt >= 0) {
          rawSamples.add(rtt);
        }

        onProgress?.call(i + 1, sampleCount);

        final elapsed = clock.monotonicMicros() - t0;
        final remainingDelay = math.max(0, targetIntervalMicros - elapsed);
        if (remainingDelay > 0 && i + 1 < sampleCount) {
          await clock.delay(Duration(microseconds: remainingDelay));
        }
      }
    } finally {
      await loadProfile.stop();
      await qualitySub.cancel();
    }

    if (rawSamples.isEmpty) {
      throw StateError('Benchmark collected 0 valid samples');
    }

    final percentiles = PercentileStats.fromSamples(rawSamples);

    return LatencyResult(
      mode: 'transport',
      timestamp: clock.now(),
      sampleCount: rawSamples.length,
      targetRateHz: targetRateHz,
      loadProfile: loadProfile.name,
      percentiles: percentiles,
      rawSamples: rawSamples,
    );
  }
}
