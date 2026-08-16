import 'package:latency_harness/latency_harness.dart';
import 'package:test/test.dart';

void main() {
  group('HarnessConfig', () {
    test('parses defaults correctly with empty args', () {
      final config = HarnessConfig.parse(<String>[]);

      expect(config.mode, HarnessMode.transport);
      expect(config.sampleCount, 10000);
      expect(config.targetRateHz, 120);
      expect(config.loadProfile, 'idle');
      expect(config.host, '127.0.0.1');
      expect(config.port, 47811);
      expect(config.thresholdPercent, 20.0);
      expect(config.calibrationSamples, 1000);
      expect(config.jsonPath, isNull);
      expect(config.comparePath, isNull);
      expect(config.showHelp, isFalse);
    });

    test('parses custom long options', () {
      final config = HarnessConfig.parse(<String>[
        '--mode',
        'e2e',
        '--samples',
        '5000',
        '--rate',
        '240',
        '--load',
        'clipboard',
        '--host',
        '192.168.1.100',
        '--port',
        '50000',
        '--threshold',
        '15.5',
        '--calibration-samples',
        '500',
        '--json',
        'output.json',
        '--compare',
        'baseline.json',
      ]);

      expect(config.mode, HarnessMode.e2e);
      expect(config.sampleCount, 5000);
      expect(config.targetRateHz, 240);
      expect(config.loadProfile, 'clipboard');
      expect(config.host, '192.168.1.100');
      expect(config.port, 50000);
      expect(config.thresholdPercent, 15.5);
      expect(config.calibrationSamples, 500);
      expect(config.jsonPath, 'output.json');
      expect(config.comparePath, 'baseline.json');
      expect(config.showHelp, isFalse);
    });

    test('parses custom short options', () {
      final config = HarnessConfig.parse(<String>[
        '-m',
        'reconnect',
        '-s',
        '20',
        '-r',
        '60',
        '-l',
        'idle',
        '-H',
        '10.0.0.1',
        '-p',
        '48000',
      ]);

      expect(config.mode, HarnessMode.reconnect);
      expect(config.sampleCount, 20);
      expect(config.targetRateHz, 60);
      expect(config.host, '10.0.0.1');
      expect(config.port, 48000);
    });

    test('parses --help flag', () {
      final config = HarnessConfig.parse(<String>['--help']);
      expect(config.showHelp, isTrue);

      final shortHelp = HarnessConfig.parse(<String>['-h']);
      expect(shortHelp.showHelp, isTrue);
    });

    test('throws FormatException on invalid port', () {
      expect(
        () => HarnessConfig.parse(<String>['--port', 'invalid']),
        throwsFormatException,
      );
      expect(
        () => HarnessConfig.parse(<String>['--port', '0']),
        throwsFormatException,
      );
      expect(
        () => HarnessConfig.parse(<String>['--port', '70000']),
        throwsFormatException,
      );
    });

    test('throws FormatException on invalid sample count', () {
      expect(
        () => HarnessConfig.parse(<String>['--samples', '-5']),
        throwsFormatException,
      );
      expect(
        () => HarnessConfig.parse(<String>['--samples', '0']),
        throwsFormatException,
      );
    });

    test('throws FormatException on invalid rate', () {
      expect(
        () => HarnessConfig.parse(<String>['--rate', '0']),
        throwsFormatException,
      );
    });

    test('throws FormatException on unknown load profile', () {
      expect(
        () => HarnessConfig.parse(<String>['--load', 'video_stream']),
        throwsFormatException,
      );
    });

    test('throws FormatException on invalid threshold', () {
      expect(
        () => HarnessConfig.parse(<String>['--threshold', '-1.0']),
        throwsFormatException,
      );
    });
  });
}
