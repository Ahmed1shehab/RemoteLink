import 'dart:convert';

import 'file_log_backend_stub.dart'
    if (dart.library.io) 'file_log_backend_io.dart';

/// File operations required by `FileLogSink`.
///
/// Abstracted behind this interface so rotation boundaries, size limits, and
/// archival ordering can be verified deterministically in memory without
/// touching the host filesystem, while production runs on `dart:io`.
abstract interface class LogFileBackend {
  /// Whether a file exists at [path].
  bool fileExists(String path);

  /// Current byte size of the file at [path], or 0 if it does not exist.
  int fileSize(String path);

  /// Appends [text] to the file at [path], creating parent directories and
  /// the file if they do not exist.
  void appendText(String path, String text);

  /// Renames [fromPath] to [toPath], overwriting any existing file at [toPath].
  void renameFile(String fromPath, String toPath);

  /// Deletes the file at [path] if it exists.
  void deleteFile(String path);

  /// Reads the entire contents of [path] as a UTF-8 string, or returns an empty
  /// string if it does not exist.
  String readFile(String path);
}

/// An in-memory [LogFileBackend] for testing rotation and size-capping logic.
final class MemoryLogFileBackend implements LogFileBackend {
  final Map<String, List<int>> _storage = <String, List<int>>{};

  /// Read-only snapshot of all currently stored files and their byte contents.
  Map<String, List<int>> get storage =>
      Map<String, List<int>>.unmodifiable(_storage);

  @override
  bool fileExists(String path) => _storage.containsKey(path);

  @override
  int fileSize(String path) => _storage[path]?.length ?? 0;

  @override
  void appendText(String path, String text) {
    final encoded = utf8.encode(text);
    final existing = _storage[path] ?? <int>[];
    _storage[path] = <int>[...existing, ...encoded];
  }

  @override
  void renameFile(String fromPath, String toPath) {
    final contents = _storage.remove(fromPath);
    if (contents != null) {
      _storage[toPath] = contents;
    }
  }

  @override
  void deleteFile(String path) {
    _storage.remove(path);
  }

  @override
  String readFile(String path) {
    final bytes = _storage[path];
    return bytes == null ? '' : utf8.decode(bytes, allowMalformed: true);
  }
}

/// Returns the default platform backend: [IoLogFileBackend] when `dart:io`
/// is available, or [MemoryLogFileBackend] otherwise.
LogFileBackend defaultLogFileBackend() => createPlatformLogFileBackend();
