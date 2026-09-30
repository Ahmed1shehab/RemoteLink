import 'dart:io';

import 'package:rl_core/rl_core.dart';
import 'package:test/test.dart';

void main() {
  group('FileLogSink rotation boundaries and buffering', () {
    late MemoryLogFileBackend memoryBackend;

    setUp(() {
      memoryBackend = MemoryLogFileBackend();
    });

    LogRecord createRecord(
      String message, {
      LogLevel level = LogLevel.info,
      String scope = 'test.scope',
    }) =>
        LogRecord(
          level: level,
          scope: scope,
          message: message,
          time: DateTime.utc(2026, 9, 30, 12, 0, 0),
        );

    test('buffers info records in memory and writes to active file on flush',
        () {
      final sink = FileLogSink(
        path: '/logs/app.log',
        maxBytesPerFile: 1000,
        maxFiles: 3,
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      final record = createRecord('First entry');
      sink.write(record);

      // Buffered in memory, not yet on disk backend
      expect(memoryBackend.fileExists('/logs/app.log'), isFalse);
      expect(sink.bufferedBytes, greaterThan(0));
      expect(sink.currentBytes, greaterThan(0));

      sink.flush();
      expect(memoryBackend.fileExists('/logs/app.log'), isTrue);
      expect(memoryBackend.readFile('/logs/app.log'), contains('First entry'));
      expect(memoryBackend.fileExists('/logs/app.log.1'), isFalse);
      expect(sink.bufferedBytes, equals(0));
    });

    test('rotates file when adding next record exceeds maxBytesPerFile', () {
      final sink = FileLogSink(
        path: '/logs/app.log',
        maxBytesPerFile: 100, // Small limit
        maxFiles: 3,
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      // Write first record: ~65 bytes
      final r1 = createRecord('Record 1');
      sink.write(r1);

      expect(sink.currentBytes, greaterThan(0));

      // Write second record: ~65 bytes. sizeAfterR1 + 65 > 100 -> triggers rotation!
      final r2 = createRecord('Record 2');
      sink.write(r2);

      // Rotation flushes r1 to active file and shifts it to app.log.1.
      // r2 is buffered for the new active file.
      expect(memoryBackend.fileExists('/logs/app.log.1'), isTrue);
      expect(memoryBackend.readFile('/logs/app.log.1'), contains('Record 1'));

      sink.flush();
      expect(memoryBackend.fileExists('/logs/app.log'), isTrue);
      expect(memoryBackend.readFile('/logs/app.log'), contains('Record 2'));
      expect(
          memoryBackend.readFile('/logs/app.log'), isNot(contains('Record 1')));
    });

    test('caps total number of files to maxFiles and discards oldest', () {
      final sink = FileLogSink(
        path: '/logs/app.log',
        maxBytesPerFile: 80,
        maxFiles: 3, // app.log, app.log.1, app.log.2
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      sink.write(createRecord('Batch 1')); // lands in buffer
      sink.write(createRecord(
          'Batch 2')); // rotates: app.log.1=Batch 1, app.log buffer=Batch 2
      sink.write(createRecord(
          'Batch 3')); // rotates: app.log.2=Batch 1, app.log.1=Batch 2, app.log buffer=Batch 3

      expect(memoryBackend.fileExists('/logs/app.log.1'), isTrue);
      expect(memoryBackend.fileExists('/logs/app.log.2'), isTrue);
      expect(memoryBackend.fileExists('/logs/app.log.3'), isFalse);
      expect(memoryBackend.readFile('/logs/app.log.2'), contains('Batch 1'));
      expect(memoryBackend.readFile('/logs/app.log.1'), contains('Batch 2'));

      // 4th batch: oldest (app.log.2 with Batch 1) is purged!
      sink.write(createRecord('Batch 4'));

      expect(memoryBackend.fileExists('/logs/app.log.1'), isTrue);
      expect(memoryBackend.fileExists('/logs/app.log.2'), isTrue);
      expect(memoryBackend.fileExists('/logs/app.log.3'), isFalse);
      expect(memoryBackend.readFile('/logs/app.log.2'), contains('Batch 2'));
      expect(memoryBackend.readFile('/logs/app.log.1'), contains('Batch 3'));

      sink.flush();
      expect(memoryBackend.readFile('/logs/app.log'), contains('Batch 4'));
    });

    test(
        'readAllLogs flushes buffer and returns records in chronological order from oldest to newest',
        () {
      final sink = FileLogSink(
        path: '/logs/app.log',
        maxBytesPerFile: 80,
        maxFiles: 3,
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      sink.write(createRecord('Alpha'));
      sink.write(createRecord('Beta'));
      sink.write(createRecord('Gamma'));

      final fullLog = sink.readAllLogs();
      final alphaIndex = fullLog.indexOf('Alpha');
      final betaIndex = fullLog.indexOf('Beta');
      final gammaIndex = fullLog.indexOf('Gamma');

      expect(alphaIndex, isNonNegative);
      expect(betaIndex, isNonNegative);
      expect(gammaIndex, isNonNegative);
      expect(alphaIndex, lessThan(betaIndex));
      expect(betaIndex, lessThan(gammaIndex));
    });

    test('handles single file (maxFiles = 1) without backup files', () {
      final sink = FileLogSink(
        path: '/logs/app.log',
        maxBytesPerFile: 80,
        maxFiles: 1,
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      sink.write(createRecord('First'));
      sink.write(createRecord('Second'));

      sink.flush();
      expect(memoryBackend.fileExists('/logs/app.log'), isTrue);
      expect(memoryBackend.fileExists('/logs/app.log.1'), isFalse);
      expect(memoryBackend.readFile('/logs/app.log'), contains('Second'));
    });

    test('filters out debug and trace logs by default minLevel', () {
      final sink = FileLogSink(
        path: '/logs/app.log',
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      sink.write(createRecord('Trace msg', level: LogLevel.trace));
      sink.write(createRecord('Debug msg', level: LogLevel.debug));

      expect(sink.bufferedBytes, equals(0));
      expect(sink.currentBytes, equals(0));

      sink.flush();
      expect(memoryBackend.fileExists('/logs/app.log'), isFalse);
    });

    test('allows debug logs when minLevel is configured to debug', () {
      final sink = FileLogSink(
        path: '/logs/app.log',
        minLevel: LogLevel.debug,
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      sink.write(createRecord('Debug msg', level: LogLevel.debug));

      expect(sink.bufferedBytes, greaterThan(0));
      sink.flush();
      expect(memoryBackend.readFile('/logs/app.log'), contains('Debug msg'));
    });

    test('flushes immediately on warn, error, and crash records', () {
      final sink = FileLogSink(
        path: '/logs/app.log',
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      // Info is buffered
      sink.write(createRecord('Info msg', level: LogLevel.info));
      expect(memoryBackend.fileExists('/logs/app.log'), isFalse);

      // Warn triggers immediate flush of buffer and self
      sink.write(createRecord('Warn msg', level: LogLevel.warn));
      expect(memoryBackend.fileExists('/logs/app.log'), isTrue);
      expect(memoryBackend.readFile('/logs/app.log'), contains('Info msg'));
      expect(memoryBackend.readFile('/logs/app.log'), contains('Warn msg'));
      expect(sink.bufferedBytes, equals(0));

      // Error triggers immediate flush
      sink.write(createRecord('Error msg', level: LogLevel.error));
      expect(memoryBackend.readFile('/logs/app.log'), contains('Error msg'));
      expect(sink.bufferedBytes, equals(0));

      // Crash scope triggers immediate flush
      sink.write(createRecord('Crash msg', scope: 'crash'));
      expect(memoryBackend.readFile('/logs/app.log'), contains('Crash msg'));
      expect(sink.bufferedBytes, equals(0));
    });

    test('flushes automatically when bufferCapacity is exceeded', () {
      final sink = FileLogSink(
        path: '/logs/app.log',
        bufferCapacity: 100,
        maxBytesPerFile: 5000,
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      sink.write(createRecord('Msg 1')); // ~60 bytes < 100
      expect(memoryBackend.fileExists('/logs/app.log'), isFalse);

      sink.write(createRecord('Msg 2')); // ~120 bytes >= 100 -> flushed!
      expect(memoryBackend.fileExists('/logs/app.log'), isTrue);
      expect(memoryBackend.readFile('/logs/app.log'), contains('Msg 1'));
      expect(memoryBackend.readFile('/logs/app.log'), contains('Msg 2'));
      expect(sink.bufferedBytes, equals(0));
    });

    test('flushes on periodic timer', () async {
      final sink = FileLogSink(
        path: '/logs/app.log',
        flushInterval: const Duration(milliseconds: 50),
        backend: memoryBackend,
      );
      addTearDown(sink.dispose);

      sink.write(createRecord('Timer msg'));
      expect(memoryBackend.fileExists('/logs/app.log'), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(memoryBackend.fileExists('/logs/app.log'), isTrue);
      expect(memoryBackend.readFile('/logs/app.log'), contains('Timer msg'));
      expect(sink.bufferedBytes, equals(0));
    });

    test('correctly calculates UTF-8 byte sizes for non-ASCII rotation', () {
      // In UTF-16 code units: "こんにちは世界 🚀" is 10 units.
      // In UTF-8 bytes: 7 Japanese characters * 3 bytes (21) + 1 space + 4 emoji = 26 bytes.
      // A formatted log line: timestamp (24) + " [INFO ] " (9) + "test.scope: " (12) + message (26) + "\n" (1)
      // = 72 UTF-8 bytes vs 56 UTF-16 code units.
      const nonAsciiMsg = 'こんにちは世界 🚀';

      final sink = FileLogSink(
        path: '/logs/app.log',
        maxBytesPerFile:
            120, // 72 + 72 = 144 > 120 (rotates in UTF-8, would NOT rotate in UTF-16: 56 + 56 = 112 < 120)
        maxFiles: 2,
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      final r1 = createRecord(nonAsciiMsg);
      sink.write(r1);

      // Write second non-ASCII record: exceeds 120 UTF-8 bytes!
      final r2 = createRecord(nonAsciiMsg);
      sink.write(r2);

      // Must have rotated to app.log.1 because UTF-8 bytes were measured!
      expect(memoryBackend.fileExists('/logs/app.log.1'), isTrue);
      expect(memoryBackend.readFile('/logs/app.log.1'), contains(nonAsciiMsg));

      final all = sink.readAllLogs();
      expect(all, contains(nonAsciiMsg));
    });

    test('works with real filesystem via IoLogFileBackend', () {
      final tempDir = Directory.systemTemp.createTempSync('rl_log_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final logPath = '${tempDir.path}/test.log';
      final sink = FileLogSink(
        path: logPath,
        maxBytesPerFile: 90,
        maxFiles: 2,
        flushInterval: null,
      );
      addTearDown(sink.dispose);

      sink.write(createRecord('Real file 1'));
      sink.write(createRecord('Real file 2'));

      final content = sink.readAllLogs();
      expect(content, contains('Real file 1'));
      expect(content, contains('Real file 2'));
    });
  });
}
