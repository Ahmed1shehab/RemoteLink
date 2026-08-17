import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../screen_capture_backend.dart';
import 'coregraphics_ffi.dart';
import 'macos_screen_capturer.dart';

/// A long-lived isolate that grabs and encodes frames.
///
/// The work itself is unavoidably blocking — see [MacosScreenCapturer]. Moving
/// it here is what keeps the desktop's event loop free while it happens, which
/// matters far more than it sounds: the transport's heartbeat is a one-second
/// timer on that same loop, and a loop busy encoding JPEGs does not run timers.
/// The peer sees silence, decides the session is dead at two and a half
/// seconds, and reconnects — over and over, for as long as the stream runs.
///
/// One isolate for the life of the backend, not one per frame. `Isolate.spawn`
/// costs milliseconds and would have to re-resolve every CoreGraphics symbol
/// each time; at thirty frames a second that overhead is the same order as the
/// work being moved.
final class MacosCaptureWorker {
  MacosCaptureWorker();

  Isolate? _isolate;
  SendPort? _requests;
  ReceivePort? _responses;
  Future<void>? _starting;
  bool _disposed = false;

  int _nextRequestId = 0;
  final Map<int, Completer<CapturedFrame?>> _pending =
      <int, Completer<CapturedFrame?>>{};

  /// Whether the worker failed to start and the caller should run inline.
  ///
  /// Spawning can fail — a constrained sandbox, an exhausted process — and a
  /// backend that gave up at that point would report "screen capture is
  /// unavailable" for a reason that has nothing to do with screen capture.
  /// Falling back is slower and correct.
  bool get isUnavailable => _failedToStart;
  bool _failedToStart = false;

  Future<CapturedFrame?> capture({
    required int monitorId,
    required int maxWidth,
    required int maxHeight,
    required double quality,
  }) async {
    if (_disposed) return null;
    await _ensureStarted();
    final requests = _requests;
    if (requests == null) return null;

    final id = _nextRequestId++;
    final completer = Completer<CapturedFrame?>();
    _pending[id] = completer;
    requests.send(<Object>[id, monitorId, maxWidth, maxHeight, quality]);
    return completer.future;
  }

  Future<void> _ensureStarted() {
    if (_requests != null || _failedToStart) return Future<void>.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final responses = ReceivePort();
    _responses = responses;

    final ready = Completer<SendPort>();
    responses.listen((Object? message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      _completeResponse(message);
    });

    try {
      _isolate = await Isolate.spawn(
        _captureWorkerMain,
        responses.sendPort,
        debugName: 'remotelink-screen-capture',
        errorsAreFatal: false,
      );
      _requests = await ready.future.timeout(const Duration(seconds: 5));
    } on Object {
      // Every in-flight caller has to be told, or the frame loop waits on a
      // future that will never complete and the stream silently stops.
      _failedToStart = true;
      responses.close();
      _responses = null;
      _failCallers();
    }
  }

  void _completeResponse(Object? message) {
    if (message is! List || message.length != 6) return;
    final id = message[0] as int;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;

    final payload = message[3];
    if (payload is! TransferableTypedData) {
      completer.complete(null);
      return;
    }

    completer.complete(
      CapturedFrame(
        width: message[1] as int,
        height: message[2] as int,
        data: payload.materialize().asUint8List(),
        cursorX: message[4] as double?,
        cursorY: message[5] as double?,
      ),
    );
  }

  void _failCallers() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requests?.send(null);
    _requests = null;
    _responses?.close();
    _responses = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _failCallers();
  }
}

/// Entry point for the capture isolate.
///
/// Top-level because `Isolate.spawn` requires it. Resolves its own CoreGraphics
/// bindings: `DynamicLibrary` handles belong to the isolate that opened them
/// and cannot be sent across a port, which is also why the backend's injectable
/// bindings seam cannot reach in here — a test that supplies its own bindings
/// runs inline instead.
void _captureWorkerMain(SendPort responses) {
  final requests = ReceivePort();
  responses.send(requests.sendPort);

  final capturer = MacosScreenCapturer(CoreGraphicsBindings());

  requests.listen((Object? message) {
    // Null is the shutdown signal. Closing the port ends the isolate once the
    // listener returns.
    if (message == null) {
      requests.close();
      return;
    }
    if (message is! List || message.length != 5) return;

    final id = message[0] as int;
    CapturedFrame? frame;
    try {
      frame = capturer.capture(
        monitorId: message[1] as int,
        maxWidth: message[2] as int,
        maxHeight: message[3] as int,
        quality: message[4] as double,
      );
    } on Object {
      // A throw here would be an unhandled error on a worker isolate, which
      // tears the isolate down and takes the stream with it. One black frame
      // is the better outcome.
      frame = null;
    }

    responses.send(<Object?>[
      id,
      frame?.width ?? 0,
      frame?.height ?? 0,
      // Transferable rather than a plain list: the bytes move to the receiving
      // isolate instead of being copied, which for a frame every 33 ms is the
      // difference between a hand-off and a megabyte of garbage per second.
      if (frame != null)
        TransferableTypedData.fromList(<Uint8List>[frame.data])
      else
        null,
      frame?.cursorX,
      frame?.cursorY,
    ]);
  });
}
