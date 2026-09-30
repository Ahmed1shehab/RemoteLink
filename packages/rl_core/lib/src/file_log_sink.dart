import 'dart:async';
import 'dart:convert';

import 'file_log_backend.dart';
import 'logging.dart';

/// A rotating, size-capped log sink that writes records to a file on disk.
///
/// Pure logic lives here: size checks, rotation boundaries, and file naming
/// are decoupled from the filesystem by [LogFileBackend]. In production, the
/// default backend uses `dart:io`; tests inject a [MemoryLogFileBackend].
///
/// Rotation keeps at most [maxFiles] files total (the active [path] plus up
/// to `maxFiles - 1` rotated files: `path.1`, `path.2`, etc.). When adding a
/// record would push the active file over [maxBytesPerFile], the current files
/// are shifted: `path.N-1` is pruned, `path.i` becomes `path.i+1`, and [path]
/// becomes `path.1`. A new empty [path] is opened for the incoming record.
///
/// To keep synchronous blocking I/O off the UI isolate, records are filtered
/// against [minLevel] (defaulting to [LogLevel.info]) and buffered in memory.
/// Buffered records are flushed synchronously:
/// - when the in-memory buffer exceeds [bufferCapacity] (default 16 KiB),
/// - periodically on [flushInterval] (default 2 seconds, injectable for tests),
/// - immediately on records at [LogLevel.warn] or higher, or crash records,
/// - explicitly on [flush] or [rotate], e.g. during uncaught crash capture.
final class FileLogSink implements LogSink {
  FileLogSink({
    required this.path,
    this.minLevel = LogLevel.info,
    this.maxBytesPerFile = defaultMaxBytesPerFile,
    this.maxFiles = defaultMaxFiles,
    this.bufferCapacity = defaultBufferCapacity,
    this.flushInterval = defaultFlushInterval,
    LogFileBackend? backend,
  })  : backend = backend ?? defaultLogFileBackend(),
        assert(maxBytesPerFile > 0, 'maxBytesPerFile must be positive'),
        assert(maxFiles >= 1, 'maxFiles must be at least 1'),
        assert(bufferCapacity > 0, 'bufferCapacity must be positive') {
    _init();
    if (flushInterval != null && flushInterval! > Duration.zero) {
      _timer = Timer.periodic(flushInterval!, (_) => flush());
    }
  }

  /// Default file size limit before rotation: 1 MiB.
  static const int defaultMaxBytesPerFile = 1024 * 1024;

  /// Default total number of log files kept (active + backups): 3.
  static const int defaultMaxFiles = 3;

  /// Default in-memory buffer threshold before flushing: 16 KiB.
  static const int defaultBufferCapacity = 16 * 1024;

  /// Default interval for periodic background flushing: 2 seconds.
  static const Duration defaultFlushInterval = Duration(seconds: 2);

  /// Path to the primary (active) log file.
  final String path;

  /// Minimum severity of records that reach the buffer or disk.
  final LogLevel minLevel;

  /// Maximum byte size of an individual log file before it rotates.
  final int maxBytesPerFile;

  /// Maximum number of log files to retain, including the active file.
  final int maxFiles;

  /// In-memory buffer size in UTF-8 bytes before flushing to [backend].
  final int bufferCapacity;

  /// Background flush timer interval, or null to disable timer-based flushing.
  final Duration? flushInterval;

  /// Abstraction for filesystem operations.
  final LogFileBackend backend;

  Timer? _timer;
  final StringBuffer _buffer = StringBuffer();
  int _bufferedBytes = 0;
  int _onDiskBytes = 0;

  /// Current byte size of the active log file, including buffered in-memory bytes.
  int get currentBytes => _onDiskBytes + _bufferedBytes;

  /// Number of bytes currently waiting in the in-memory write buffer.
  int get bufferedBytes => _bufferedBytes;

  /// Number of bytes committed to the active file on disk.
  int get onDiskBytes => _onDiskBytes;

  void _init() {
    try {
      _onDiskBytes = backend.fileExists(path) ? backend.fileSize(path) : 0;
    } catch (_) {
      _onDiskBytes = 0;
    }
  }

  @override
  void write(LogRecord record) {
    if (record.level.severity < minLevel.severity) {
      return;
    }

    try {
      final formatted = '$record\n';
      final byteCount = utf8.encode(formatted).length;

      // If the file already has data (on disk or buffered) and adding this record
      // would push it over maxBytesPerFile, rotate before writing.
      if (currentBytes > 0 && (currentBytes + byteCount > maxBytesPerFile)) {
        rotate();
      }

      _buffer.write(formatted);
      _bufferedBytes += byteCount;

      final isImmediate = record.level.severity >= LogLevel.warn.severity ||
          record.scope == 'crash' ||
          record.error != null;

      if (_bufferedBytes >= bufferCapacity || isImmediate) {
        flush();
      }
    } catch (_) {
      // Sinks must fail closed and never crash the application.
    }
  }

  /// Flushes all buffered log lines to the persistent backend.
  void flush() {
    if (_buffer.isEmpty) return;
    try {
      final text = _buffer.toString();
      backend.appendText(path, text);
      _onDiskBytes += _bufferedBytes;
      _buffer.clear();
      _bufferedBytes = 0;
    } catch (_) {
      // Fail closed: clear buffer to avoid unbounded memory growth if disk unwritable.
      _buffer.clear();
      _bufferedBytes = 0;
    }
  }

  /// Forces a rotation of the current log files.
  void rotate() {
    try {
      flush();

      if (maxFiles <= 1) {
        backend.deleteFile(path);
        _onDiskBytes = 0;
        return;
      }

      // Evict the oldest archive if it exists.
      final oldest = '$path.${maxFiles - 1}';
      if (backend.fileExists(oldest)) {
        backend.deleteFile(oldest);
      }

      // Shift existing archives down: path.(i) -> path.(i+1)
      for (var i = maxFiles - 2; i >= 1; i--) {
        final source = '$path.$i';
        final target = '$path.${i + 1}';
        if (backend.fileExists(source)) {
          backend.renameFile(source, target);
        }
      }

      // Rotate active file to path.1
      if (backend.fileExists(path)) {
        backend.renameFile(path, '$path.1');
      }

      _onDiskBytes = 0;
    } catch (_) {
      // Rotation failures fail safe.
    }
  }

  /// Reads all retained logs in chronological order (oldest archives first,
  /// ending with the active log file).
  String readAllLogs() {
    flush();
    final buffer = StringBuffer();
    // Oldest to newest
    for (var i = maxFiles - 1; i >= 1; i--) {
      final archivePath = '$path.$i';
      if (backend.fileExists(archivePath)) {
        final content = backend.readFile(archivePath);
        if (content.isNotEmpty) {
          buffer.write(content);
        }
      }
    }
    if (backend.fileExists(path)) {
      final activeContent = backend.readFile(path);
      if (activeContent.isNotEmpty) {
        buffer.write(activeContent);
      }
    }
    return buffer.toString();
  }

  /// Cancels the background flush timer and flushes any buffered logs.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    flush();
  }
}
