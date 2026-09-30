import 'package:rl_core/rl_core.dart';
import 'package:test/test.dart';

void main() {
  group('buildLogExport', () {
    late MemoryLogFileBackend memoryBackend;
    late LogRedactor redactor;

    setUp(() {
      memoryBackend = MemoryLogFileBackend();
      redactor = LogRedactor(
        knownPeerNames: <String>{"Ahmed's Laptop", 'Pixel 8'},
        homeDirectories: <String>['/Users/ahmed'],
      );
    });

    test(
        'redacts sensitive information in persistent FileLogSink file contents',
        () {
      final fileSink = FileLogSink(
        path: '/logs/app.log',
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(fileSink.dispose);

      fileSink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'transfer',
          message:
              'Sent secret.pdf to 192.168.1.55 (Ahmed\'s Laptop) from /Users/ahmed/secret.pdf with key=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          time: DateTime.utc(2026, 9, 30, 12, 0, 0),
        ),
      );

      final exported = buildLogExport(
        fileSink: fileSink,
        redactor: redactor,
      );

      expect(exported, isNot(contains('192.168.1.55')));
      expect(exported, contains(LogRedactor.redactedIp));

      expect(exported, isNot(contains("Ahmed's Laptop")));
      expect(exported, contains(LogRedactor.redactedPeerName));

      expect(exported, isNot(contains('/Users/ahmed/secret.pdf')));
      expect(exported, contains(LogRedactor.redactedPath));

      expect(
        exported,
        isNot(contains(
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef')),
      );
      expect(exported, contains(LogRedactor.redactedKey));
    });

    test('redacts sensitive information in crash report', () {
      final memorySink = MemoryLogSink();
      memorySink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'network',
          message: 'Connecting to 10.0.0.42 on Pixel 8',
          time: DateTime.utc(2026, 9, 30, 11, 59, 0),
        ),
      );

      final crashHandler = CrashHandler(
        memorySink: memorySink,
      );

      final report = crashHandler.recordCrash(
        Exception(
            'Panic opening /Users/ahmed/keys/auth.token for device T9PTJKQZWKGRRCYPBKH2ZNSZDV'),
        StackTrace.fromString('#0 main (/Users/ahmed/src/app.dart:10:5)'),
      );

      final exported = buildLogExport(
        lastCrashReport: report,
        redactor: redactor,
      );

      expect(exported, contains('=== Remote Link Crash Report ==='));

      // Error message scrubbed
      expect(exported, isNot(contains('/Users/ahmed/keys/auth.token')));
      expect(exported, contains(LogRedactor.redactedPath));
      expect(exported, isNot(contains('T9PTJKQZWKGRRCYPBKH2ZNSZDV')));
      expect(exported, contains(LogRedactor.redactedDeviceId));

      // Recent logs attached to crash scrubbed
      expect(exported, isNot(contains('10.0.0.42')));
      expect(exported, contains(LogRedactor.redactedIp));
      expect(exported, isNot(contains('Pixel 8')));
      expect(exported, contains(LogRedactor.redactedPeerName));
    });

    test('exports rotated files in chronological order (oldest first)', () {
      final fileSink = FileLogSink(
        path: '/logs/app.log',
        maxBytesPerFile: 80,
        maxFiles: 3,
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(fileSink.dispose);

      fileSink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'test',
          message: 'First entry',
          time: DateTime.utc(2026, 9, 30, 10, 0, 0),
        ),
      );
      fileSink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'test',
          message: 'Second entry',
          time: DateTime.utc(2026, 9, 30, 10, 1, 0),
        ),
      );
      fileSink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'test',
          message: 'Third entry',
          time: DateTime.utc(2026, 9, 30, 10, 2, 0),
        ),
      );

      final exported = buildLogExport(
        fileSink: fileSink,
        redactor: redactor,
      );

      final firstIdx = exported.indexOf('First entry');
      final secondIdx = exported.indexOf('Second entry');
      final thirdIdx = exported.indexOf('Third entry');

      expect(firstIdx, isNonNegative);
      expect(secondIdx, isNonNegative);
      expect(thirdIdx, isNonNegative);
      expect(firstIdx, lessThan(secondIdx));
      expect(secondIdx, lessThan(thirdIdx));
    });

    test('falls back to memory records when no file sink is present', () {
      final memoryRecords = <LogRecord>[
        LogRecord(
          level: LogLevel.debug,
          scope: 'mem',
          message: 'Debug message',
          time: DateTime.utc(2026, 9, 30, 12, 0, 0),
        ),
        LogRecord(
          level: LogLevel.info,
          scope: 'mem',
          message: 'Info message for Ahmed\'s Laptop',
          time: DateTime.utc(2026, 9, 30, 12, 1, 0),
        ),
      ];

      final exported = buildLogExport(
        memoryRecords: memoryRecords,
        redactor: redactor,
        filterLevel: LogLevel.info,
      );

      expect(exported, isNot(contains('Debug message')));
      expect(exported, contains('Info message for'));
      expect(exported, isNot(contains("Ahmed's Laptop")));
      expect(exported, contains(LogRedactor.redactedPeerName));
    });

    test('combines crash report and persistent file logs with optional header',
        () {
      final fileSink = FileLogSink(
        path: '/logs/app.log',
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(fileSink.dispose);

      fileSink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'disk',
          message: 'Persistent disk entry',
          time: DateTime.utc(2026, 9, 30, 12, 0, 0),
        ),
      );

      final crashHandler = CrashHandler();
      final report = crashHandler.recordCrash(Exception('Crash event'));

      final exported = buildLogExport(
        header: '=== Diagnostics Header ===',
        fileSink: fileSink,
        lastCrashReport: report,
        redactor: redactor,
      );

      expect(exported, startsWith('=== Diagnostics Header ==='));
      expect(exported, contains('=== Remote Link Crash Report ==='));
      expect(exported, contains('Crash event'));
      expect(exported, contains('Persistent disk entry'));
    });
  });
}
