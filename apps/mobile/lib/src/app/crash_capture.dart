import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:rl_core/rl_core.dart';

/// Installs global error listeners that forward uncaught Flutter, platform
/// dispatcher, and isolate errors to [handler].
///
/// Returns a cleanup callback that restores previous handlers and removes
/// the isolate error listener, suitable for teardown in unit and widget tests.
void Function() installCrashCapture(CrashHandler handler) {
  final previousFlutterOnError = FlutterError.onError;
  final previousPlatformOnError = PlatformDispatcher.instance.onError;

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    handler.recordCrash(details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    handler.recordCrash(error, stack);
    return true;
  };

  final errorPort = RawReceivePort((dynamic pair) {
    handleIsolateError(handler, pair);
  });
  Isolate.current.addErrorListener(errorPort.sendPort);

  return () {
    FlutterError.onError = previousFlutterOnError;
    PlatformDispatcher.instance.onError = previousPlatformOnError;
    Isolate.current.removeErrorListener(errorPort.sendPort);
    errorPort.close();
  };
}

/// Dispatches an uncaught isolate error message pair `[error, stackTraceString]`
/// to [handler].
@visibleForTesting
void handleIsolateError(CrashHandler handler, dynamic pair) {
  final isolateError = pair as List<dynamic>;
  final error = isolateError[0];
  final stack = isolateError[1] != null
      ? StackTrace.fromString(isolateError[1] as String)
      : null;
  handler.recordCrash((error ?? 'Isolate error') as Object, stack);
}
