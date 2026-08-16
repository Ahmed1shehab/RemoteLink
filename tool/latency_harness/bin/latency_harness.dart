import 'dart:io';

import 'package:args/args.dart';
import 'package:latency_harness/latency_harness.dart';

Future<void> main(List<String> args) async {
  final ArgParser parser = HarnessConfig.createArgParser();
  final HarnessConfig config;

  try {
    config = HarnessConfig.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    stderr.writeln('Usage: dart run latency_harness [options]');
    stderr.writeln(parser.usage);
    exit(2);
  } on ArgumentError catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    stderr.writeln('Usage: dart run latency_harness [options]');
    stderr.writeln(parser.usage);
    exit(2);
  }

  if (config.showHelp) {
    stdout.writeln('RemoteLink Headless Latency Harness');
    stdout.writeln(
        'Measures cursor and transport latency, calibration overhead, and regression gating.\n');
    stdout.writeln('Usage: dart run latency_harness [options]\n');
    stdout.writeln(parser.usage);
    exit(0);
  }

  try {
    final runner = HarnessRunner(config: config);
    final exitCode = await runner.run(onStatus: stdout.writeln);
    exit(exitCode);
  } on SocketException catch (e) {
    stderr.writeln(
      'Connection failed: Could not reach desktop service at '
      '${config.host}:${config.port} (${e.message})',
    );
    stderr.writeln(
      'Ensure RemoteLink desktop is running and listening on that port.',
    );
    exit(1);
  } on StateError catch (e) {
    stderr.writeln('Execution error: ${e.message}');
    exit(1);
  } on Object catch (e, stackTrace) {
    stderr.writeln('Unexpected error: $e');
    stderr.writeln(stackTrace);
    exit(1);
  }
}
