import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../screen_capture_backend.dart';
import 'coregraphics_ffi.dart';

/// One display grab and JPEG encode, start to finish, with no `await` in it.
///
/// Separated from the backend because of where it has to run rather than
/// because of what it does. `CGDisplayCreateImage`, the rescale, and the
/// ImageIO encode are all blocking C calls; the `async` on the backend method
/// that used to wrap them was decorative, since nothing inside it ever yielded.
/// On the desktop's UI isolate that meant tens of milliseconds of dead event
/// loop per frame, thirty times a second — and the first thing to suffer was
/// the one-second heartbeat, which is why a session that was only streaming a
/// picture kept being declared dead and reconnecting.
///
/// Nothing here touches a `SendPort`, a `Log`, or any other object that cannot
/// cross an isolate boundary, so the same code runs on a worker isolate in
/// production and inline in tests.
final class MacosScreenCapturer {
  MacosScreenCapturer(this._bindings);

  final CoreGraphicsBindings _bindings;

  /// Grabs [monitorId] and encodes it, or returns null if the display could not
  /// be read.
  ///
  /// Errors are reported as null rather than thrown. The caller is a frame loop:
  /// a display that is asleep, being reconfigured, or momentarily unavailable is
  /// an ordinary event that should cost one dropped frame, not an exception
  /// crossing an isolate boundary.
  CapturedFrame? capture({
    required int monitorId,
    required int maxWidth,
    required int maxHeight,
    required double quality,
  }) {
    final displayId = monitorId == kWholeVirtualDesktopMonitorId
        ? _bindings.mainDisplayId()
        : monitorId;

    final image = _bindings.displayCreateImage(displayId);
    if (image == nullptr) return null;

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
        final jpegBytes = _encodeJpeg(imageToEncode, quality);
        if (jpegBytes == null) return null;
        final cursor = _cursorWithin(displayId);
        return CapturedFrame(
          width: targetWidth,
          height: targetHeight,
          data: jpegBytes,
          cursorX: cursor?.x,
          cursorY: cursor?.y,
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

  /// Where the pointer is inside [monitorId], in 0..1, or null if elsewhere.
  ///
  /// Public and separate from [capture] because it is thousands of times
  /// cheaper — two window-server calls against a grab-scale-encode — and the
  /// stream samples it far more often than it captures.
  ({double x, double y})? cursorPosition({int monitorId = 0}) {
    final displayId = monitorId == 0 ? _bindings.mainDisplayId() : monitorId;
    return _cursorWithin(displayId);
  }

  /// Where the pointer is inside [displayId], in 0..1, or null if elsewhere.
  ///
  /// `CGDisplayCreateImage` composites windows but not the cursor, so this is
  /// the only way the viewer learns where the pointer is. Read here, alongside
  /// the frame, so the position and the picture describe the same instant — a
  /// cursor sampled on a different tick lands visibly beside the thing it is
  /// hovering over during any fast movement.
  ///
  /// `CGEventCreate(null)` returns an event carrying the current pointer
  /// location, which is the documented way to ask without an event to hand and
  /// costs nothing beyond one allocation.
  ({double x, double y})? _cursorWithin(int displayId) {
    final event = _bindings.createEvent(nullptr);
    if (event == nullptr) return null;

    try {
      final location = _bindings.getLocation(event);
      final bounds = _bindings.displayBounds(displayId);
      final width = bounds.size.width;
      final height = bounds.size.height;
      if (width <= 0 || height <= 0) return null;

      final x = (location.x - bounds.origin.x) / width;
      final y = (location.y - bounds.origin.y) / height;

      // Outside this display on a multi-monitor desk. Reporting nothing is
      // right: the pointer genuinely is not in this picture, and clamping it
      // to an edge would draw a cursor that is not there.
      if (!x.isFinite || !y.isFinite) return null;
      if (x < 0 || x > 1 || y < 0 || y > 1) return null;

      return (x: x, y: y);
    } on Object catch (_) {
      return null;
    } finally {
      _bindings.release(event.cast());
    }
  }

  Uint8List? _encodeJpeg(Pointer<Void> image, double quality) {
    final cfData = _bindings.cfDataCreateMutable(nullptr, 0);
    if (cfData == nullptr) return null;

    Pointer<Utf8> utiUtf8 = nullptr;
    Pointer<Void> utiString = nullptr;
    Pointer<Void> destination = nullptr;
    Pointer<Void> options = nullptr;

    try {
      utiUtf8 = 'public.jpeg'.toNativeUtf8();
      utiString = _bindings.cfStringCreateWithCString(
        nullptr,
        utiUtf8,
        0x08000100, // kCFStringEncodingUTF8
      );
      if (utiString == nullptr) return null;

      options = _createQualityOptions(quality);

      destination = _bindings.imageDestinationCreateWithData(
        cfData,
        utiString,
        1,
        nullptr,
      );
      if (destination == nullptr) return null;

      // The quality belongs on the *image*, not on the destination: ImageIO
      // reads `kCGImageDestinationLossyCompressionQuality` from the per-image
      // properties passed to AddImage. Passing it to the destination's own
      // options instead is silently ignored, which looks exactly like a
      // quality setting that does nothing.
      _bindings.imageDestinationAddImage(destination, image, options);
      final success = _bindings.imageDestinationFinalize(destination);
      if (!success) return null;

      final length = _bindings.cfDataGetLength(cfData);
      if (length <= 0) return null;

      final bytePtr = _bindings.cfDataGetBytePtr(cfData);
      if (bytePtr == nullptr) return null;

      return Uint8List.fromList(bytePtr.asTypedList(length));
    } finally {
      if (destination != nullptr) _bindings.release(destination);
      if (options != nullptr) _bindings.release(options);
      if (utiString != nullptr) _bindings.release(utiString);
      if (utiUtf8 != nullptr) calloc.free(utiUtf8);
      _bindings.release(cfData);
    }
  }

  /// Builds `{kCGImageDestinationLossyCompressionQuality: quality}`.
  ///
  /// Returns [nullptr] if any step fails, which the caller passes straight to
  /// ImageIO — a null properties dictionary is legal and simply means "your
  /// defaults". A frame at the wrong quality beats no frame at all.
  ///
  /// The key is built as a plain string rather than read from ImageIO's
  /// exported `kCGImageDestinationLossyCompressionQuality` symbol. The
  /// dictionary uses `kCFTypeDictionaryKeyCallBacks`, so lookup is by `CFEqual`
  /// on the string's contents and an identical string matches. Doing it this
  /// way keeps the binding to a function table rather than to a data symbol
  /// whose address is not part of the documented ABI.
  Pointer<Void> _createQualityOptions(double quality) {
    final clamped = quality.isFinite ? quality.clamp(0.0, 1.0) : 1.0;

    Pointer<Utf8> keyUtf8 = nullptr;
    Pointer<Void> keyString = nullptr;
    Pointer<Void> number = nullptr;
    Pointer<Double> value = nullptr;
    Pointer<Pointer<Void>> keys = nullptr;
    Pointer<Pointer<Void>> values = nullptr;

    try {
      keyUtf8 = 'kCGImageDestinationLossyCompressionQuality'.toNativeUtf8();
      keyString = _bindings.cfStringCreateWithCString(
        nullptr,
        keyUtf8,
        0x08000100, // kCFStringEncodingUTF8
      );
      if (keyString == nullptr) return nullptr;

      value = calloc<Double>();
      value.value = clamped.toDouble();
      number = _bindings.cfNumberCreate(
        nullptr,
        kCFNumberFloat64Type,
        value.cast(),
      );
      if (number == nullptr) return nullptr;

      keys = calloc<Pointer<Void>>();
      values = calloc<Pointer<Void>>();
      keys.value = keyString;
      values.value = number;

      // The dictionary retains both entries, so releasing them below is
      // correct and the dictionary the caller gets owns its contents.
      return _bindings.cfDictionaryCreate(
        nullptr,
        keys,
        values,
        1,
        _bindings.cfTypeDictionaryKeyCallBacks,
        _bindings.cfTypeDictionaryValueCallBacks,
      );
    } on Object catch (_) {
      // No logging here on purpose: this runs on a worker isolate where a
      // scoped logger would write to a sink nobody is reading.
      return nullptr;
    } finally {
      if (number != nullptr) _bindings.release(number);
      if (keyString != nullptr) _bindings.release(keyString);
      calloc
        ..free(value)
        ..free(keys)
        ..free(values);
      if (keyUtf8 != nullptr) calloc.free(keyUtf8);
    }
  }
}
