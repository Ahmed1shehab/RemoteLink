/// Shared primitives used by every other RemoteLink package.
///
/// This package must never depend on Flutter, `dart:io`, or `dart:ffi` so that
/// it can be consumed from isolates, tests, and (eventually) web tooling.
library;

export 'src/accessibility.dart';
export 'src/clipboard_history.dart';
export 'src/clock.dart';
export 'src/crash_handler.dart';
export 'src/device.dart';
export 'src/device_name.dart';
export 'src/errors.dart';
export 'src/file_log_backend.dart';
export 'src/file_log_sink.dart';
export 'src/log_export.dart';
export 'src/logging.dart';
export 'src/mac_address.dart';
export 'src/mime_type.dart';
export 'src/redaction.dart';
export 'src/result.dart';
export 'src/wake_on_lan.dart';
