import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../screen_capture_backend.dart';
import 'coregraphics_ffi.dart';

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
  MacosScreenCaptureBackend({CoreGraphicsBindings? bindings})
      : _bindings = bindings ?? CoreGraphicsBindings();

  final CoreGraphicsBindings _bindings;
  final Log _log = Log.scoped('native.screen_capture.macos');

  bool _disposed = false;

  @override
  bool get isAvailable => !_disposed && checkPermission();

  @override
  String? get unavailableReason {
    if (_disposed) return 'backend disposed';
    if (!checkPermission()) {
      return 'RemoteLink needs Screen Recording permission. Enable it in System '
          'Settings › Privacy & Security › Screen Recording, then restart '
          'RemoteLink.';
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
  }) async {
    if (!isAvailable) return null;

    final displayId = monitorId == kWholeVirtualDesktopMonitorId
        ? _bindings.mainDisplayId()
        : monitorId;

    final image = _bindings.displayCreateImage(displayId);
    if (image == nullptr) {
      _log.debug(
          () => 'CGDisplayCreateImage returned null for display $displayId');
      return null;
    }

    try {
      final origWidth = _bindings.imageGetWidth(image);
      final origHeight = _bindings.imageGetHeight(image);
      if (origWidth <= 0 || origHeight <= 0) return null;

      var targetWidth = origWidth;
      var targetHeight = origHeight;
      final shouldScale = (maxWidth > 0 && origWidth > maxWidth) ||
          (maxHeight > 0 && origHeight > maxHeight);

      if (shouldScale) {
        final scaleX =
            maxWidth > 0 && origWidth > maxWidth ? maxWidth / origWidth : 1.0;
        final scaleY = maxHeight > 0 && origHeight > maxHeight
            ? maxHeight / origHeight
            : 1.0;
        final scale = (maxWidth > 0 && maxHeight > 0)
            ? (scaleX < scaleY ? scaleX : scaleY)
            : (maxWidth > 0 ? scaleX : scaleY);
        targetWidth = (origWidth * scale).round().clamp(1, origWidth);
        targetHeight = (origHeight * scale).round().clamp(1, origHeight);
      }

      Pointer<Void> imageToEncode = image;
      Pointer<Void> scaledImage = nullptr;
      Pointer<Void> colorSpace = nullptr;
      Pointer<Void> context = nullptr;
      Pointer<CGRect> rect = nullptr;

      if (shouldScale &&
          (targetWidth != origWidth || targetHeight != origHeight)) {
        try {
          colorSpace = _bindings.colorSpaceCreateDeviceRGB();
          if (colorSpace != nullptr) {
            context = _bindings.bitmapContextCreate(
              nullptr,
              targetWidth,
              targetHeight,
              8,
              0,
              colorSpace,
              1, // kCGImageAlphaPremultipliedLast
            );
            if (context != nullptr) {
              rect = calloc<CGRect>();
              rect.ref.origin.x = 0;
              rect.ref.origin.y = 0;
              rect.ref.size.width = targetWidth.toDouble();
              rect.ref.size.height = targetHeight.toDouble();
              _bindings.contextDrawImage(context, rect.ref, image);
              scaledImage = _bindings.bitmapContextCreateImage(context);
              if (scaledImage != nullptr) {
                imageToEncode = scaledImage;
              }
            }
          }
        } finally {
          calloc.free(rect);
          if (context != nullptr) _bindings.release(context);
          if (colorSpace != nullptr) _bindings.release(colorSpace);
        }
      }

      try {
        final jpegBytes = _encodeJpeg(imageToEncode);
        if (jpegBytes == null) return null;
        return CapturedFrame(
          width: targetWidth,
          height: targetHeight,
          data: jpegBytes,
        );
      } finally {
        if (scaledImage != nullptr) {
          _bindings.release(scaledImage);
        }
      }
    } finally {
      _bindings.release(image);
    }
  }

  Uint8List? _encodeJpeg(Pointer<Void> image) {
    final cfData = _bindings.cfDataCreateMutable(nullptr, 0);
    if (cfData == nullptr) return null;

    Pointer<Utf8> utiUtf8 = nullptr;
    Pointer<Void> utiString = nullptr;
    Pointer<Void> destination = nullptr;

    try {
      utiUtf8 = 'public.jpeg'.toNativeUtf8();
      utiString = _bindings.cfStringCreateWithCString(
        nullptr,
        utiUtf8,
        0x08000100, // kCFStringEncodingUTF8
      );
      if (utiString == nullptr) return null;

      destination = _bindings.imageDestinationCreateWithData(
        cfData,
        utiString,
        1,
        nullptr,
      );
      if (destination == nullptr) return null;

      _bindings.imageDestinationAddImage(destination, image, nullptr);
      final success = _bindings.imageDestinationFinalize(destination);
      if (!success) return null;

      final length = _bindings.cfDataGetLength(cfData);
      if (length <= 0) return null;

      final bytePtr = _bindings.cfDataGetBytePtr(cfData);
      if (bytePtr == nullptr) return null;

      return Uint8List.fromList(bytePtr.asTypedList(length));
    } finally {
      if (destination != nullptr) _bindings.release(destination);
      if (utiString != nullptr) _bindings.release(utiString);
      if (utiUtf8 != nullptr) calloc.free(utiUtf8);
      _bindings.release(cfData);
    }
  }

  @override
  void dispose() {
    _disposed = true;
  }
}
