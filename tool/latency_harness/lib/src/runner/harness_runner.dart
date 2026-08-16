import 'dart:async';
import 'dart:io';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../formatters/json_formatter.dart';
import '../formatters/table_formatter.dart';
import '../load/load_profile.dart';
import '../stats/comparison.dart';
import '../stats/latency_result.dart';
import 'e2e_benchmark.dart';
import 'harness_config.dart';
import 'reconnect_benchmark.dart';
import 'transport_benchmark.dart';

/// Top-level coordinator for running latency benchmarks and regression comparisons.
final class HarnessRunner {
  HarnessRunner({
    required this.config,
    Clock? clock,
    InputBackend? input,
  })  : _clock = clock ?? SystemClock(),
        _input = input;

  final HarnessConfig config;
  final Clock _clock;
  final InputBackend? _input;

  static const Capabilities _clientCapabilities = Capabilities(
    Capabilities.mouse |
        Capabilities.keyboard |
        Capabilities.clipboardText |
        Capabilities.clipboardImage,
  );

  /// Runs the configured benchmark, writes outputs, compares against baseline if
  /// requested, and returns the exit code (0 for success, non-zero for regressions or failure).
  Future<int> run({
    void Function(String message)? onStatus,
  }) async {
    final identity = await DeviceIdentity.generate();
    final client = RemoteLinkClient(
      identity: identity,
      capabilities: _clientCapabilities,
      clock: _clock,
    );

    final target = ConnectionTarget(
      host: config.host,
      port: config.port,
    );

    try {
      onStatus?.call('Connecting to ${target.host}:${target.port}...');
      await client.connect(target);

      final session = await client.waitUntilConnected(timeout: config.timeout);
      onStatus?.call(
          'Connected to server. Running ${config.mode.name} benchmark...');

      final loadProfile = LoadProfiles.create(config.loadProfile);
      final LatencyResult result;

      switch (config.mode) {
        case HarnessMode.transport:
          final benchmark = TransportBenchmark(
            session: session,
            loadProfile: loadProfile,
            clock: _clock,
            sampleCount: config.sampleCount,
            targetRateHz: config.targetRateHz,
          );
          result = await benchmark.run(
            onProgress: (cur, total) {
              if (cur % 500 == 0 || cur == total) {
                onStatus?.call('Transport progress: $cur / $total samples');
              }
            },
          );

        case HarnessMode.e2e:
          final input = _input ?? NativeBackends.createInput();
          final benchmark = E2eBenchmark(
            session: session,
            input: input,
            loadProfile: loadProfile,
            clock: _clock,
            sampleCount: config.sampleCount,
            targetRateHz: config.targetRateHz,
            calibrationSamples: config.calibrationSamples,
          );
          result = await benchmark.run(
            onProgress: (phase, cur, total) {
              if (cur % 500 == 0 || cur == total || cur == 0) {
                onStatus?.call('$phase: $cur / $total');
              }
            },
          );

        case HarnessMode.reconnect:
          final benchmark = ReconnectBenchmark(
            client: client,
            target: target,
            clock: _clock,
            trials: config.sampleCount > 50 ? 10 : config.sampleCount,
            reconnectTimeout: config.timeout,
          );
          result = await benchmark.run(
            onProgress: (cur, total) {
              onStatus?.call('Reconnect trial: $cur / $total');
            },
          );
      }

      // Display primary result table
      stdout.writeln(TableFormatter.formatResult(result));

      // Handle JSON output if requested
      if (config.jsonPath != null) {
        final jsonString = JsonFormatter.formatResult(result);
        final file = File(config.jsonPath!);
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonString);
        stdout.writeln('JSON results saved to: ${config.jsonPath}');
      }

      // Handle baseline comparison if requested
      if (config.comparePath != null) {
        final baselineFile = File(config.comparePath!);
        if (!baselineFile.existsSync()) {
          stderr.writeln(
            'Error: Baseline file not found at ${config.comparePath}',
          );
          return 1;
        }

        final baselineContent = await baselineFile.readAsString();
        final baselineResult = JsonFormatter.parseResult(baselineContent);

        final comparison = BaselineComparison.compare(
          current: result,
          baseline: baselineResult,
          thresholdPercent: config.thresholdPercent,
        );

        stdout.writeln(TableFormatter.formatComparison(comparison));

        if (comparison.hasRegressions) {
          stderr.writeln(
            'Exiting with status 1 due to detected latency regressions.',
          );
          return 1;
        }
      }

      return 0;
    } finally {
      await client.dispose();
    }
  }
}
