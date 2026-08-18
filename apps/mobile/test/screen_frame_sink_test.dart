import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/screen/screen_frame_sink.dart';

/// Builds a real, disposable image without decoding anything.
///
/// A real `ui.Image` rather than a stand-in because the thing under test is
/// ownership — who disposes what, and when — and a fake with a boolean flag
/// would be asserting against itself.
Future<ui.Image> _image({int width = 4, int height = 4}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    Uint8List(width * height * 4),
  );
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}

/// A decoder whose completion this test decides.
///
/// The whole policy — one decode at a time, newest waiting frame wins — is
/// about what happens *while* a decode is outstanding, and a decoder that
/// finishes on its own never lets that window be observed.
final class _Gate {
  final List<Completer<ui.Image>> pending = <Completer<ui.Image>>[];
  final List<Uint8List> asked = <Uint8List>[];

  Future<ui.Image> decode(Uint8List bytes) {
    asked.add(bytes);
    final completer = Completer<ui.Image>();
    pending.add(completer);
    return completer.future;
  }

  /// Completes the oldest outstanding decode.
  Future<void> finish({int width = 4}) async {
    final image = await _image(width: width);
    pending.removeAt(0).complete(image);
    // Two turns: one for the sink's `await` to resume, one for the follow-on
    // decode it starts.
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> fail() async {
    pending.removeAt(0).completeError(Exception('corrupt frame'));
    await Future<void>.delayed(Duration.zero);
  }
}

Uint8List _bytes(int marker) => Uint8List.fromList(<int>[marker]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScreenFrameSink', () {
    test('decodes the first frame and hands it over', () async {
      final gate = _Gate();
      final received = <ui.Image>[];
      final sink = ScreenFrameSink(onImage: received.add, decode: gate.decode)
        ..submit(_bytes(1));

      await gate.finish();

      expect(received, hasLength(1));
      expect(received.single.width, 4);
      sink.dispose();
      received.single.dispose();
    });

    test('never runs two decodes at once', () async {
      // Concurrent decodes are how a phone falls over: each one holds a full
      // uncompressed bitmap, so the memory cost is the number in flight.
      final gate = _Gate();
      final sink =
          ScreenFrameSink(onImage: (i) => i.dispose(), decode: gate.decode)
            ..submit(_bytes(1))
            ..submit(_bytes(2))
            ..submit(_bytes(3));

      expect(gate.pending, hasLength(1));
      expect(gate.asked, hasLength(1));
      sink.dispose();
    });

    test('a frame superseded while waiting is dropped, not queued', () async {
      // The point of the whole class. Queueing means the picture falls further
      // behind the desk the longer the stream runs and never catches up; nobody
      // watching a live screen wants to be shown its recent past.
      final gate = _Gate();
      final sink =
          ScreenFrameSink(onImage: (i) => i.dispose(), decode: gate.decode)
            ..submit(_bytes(1))
            ..submit(_bytes(2))
            ..submit(_bytes(3))
            ..submit(_bytes(4));

      await gate.finish();

      expect(
        gate.asked.map((b) => b.first),
        <int>[1, 4],
        reason: 'frames 2 and 3 were already stale when the decoder freed up',
      );
      expect(sink.droppedFrames, 2);
      sink.dispose();
    });

    test('a steady stream slower than the decoder drops nothing', () async {
      final gate = _Gate();
      final sink =
          ScreenFrameSink(onImage: (i) => i.dispose(), decode: gate.decode);

      for (var i = 1; i <= 5; i++) {
        sink.submit(_bytes(i));
        await gate.finish();
      }

      expect(gate.asked, hasLength(5));
      expect(sink.droppedFrames, 0);
      sink.dispose();
    });

    test('a frame that fails to decode does not end the stream', () async {
      // A truncated or corrupt frame is a passing event on a lossy link. The
      // next one is about thirty milliseconds away and very likely fine.
      final gate = _Gate();
      final received = <ui.Image>[];
      final sink = ScreenFrameSink(onImage: received.add, decode: gate.decode)
        ..submit(_bytes(1))
        ..submit(_bytes(2));

      await gate.fail();
      expect(gate.asked.map((b) => b.first), <int>[1, 2]);

      await gate.finish();
      expect(received, hasLength(1));

      sink.dispose();
      for (final image in received) {
        image.dispose();
      }
    });

    test('an image decoded after dispose is freed, not handed over', () async {
      // Native memory. An image nobody disposes is never given back, and this
      // happens on every stream that ends while a decode is in flight — which
      // is most of them, since leaving the screen is what stops the stream.
      final gate = _Gate();
      final received = <ui.Image>[];
      final sink = ScreenFrameSink(onImage: received.add, decode: gate.decode)
        ..submit(_bytes(1));

      sink.dispose();
      final image = await _image();
      gate.pending.removeAt(0).complete(image);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      expect(image.debugDisposed, isTrue);
    });

    test('a frame waiting at dispose is never decoded', () async {
      final gate = _Gate();
      final sink =
          ScreenFrameSink(onImage: (i) => i.dispose(), decode: gate.decode)
            ..submit(_bytes(1))
            ..submit(_bytes(2));

      sink.dispose();
      await gate.finish();

      expect(gate.asked, hasLength(1));
    });

    test('submitting after dispose does nothing', () async {
      final gate = _Gate();
      ScreenFrameSink(onImage: (i) => i.dispose(), decode: gate.decode)
        ..dispose()
        ..submit(_bytes(1));

      expect(gate.asked, isEmpty);
    });
  });

  group('decodeScreenFrame', () {
    test('decodes real encoded bytes to an image of the right size', () async {
      // The default decoder, against bytes a codec actually produced. The
      // injectable one above proves the policy; this proves the policy is
      // wrapped around something that works.
      final source = await _image(width: 7, height: 3);
      final encoded = await source.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();

      final decoded = await decodeScreenFrame(
        encoded!.buffer.asUint8List(),
      );

      expect(decoded.width, 7);
      expect(decoded.height, 3);
      decoded.dispose();
    });

    test('rejects bytes that are not an image', () async {
      await expectLater(
        decodeScreenFrame(Uint8List.fromList(<int>[1, 2, 3, 4])),
        throwsA(anything),
      );
    });
  });
}
