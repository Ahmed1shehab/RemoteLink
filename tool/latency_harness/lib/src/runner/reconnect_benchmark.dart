import 'dart:async';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../stats/latency_result.dart';
import '../stats/percentiles.dart';

/// Runs the reconnect benchmark measuring recovery time after connection drop.
final class ReconnectBenchmark {
  const ReconnectBenchmark({
    required this.client,
    required this.target,
    required this.clock,
    this.trials = 10,
    this.reconnectTimeout = const Duration(seconds: 15),
  });

  final RemoteLinkClient client;
  final ConnectionTarget target;
  final Clock clock;
  final int trials;
  final Duration reconnectTimeout;

  Future<LatencyResult> run({
    void Function(int current, int total)? onProgress,
  }) async {
    final samples = <int>[];

    // Ensure client is connected initially
    if (!client.isConnected) {
      await client.connect(target);
      await client.waitUntilConnected(timeout: reconnectTimeout);
    }

    for (var i = 0; i < trials; i++) {
      final session =
          await client.waitUntilConnected(timeout: reconnectTimeout);

      final nextSessionFuture = client.sessions.first;
      final t0 = clock.monotonicMicros();

      // Drop connection to trigger supervisor reconnect
      await session.close(reason: CloseReason.idleTimeout);

      try {
        await nextSessionFuture.timeout(reconnectTimeout);
      } on TimeoutException {
        throw TimeoutException(
          'Reconnection trial #$i failed to re-establish session within '
          '${reconnectTimeout.inSeconds}s',
        );
      }

      final t1 = clock.monotonicMicros();
      final elapsed = t1 - t0;
      if (elapsed >= 0) {
        samples.add(elapsed);
      }

      onProgress?.call(i + 1, trials);
    }

    if (samples.isEmpty) {
      throw StateError('Reconnect benchmark collected 0 valid samples');
    }

    final percentiles = PercentileStats.fromSamples(samples);

    return LatencyResult(
      mode: 'reconnect',
      timestamp: clock.now(),
      sampleCount: samples.length,
      targetRateHz: 0,
      loadProfile: 'none',
      percentiles: percentiles,
      rawSamples: samples,
    );
  }
}
