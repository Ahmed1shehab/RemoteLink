import 'package:rl_core/rl_core.dart';
import 'package:test/test.dart';

void main() {
  group('CrashHandler', () {
    late MemoryLogSink memorySink;
    late MemoryLogSink outputSink;

    setUp(() {
      memorySink = MemoryLogSink(capacity: 100);
      outputSink = MemoryLogSink();
    });

    test('captures error, stack trace, and attaches last N log records', () {
      for (var i = 1; i <= 10; i++) {
        memorySink.write(
          LogRecord(
            level: LogLevel.info,
            scope: 'app.service',
            message: 'Step $i',
            time: DateTime.utc(2026, 9, 30, 12, i),
          ),
        );
      }

      final handler = CrashHandler(
        memorySink: memorySink,
        sink: outputSink,
        maxRecentLogs: 5,
      );

      final stack = StackTrace.current;
      final report = handler.recordCrash(Exception('disk failure'), stack);

      expect(report.error.toString(), contains('disk failure'));
      expect(report.stackTrace, equals(stack));
      expect(report.recentLogs.length, equals(5));
      expect(report.recentLogs.first.message, equals('Step 6'));
      expect(report.recentLogs.last.message, equals('Step 10'));

      expect(handler.lastReport, equals(report));

      // Output sink should have recorded the crash record
      expect(outputSink.records.length, equals(1));
      final written = outputSink.records.single;
      expect(written.level, equals(LogLevel.error));
      expect(written.scope, equals('crash'));
      expect(written.message, contains('uncaught exception'));
      expect(written.fields['recentLogCount'], equals(5));
    });

    test('CrashReport format scrubs sensitive details when redactor provided',
        () {
      final memorySink = MemoryLogSink();
      memorySink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'transport',
          message: 'connected to 192.168.1.100 with peer Ahmed\'s MacBook Pro',
          time: DateTime.utc(2026, 9, 30),
        ),
      );

      final handler = CrashHandler(
        memorySink: memorySink,
        sink: outputSink,
      );

      final report = handler.recordCrash(
        Exception(
            'Fatal error accessing /Users/ahmed/secret.key for peer T9PTJKQZWKGRRCYPBKH2ZNSZDV'),
      );

      final redactor = LogRedactor(
        knownPeerNames: <String>{"Ahmed's MacBook Pro"},
        homeDirectories: <String>['/Users/ahmed'],
      );

      final formatted = report.format(redactor: redactor);

      expect(formatted, contains('=== Remote Link Crash Report ==='));
      expect(formatted, isNot(contains('/Users/ahmed')));
      expect(formatted, contains('[REDACTED_PATH]'));
      expect(formatted, isNot(contains('T9PTJKQZWKGRRCYPBKH2ZNSZDV')));
      expect(formatted, contains('[REDACTED_DEVICE_ID]'));
      expect(formatted, isNot(contains('192.168.1.100')));
      expect(formatted, contains('[REDACTED_IP]'));
      expect(formatted, isNot(contains("Ahmed's MacBook Pro")));
      expect(formatted, contains('[REDACTED_PEER_NAME]'));
    });

    test('invokes onReport callback when crash occurs', () {
      CrashReport? callbackReport;
      final handler = CrashHandler(
        onReport: (report) => callbackReport = report,
      );

      final report = handler.recordCrash(StateError('unexpected state'));

      expect(callbackReport, isNotNull);
      expect(callbackReport, equals(report));
    });

    test('flushes FileLogSink after writing crash record', () {
      final backend = MemoryLogFileBackend();
      final fileSink = FileLogSink(
        path: '/logs/crash_test.log',
        backend: backend,
        flushInterval: null,
      );
      addTearDown(fileSink.dispose);

      // Write an info record that gets buffered in memory
      fileSink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'service',
          message: 'Buffered info log before crash',
          time: DateTime.utc(2026, 9, 30),
        ),
      );
      expect(backend.fileExists('/logs/crash_test.log'), isFalse);
      expect(fileSink.bufferedBytes, greaterThan(0));

      final handler = CrashHandler(
        sink: fileSink,
      );

      handler.recordCrash(Exception('Crash event'));

      // The buffered info record AND the crash record must both be committed to disk
      expect(backend.fileExists('/logs/crash_test.log'), isTrue);
      final onDiskContent = backend.readFile('/logs/crash_test.log');
      expect(onDiskContent, contains('Buffered info log before crash'));
      expect(onDiskContent,
          contains('uncaught exception: Exception: Crash event'));
      expect(fileSink.bufferedBytes, equals(0));
    });
  });
}
