import 'file_log_backend.dart';

/// Stub implementation when `dart:io` is unavailable.
LogFileBackend createPlatformLogFileBackend() => MemoryLogFileBackend();
