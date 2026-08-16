/// Shared primitives used by every other RemoteLink package.
///
/// This package must never depend on Flutter, `dart:io`, or `dart:ffi` so that
/// it can be consumed from isolates, tests, and (eventually) web tooling.
library;

export 'src/clock.dart';
export 'src/device.dart';
export 'src/device_name.dart';
export 'src/errors.dart';
export 'src/logging.dart';
export 'src/result.dart';
