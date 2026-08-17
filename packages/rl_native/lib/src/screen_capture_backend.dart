/// Display screen capture backend for RemoteLink host platforms.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// A single captured and encoded screen frame.
@immutable
final class CapturedFrame {
  const CapturedFrame({
    required this.width,
    required this.height,
    required this.data,
  });

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
  /// Returns `null` if capture failed (e.g. invalid monitor or display error).
  Future<CapturedFrame?> captureFrame({
    int monitorId = kWholeVirtualDesktopMonitorId,
    int maxWidth = 0,
    int maxHeight = 0,
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
  }) async =>
      null;

  @override
  void dispose() {}
}
