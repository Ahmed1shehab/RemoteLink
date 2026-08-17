/// Display screen capture backend for RemoteLink host platforms.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// Default JPEG quality for a live screen stream.
///
/// ImageIO's own default, used when no options dictionary is supplied, is close
/// to lossless. On a Retina desk that is a 400–800 KB frame, and thirty of
/// those a second is more than a Wi-Fi link carries — the frames queue, the
/// queue is delay, and the viewer falls further behind the longer it watches.
///
/// This is deliberately lower than a value you would pick for a photograph. The
/// subject is text and flat UI at a size the phone has already scaled down;
/// the artefacts land below what the panel resolves, and the payload is roughly
/// a tenth the size. Latency is the feature here and sharpness is what pays
/// for it.
const double kDefaultScreenJpegQuality = 0.55;

/// Lowest quality [screenJpegQualityForBitrate] will return.
///
/// Below this JPEG stops trading detail for size and starts producing blocking
/// artefacts across flat UI surfaces, which costs bytes of its own.
const double kMinScreenJpegQuality = 0.3;

/// Highest quality [screenJpegQualityForBitrate] will return.
///
/// Short of 1.0 deliberately. The top of the JPEG quality range buys almost
/// nothing visible and costs a great deal of size, and a peer asking for a
/// 100 Mbps stream is stating a ceiling, not asking to spend it.
const double kMaxScreenJpegQuality = 0.85;

/// Encoder quality for a stream that asked for [targetBitrateKbps].
///
/// `ScreenStreamStart.targetBitrateKbps` has been on the wire since the
/// protocol was defined and nothing read it. That left the phone with no way to
/// say "this link is poor, send me less" other than asking for a smaller
/// picture, which trades away legibility rather than fidelity — the wrong knob.
///
/// The mapping is linear in the log of the requested rate rather than in the
/// rate itself, because perceived quality is: the difference between 1 and
/// 2 Mbps is obvious and the difference between 40 and 80 Mbps is not.
double screenJpegQualityForBitrate(int targetBitrateKbps) {
  if (targetBitrateKbps <= 0) return kDefaultScreenJpegQuality;

  // Anchored so the protocol's own default of 5000 kbps lands on
  // [kDefaultScreenJpegQuality]: a peer that expresses no opinion gets the
  // value chosen for a typical link, and only a peer that asks for something
  // different moves off it.
  const anchorKbps = 5000.0;
  const perDoubling = 0.12;

  final ratio = (targetBitrateKbps / anchorKbps).clamp(1e-6, 1e6);
  final doublings = math.log(ratio) / math.ln2;
  final quality = kDefaultScreenJpegQuality + doublings * perDoubling;

  return quality.clamp(kMinScreenJpegQuality, kMaxScreenJpegQuality);
}

/// A single captured and encoded screen frame.
@immutable
final class CapturedFrame {
  const CapturedFrame({
    required this.width,
    required this.height,
    required this.data,
    this.cursorX,
    this.cursorY,
  });

  /// Where the pointer sits within this frame, in 0..1, or null if it is not on
  /// the captured display.
  ///
  /// Separate from [data] because the capture APIs do not composite the cursor
  /// into the image — see `ScreenFrame.cursorX` for what that costs a viewer.
  final double? cursorX;
  final double? cursorY;

  /// Decoded width in pixels.
  final int width;

  /// Decoded height in pixels.
  final int height;

  /// Encoded frame payload (e.g. JPEG bytes).
  final Uint8List data;
}

/// Captures display frames on the host.
///
/// Separate from `InputBackend` and `MediaBackend` because the mechanisms have
/// nothing in common: input is synthesised HID events on a microsecond budget,
/// media control goes through transport sessions/audio services, and screen
/// capture talks to display hardware, window servers, or graphics pipelines.
abstract interface class ScreenCaptureBackend {
  /// Whether this backend can capture display frames and permission is granted.
  bool get isAvailable;

  /// Human-readable reason [isAvailable] is false.
  String? get unavailableReason;

  /// Checks if screen capture permission is currently granted.
  bool checkPermission();

  /// Requests screen capture permission from the OS.
  bool requestPermission();

  /// Captures a single frame of the display identified by [monitorId].
  ///
  /// [monitorId] of 0 ([kWholeVirtualDesktopMonitorId]) captures the main or combined display.
  /// [maxWidth] and [maxHeight] constrain the output size (0 means unconstrained).
  /// [quality] is the lossy encoder quality in 0..1; see
  /// [kDefaultScreenJpegQuality] for why the default is low.
  /// Returns `null` if capture failed (e.g. invalid monitor or display error).
  Future<CapturedFrame?> captureFrame({
    int monitorId = kWholeVirtualDesktopMonitorId,
    int maxWidth = 0,
    int maxHeight = 0,
    double quality = kDefaultScreenJpegQuality,
  });

  void dispose();
}

/// Fallback backend for unsupported platforms or missing permissions.
final class UnsupportedScreenCaptureBackend implements ScreenCaptureBackend {
  const UnsupportedScreenCaptureBackend([this.unavailableReason]);

  @override
  final String? unavailableReason;

  @override
  bool get isAvailable => false;

  @override
  bool checkPermission() => false;

  @override
  bool requestPermission() => false;

  @override
  Future<CapturedFrame?> captureFrame({
    int monitorId = kWholeVirtualDesktopMonitorId,
    int maxWidth = 0,
    int maxHeight = 0,
    double quality = kDefaultScreenJpegQuality,
  }) async =>
      null;

  @override
  void dispose() {}
}
