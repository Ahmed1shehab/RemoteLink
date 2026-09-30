import 'dart:io';

import 'file_log_backend.dart';

/// Real filesystem implementation for Dart VM and native Flutter runtimes.
LogFileBackend createPlatformLogFileBackend() => const IoLogFileBackend();

/// A [LogFileBackend] backed by synchronous `dart:io` file operations.
///
/// Synchronous writes are deliberate: log statements during shutdown or an
/// uncaught crash must reach the filesystem immediately without waiting for
/// the event loop to advance.
final class IoLogFileBackend implements LogFileBackend {
  const IoLogFileBackend();

  @override
  bool fileExists(String path) => File(path).existsSync();

  @override
  int fileSize(String path) {
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : 0;
  }

  @override
  void appendText(String path, String text) {
    final file = File(path);
    final parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    file.writeAsStringSync(text, mode: FileMode.append, flush: true);
  }

  @override
  void renameFile(String fromPath, String toPath) {
    final source = File(fromPath);
    if (!source.existsSync()) return;
    final target = File(toPath);
    if (target.existsSync()) {
      target.deleteSync();
    }
    source.renameSync(toPath);
  }

  @override
  void deleteFile(String path) {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  @override
  String readFile(String path) {
    final file = File(path);
    return file.existsSync() ? file.readAsStringSync() : '';
  }
}
