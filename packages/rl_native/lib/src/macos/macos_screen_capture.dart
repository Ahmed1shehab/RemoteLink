import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../screen_capture_backend.dart';
import 'coregraphics_ffi.dart';
import 'macos_capture_worker.dart';
import 'macos_screen_capturer.dart';

/// macOS screen capture using CoreGraphics and ImageIO.
///
/// ## Implementation strategy
///
/// 1. **Capture (`CGDisplayCreateImage`)**:
///    Captures the specified display synchronously. Synchronous polling on a
///    timer is used rather than `CGDisplayStream` or `ScreenCaptureKit` because
///    both streaming APIs deliver frames by invoking an Objective-C block on a
///    dispatch queue, which `dart:ffi` cannot construct.
///
/// 1a. **Which isolate it runs on**:
///    The grab and the encode are blocking C calls, so they run on a worker
///    isolate ([MacosCaptureWorker]) rather than on whichever isolate asked for
///    the frame. Running them inline is what made a streaming session
///    disconnect roughly every ten seconds: the desktop's event loop spent most
///    of its time inside CoreGraphics, the transport's one-second heartbeat
///    timer did not get to run, and the phone declared the peer gone after two
///    and a half seconds of silence. The symptom looked like a network fault
///    and was entirely local.
///
/// 2. **Encoding (`ImageIO`)**:
///    Encodes the captured `CGImage` to JPEG using `CGImageDestinationCreateWithData`,
///    `CGImageDestinationAddImage`, and `CGImageDestinationFinalize`. VideoToolbox
///    also requires asynchronous callbacks, making ImageIO JPEG the synchronous
///    codec for `ScreenCodec.jpeg`.
///
/// 3. **Permission checking**:
///    macOS gates screen recording behind TCC without throwing errors (returns
///    desktop wallpaper without windows). `CGPreflightScreenCaptureAccess` is
///    checked up front so [isAvailable] is false if permission is missing.
///
/// 4. **Memory management**:
///    Core Foundation objects (`CGImageRef`, `CFMutableDataRef`, `CFStringRef`,
///    `CGImageDestinationRef`, `CGContextRef`, `CGColorSpaceRef`) are manually
///    reference-counted. Every created object is released in a `finally` block
///    to prevent leaks during continuous streaming.
final class MacosScreenCaptureBackend implements ScreenCaptureBackend {
  /// Builds a backend over [bindings], or over freshly resolved ones.
  ///
  /// Supplying bindings also turns the worker isolate off — see [captureFrame]
  /// for why the two cannot coexist.
  factory MacosScreenCaptureBackend({CoreGraphicsBindings? bindings}) {
    final resolved = bindings ?? CoreGraphicsBindings();
    return MacosScreenCaptureBackend._(
      bindings: resolved,
      capturer: MacosScreenCapturer(resolved),
      worker: bindings == null ? MacosCaptureWorker() : null,
    );
  }

  MacosScreenCaptureBackend._({
    required CoreGraphicsBindings bindings,
    required MacosScreenCapturer capturer,
    required MacosCaptureWorker? worker,
  })  : _bindings = bindings,
        _capturer = capturer,
        _worker = worker;

  final CoreGraphicsBindings _bindings;
  final MacosScreenCapturer _capturer;
  final MacosCaptureWorker? _worker;
  final Log _log = Log.scoped('native.screen_capture.macos');

  bool _disposed = false;

  @override
  bool get isAvailable => !_disposed && checkPermission();

  @override
  String? get unavailableReason {
    if (_disposed) return 'backend disposed';
    if (!checkPermission()) {
      return 'Remote Link needs Screen Recording permission. Enable it in System '
          'Settings › Privacy & Security › Screen Recording, then restart '
          'Remote Link.';
    }
    return null;
  }

  @override
  bool checkPermission() {
    if (_disposed) return false;
    try {
      return _bindings.preflightScreenCaptureAccess();
    } on Object catch (e) {
      _log.warn('could not check screen capture permission', error: e);
      return false;
    }
  }

  @override
  bool requestPermission() {
    if (_disposed) return false;
    try {
      return _bindings.requestScreenCaptureAccess();
    } on Object catch (e) {
      _log.warn('could not request screen capture permission', error: e);
      return false;
    }
  }

  @override
  Future<CapturedFrame?> captureFrame({
    int monitorId = kWholeVirtualDesktopMonitorId,
    int maxWidth = 0,
    int maxHeight = 0,
    double quality = kDefaultScreenJpegQuality,
  }) async {
    if (!isAvailable) return null;

    CapturedFrame? captureInline() => _capturer.capture(
          monitorId: monitorId,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          quality: quality,
        );

    // Inline when the caller supplied its own bindings. Those are a test seam,
    // and a `DynamicLibrary` handle cannot cross an isolate boundary, so the
    // worker would silently resolve the real CoreGraphics instead of the
    // bindings the test handed over.
    final worker = _worker;
    if (worker == null || worker.isUnavailable) return captureInline();

    final frame = await worker.capture(
      monitorId: monitorId,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
    );

    // Spawning is only attempted on the first frame, so this is where a failure
    // to start actually shows up. Falling back keeps the stream alive at the
    // cost of a stutter, which beats a viewer that shows nothing.
    if (frame == null && worker.isUnavailable) {
      _log.warn(
        'capture isolate could not start; encoding on the calling isolate '
        'instead, which will make the stream stutter',
      );
      return captureInline();
    }
    return frame;
  }

  /// Reads the pointer on the calling isolate, never through the worker.
  ///
  /// The worker exists to keep a thirty-millisecond encode off the event loop.
  /// This is ten microseconds, so a round trip through a port would cost more
  /// than the work — and it would queue behind whatever frame the worker is
  /// encoding, which is exactly the coupling this call exists to break.
  @override
  ({double x, double y})? cursorPosition({
    int monitorId = kWholeVirtualDesktopMonitorId,
  }) {
    if (!isAvailable) return null;
    return _capturer.cursorPosition(monitorId: monitorId);
  }

  @override
  void dispose() {
    _disposed = true;
    _worker?.dispose();
  }
}
