import 'dart:async';

/// Severity ordering used for level filtering.
enum LogLevel {
  trace(0),
  debug(10),
  info(20),
  warn(30),
  error(40),
  off(100);

  const LogLevel(this.severity);

  final int severity;
}

/// A single structured log record.
///
/// Records are structured rather than pre-formatted because the desktop app
/// ships them to a rolling file, the mobile app renders them in a diagnostics
/// screen, and tests assert on [fields] directly.
final class LogRecord {
  LogRecord({
    required this.level,
    required this.scope,
    required this.message,
    required this.time,
    this.fields = const <String, Object?>{},
    this.error,
    this.stackTrace,
  });

  final LogLevel level;

  /// Dotted subsystem path, e.g. `transport.session` or `native.input.win32`.
  final String scope;

  final String message;
  final DateTime time;
  final Map<String, Object?> fields;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write(time.toIso8601String())
      ..write(' [')
      ..write(level.name.toUpperCase().padRight(5))
      ..write('] ')
      ..write(scope)
      ..write(': ')
      ..write(message);
    if (fields.isNotEmpty) {
      buffer.write(' ');
      buffer.write(
        fields.entries.map((e) => '${e.key}=${e.value}').join(' '),
      );
    }
    if (error != null) buffer.write('\n  error: $error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    return buffer.toString();
  }
}

/// Receives records that pass the level filter.
abstract interface class LogSink {
  void write(LogRecord record);
}

/// Writes records with `print`. Debug builds only.
final class ConsoleLogSink implements LogSink {
  const ConsoleLogSink();

  @override
  void write(LogRecord record) {
    // ignore: avoid_print
    print(record);
  }
}

/// Keeps the last [capacity] records in a ring buffer.
///
/// Backs the in-app diagnostics view and lets a bug report attach recent
/// history without having written anything to disk.
final class MemoryLogSink implements LogSink {
  MemoryLogSink({this.capacity = 500});

  final int capacity;
  final List<LogRecord> _records = <LogRecord>[];
  final StreamController<LogRecord> _controller =
      StreamController<LogRecord>.broadcast();

  List<LogRecord> get records => List<LogRecord>.unmodifiable(_records);

  Stream<LogRecord> get stream => _controller.stream;

  @override
  void write(LogRecord record) {
    _records.add(record);
    if (_records.length > capacity) _records.removeAt(0);
    if (_controller.hasListener) _controller.add(record);
  }

  Future<void> dispose() => _controller.close();
}

/// Fans records out to several sinks.
final class MultiLogSink implements LogSink {
  const MultiLogSink(this.sinks);

  final List<LogSink> sinks;

  @override
  void write(LogRecord record) {
    for (final sink in sinks) {
      sink.write(record);
    }
  }
}

/// Scoped logger.
///
/// Obtain one with [Log.scoped]; the root sink and level are process-global so
/// that a single settings toggle changes verbosity everywhere. Message strings
/// are built lazily via closures so that disabled levels cost one comparison.
final class Log {
  const Log._(this.scope);

  final String scope;

  static LogLevel _level = LogLevel.info;
  static LogSink _sink = const ConsoleLogSink();

  /// Minimum severity that reaches [sink].
  static LogLevel get level => _level;

  static set level(LogLevel value) => _level = value;

  static LogSink get sink => _sink;

  static set sink(LogSink value) => _sink = value;

  /// Creates a logger for a subsystem, e.g. `Log.scoped('transport.session')`.
  static Log scoped(String scope) => Log._(scope);

  /// Child logger with a nested scope: `parent.child('codec')`.
  Log child(String suffix) => Log._('$scope.$suffix');

  bool enabledFor(LogLevel candidate) =>
      candidate.severity >= _level.severity && _level != LogLevel.off;

  void trace(String Function() message, {Map<String, Object?>? fields}) =>
      _log(LogLevel.trace, message, fields);

  void debug(String Function() message, {Map<String, Object?>? fields}) =>
      _log(LogLevel.debug, message, fields);

  void info(String message, {Map<String, Object?>? fields}) =>
      _log(LogLevel.info, () => message, fields);

  void warn(
    String message, {
    Map<String, Object?>? fields,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.warn, () => message, fields, error, stackTrace);

  void error(
    String message, {
    Map<String, Object?>? fields,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.error, () => message, fields, error, stackTrace);

  void _log(
    LogLevel candidate,
    String Function() message,
    Map<String, Object?>? fields, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!enabledFor(candidate)) return;
    _sink.write(
      LogRecord(
        level: candidate,
        scope: scope,
        message: message(),
        time: DateTime.now(),
        fields: fields ?? const <String, Object?>{},
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}
