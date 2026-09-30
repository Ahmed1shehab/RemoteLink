import 'file_log_sink.dart';
import 'logging.dart';
import 'redaction.dart';

/// A structured report capturing an unhandled exception alongside recent logs.
final class CrashReport {
  CrashReport({
    required this.error,
    this.stackTrace,
    required this.timestamp,
    this.recentLogs = const <LogRecord>[],
  });

  final Object error;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  final List<LogRecord> recentLogs;

  /// Formats the report as a string, optionally scrubbing it with [redactor].
  String format({LogRedactor? redactor}) {
    final buffer = StringBuffer()
      ..writeln('=== Remote Link Crash Report ===')
      ..writeln('Time: ${timestamp.toUtc().toIso8601String()}')
      ..writeln('Error: $error');

    if (stackTrace != null) {
      buffer.writeln('\n--- Stack Trace ---');
      buffer.writeln(stackTrace);
    }

    if (recentLogs.isNotEmpty) {
      buffer.writeln('\n--- Recent Logs (${recentLogs.length} records) ---');
      for (final record in recentLogs) {
        buffer.writeln(record.toString());
      }
    }

    final text = buffer.toString();
    return redactor != null ? redactor.redact(text) : text;
  }

  @override
  String toString() => format();
}

/// Records uncaught crashes alongside the most recent log history.
///
/// Installed at application entrypoints to catch Flutter errors, platform
/// dispatcher errors, isolate errors, and zone errors. The last [maxRecentLogs]
/// records are captured from [memorySink] so bug reports have immediate
/// diagnostic context without having written to disk beforehand.
final class CrashHandler {
  CrashHandler({
    this.memorySink,
    this.sink,
    this.redactor,
    this.maxRecentLogs = defaultMaxRecentLogs,
    this.onReport,
  });

  /// Default number of recent log records attached to a crash report.
  static const int defaultMaxRecentLogs = 50;

  /// Process-global crash handler instance when configured.
  static CrashHandler? instance;

  final MemoryLogSink? memorySink;
  final LogSink? sink;
  final LogRedactor? redactor;
  final int maxRecentLogs;
  final void Function(CrashReport report)? onReport;

  CrashReport? _lastReport;

  /// The most recent crash report captured by this handler, if any.
  CrashReport? get lastReport => _lastReport;

  /// Records [error] and optional [stackTrace], attaching recent log records.
  CrashReport recordCrash(Object error, [StackTrace? stackTrace]) {
    final records = memorySink?.records ?? const <LogRecord>[];
    final recent = records.length > maxRecentLogs
        ? records.sublist(records.length - maxRecentLogs)
        : List<LogRecord>.from(records);

    final report = CrashReport(
      error: error,
      stackTrace: stackTrace,
      timestamp: DateTime.now(),
      recentLogs: recent,
    );
    _lastReport = report;

    final logRecord = LogRecord(
      level: LogLevel.error,
      scope: 'crash',
      message: 'uncaught exception: $error',
      time: report.timestamp,
      error: error,
      stackTrace: stackTrace,
      fields: <String, Object?>{
        'recentLogCount': recent.length,
      },
    );

    if (sink != null) {
      sink!.write(logRecord);
    } else {
      Log.scoped('crash').error(
        'uncaught exception: $error',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'recentLogCount': recent.length},
      );
    }

    _flushFileSink(sink);
    if (sink == null) {
      _flushFileSink(Log.sink);
    }

    onReport?.call(report);
    return report;
  }

  void _flushFileSink(LogSink? target) {
    if (target is FileLogSink) {
      target.flush();
    } else if (target is MultiLogSink) {
      for (final child in target.sinks) {
        if (child is FileLogSink) {
          child.flush();
        }
      }
    }
  }
}
