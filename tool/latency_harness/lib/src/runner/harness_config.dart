import 'package:args/args.dart';
import 'package:meta/meta.dart';

import '../load/load_profile.dart';

/// Supported measurement modes for the latency harness.
enum HarnessMode {
  transport('transport', 'Measures network Ping/Pong round-trip time'),
  e2e('e2e',
      'Measures end-to-end cursor injection to OS screen arrival with calibration'),
  reconnect('reconnect',
      'Measures connection recovery and session re-establishment time');

  const HarnessMode(this.cliName, this.description);

  final String cliName;
  final String description;

  static HarnessMode fromName(String name) {
    return switch (name.toLowerCase()) {
      'transport' || 'ping' || 'network' => HarnessMode.transport,
      'e2e' || 'end-to-end' || 'cursor' => HarnessMode.e2e,
      'reconnect' || 'recovery' => HarnessMode.reconnect,
      _ => throw ArgumentError.value(
          name,
          'mode',
          'Unknown mode "$name". Valid modes: transport, e2e, reconnect',
        ),
    };
  }
}

/// CLI configuration options for a latency harness invocation.
@immutable
final class HarnessConfig {
  const HarnessConfig({
    this.mode = HarnessMode.transport,
    this.host = '127.0.0.1',
    this.port = 47811,
    this.sampleCount = 10000,
    this.targetRateHz = 120,
    this.loadProfile = LoadProfiles.idle,
    this.jsonPath,
    this.comparePath,
    this.thresholdPercent = 20.0,
    this.calibrationSamples = 1000,
    this.timeout = const Duration(seconds: 15),
    this.showHelp = false,
  });

  final HarnessMode mode;
  final String host;
  final int port;
  final int sampleCount;
  final int targetRateHz;
  final String loadProfile;
  final String? jsonPath;
  final String? comparePath;
  final double thresholdPercent;
  final int calibrationSamples;
  final Duration timeout;
  final bool showHelp;

  static ArgParser createArgParser() {
    return ArgParser()
      ..addOption(
        'mode',
        abbr: 'm',
        defaultsTo: 'transport',
        allowed: <String>['transport', 'e2e', 'reconnect'],
        help: 'Measurement mode to run (transport, e2e, reconnect).',
      )
      ..addOption(
        'host',
        abbr: 'H',
        defaultsTo: '127.0.0.1',
        help: 'Target host running RemoteLink desktop service.',
      )
      ..addOption(
        'port',
        abbr: 'p',
        defaultsTo: '47811',
        help: 'Port of the RemoteLink desktop service.',
      )
      ..addOption(
        'samples',
        abbr: 's',
        defaultsTo: '10000',
        help: 'Number of measurement samples to collect.',
      )
      ..addOption(
        'rate',
        abbr: 'r',
        defaultsTo: '120',
        help: 'Target sampling rate in Hz (e.g. 60, 120, 240).',
      )
      ..addOption(
        'load',
        abbr: 'l',
        defaultsTo: 'idle',
        help: 'Concurrent load profile (idle, clipboard).',
      )
      ..addOption(
        'json',
        help: 'File path to write machine-readable JSON output.',
      )
      ..addOption(
        'compare',
        help: 'Path to baseline JSON file for regression comparison.',
      )
      ..addOption(
        'threshold',
        defaultsTo: '20.0',
        help: 'Regression threshold percentage for --compare (default 20.0%).',
      )
      ..addOption(
        'calibration-samples',
        defaultsTo: '1000',
        help:
            'Sample count for local OS move-and-read calibration in e2e mode.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '15',
        help: 'Connection timeout in seconds.',
      )
      ..addFlag(
        'help',
        abbr: 'h',
        negatable: false,
        help: 'Show command help and usage.',
      );
  }

  /// Parses CLI arguments into a validated [HarnessConfig].
  factory HarnessConfig.parse(List<String> args) {
    final parser = createArgParser();
    final results = parser.parse(args);

    if (results.flag('help')) {
      return const HarnessConfig(showHelp: true);
    }

    final modeName = results.option('mode') ?? 'transport';
    final mode = HarnessMode.fromName(modeName);

    final host = results.option('host') ?? '127.0.0.1';
    final port = int.tryParse(results.option('port') ?? '47811');
    if (port == null || port <= 0 || port > 65535) {
      throw FormatException('Invalid port: ${results.option('port')}');
    }

    final samples = int.tryParse(results.option('samples') ?? '10000');
    if (samples == null || samples <= 0) {
      throw FormatException(
          'Invalid sample count: ${results.option('samples')}');
    }

    final rate = int.tryParse(results.option('rate') ?? '120');
    if (rate == null || rate <= 0) {
      throw FormatException('Invalid rate: ${results.option('rate')}');
    }

    final load = results.option('load') ?? LoadProfiles.idle;
    if (!LoadProfiles.available.contains(load.toLowerCase())) {
      throw FormatException(
        'Unknown load profile "$load". Available: ${LoadProfiles.available.join(', ')}',
      );
    }

    final threshold = double.tryParse(results.option('threshold') ?? '20.0');
    if (threshold == null || threshold < 0) {
      throw FormatException(
        'Invalid threshold percentage: ${results.option('threshold')}',
      );
    }

    final calSamples =
        int.tryParse(results.option('calibration-samples') ?? '1000');
    if (calSamples == null || calSamples <= 0) {
      throw FormatException(
        'Invalid calibration sample count: ${results.option('calibration-samples')}',
      );
    }

    final timeoutSec = int.tryParse(results.option('timeout') ?? '15');
    if (timeoutSec == null || timeoutSec <= 0) {
      throw FormatException('Invalid timeout: ${results.option('timeout')}');
    }

    return HarnessConfig(
      mode: mode,
      host: host,
      port: port,
      sampleCount: samples,
      targetRateHz: rate,
      loadProfile: load.toLowerCase(),
      jsonPath: results.option('json'),
      comparePath: results.option('compare'),
      thresholdPercent: threshold,
      calibrationSamples: calSamples,
      timeout: Duration(seconds: timeoutSec),
      showHelp: false,
    );
  }
}
