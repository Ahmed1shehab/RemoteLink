import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:meta/meta.dart';

/// Turns encoded bytes into a drawable image.
///
/// Injectable so the dropping policy below can be tested against a decoder the
/// test controls, rather than against real JPEG timings.
typedef ScreenFrameDecode = Future<ui.Image> Function(Uint8List bytes);

/// Decodes streamed frames one at a time, always showing the newest.
///
/// Replaces `Image.memory`, which is wrong for a video stream in two ways that
/// compound. It routes every frame through Flutter's `ImageCache`, keyed by the
/// byte list — and since each frame is a fresh list, every one is a miss, so
/// the cache fills with decoded bitmaps that will never be asked for again. At
/// 1440x900 a decoded frame is about 5 MB, so a 100 MB cache holds roughly
/// nineteen of them and evicts continuously; thirty frames a second is 150 MB
/// a second of allocation and eviction, which is the stutter.
///
/// The second problem is queueing. Frames arrive at whatever rate the desk
/// sends them, and if decoding is slower than arrival the backlog grows without
/// limit — the picture falls further behind the desk the longer it runs, which
/// is the lag that does not recover.
///
/// So: one decode in flight, and while it runs at most one frame waits. A
/// second arrival overwrites the first, because a screen frame that has been
/// superseded has no value at all — nobody wants to watch the desk's recent
/// past. The picture then degrades in frame rate under load instead of in
/// latency, which is the right way round.
final class ScreenFrameSink {
  ScreenFrameSink({required this.onImage, ScreenFrameDecode? decode})
      : _decode = decode ?? decodeScreenFrame;

  /// Called with each decoded frame. Ownership passes to the callback, which
  /// must dispose the image when it is done with it.
  final void Function(ui.Image) onImage;

  final ScreenFrameDecode _decode;

  Uint8List? _pending;
  bool _decoding = false;
  bool _disposed = false;

  /// Frames thrown away because a newer one arrived first.
  ///
  /// Not cosmetic: it is the only way to tell "the link is slow" from "the
  /// phone cannot decode fast enough", and the two want opposite fixes.
  int droppedFrames = 0;

  /// Frames handed to the decoder.
  int decodedFrames = 0;

  @visibleForTesting
  bool get isDecoding => _decoding;

  @visibleForTesting
  bool get hasPending => _pending != null;

  /// Offers a frame. It is decoded now, queued as the one waiting frame, or
  /// dropped in favour of a newer one.
  void submit(Uint8List bytes) {
    if (_disposed) return;
    if (_decoding) {
      if (_pending != null) droppedFrames++;
      _pending = bytes;
      return;
    }
    unawaited(_decodeNow(bytes));
  }

  Future<void> _decodeNow(Uint8List bytes) async {
    _decoding = true;
    decodedFrames++;

    ui.Image image;
    try {
      image = await _decode(bytes);
    } on Object {
      // A corrupt or truncated frame is not worth ending the stream over. The
      // next one arrives in about thirty milliseconds and is very likely fine.
      _decoding = false;
      _startPending();
      return;
    }

    _decoding = false;

    // Disposed while this was in flight: nobody will ever draw it, and an image
    // nobody disposes is native memory that is never given back.
    if (_disposed) {
      image.dispose();
      _pending = null;
      return;
    }

    onImage(image);
    _startPending();
  }

  void _startPending() {
    final next = _pending;
    if (next == null || _disposed) return;
    _pending = null;
    unawaited(_decodeNow(next));
  }

  void dispose() {
    _disposed = true;
    _pending = null;
  }
}

/// Decodes one encoded frame.
///
/// Deliberately not `ui.instantiateImageCodec`: going through the descriptor
/// lets every intermediate be disposed explicitly. These are native handles,
/// and leaking one per frame at thirty frames a second is not a slow leak.
Future<ui.Image> decodeScreenFrame(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
