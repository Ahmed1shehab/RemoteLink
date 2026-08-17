@TestOn('mac-os')
library;

import 'dart:async';

import 'package:rl_native/rl_native.dart';
import 'package:rl_native/src/macos/macos_capture_worker.dart';
import 'package:test/test.dart';

void main() {
  group('the capture worker isolate', () {
    late MacosCaptureWorker worker;

    setUp(() => worker = MacosCaptureWorker());
    tearDown(() => worker.dispose());

    test('encodes a real JPEG off the calling isolate', () async {
      // No Screen Recording permission is needed to reach this path:
      // `CGDisplayCreateImage` without it returns the desktop picture minus
      // every window, which still encodes. That is exactly why the permission
      // has to be checked separately — the failure mode is a valid frame
      // showing nothing, not an error.
      final frame = await worker.capture(
        monitorId: 0,
        maxWidth: 640,
        maxHeight: 640,
        quality: 0.5,
      );

      expect(frame, isNotNull, reason: 'the worker isolate produced no frame');
      expect(frame!.width, greaterThan(0));
      expect(frame.height, greaterThan(0));
      expect(frame.width, lessThanOrEqualTo(640));
      expect(frame.height, lessThanOrEqualTo(640));

      // SOI and EOI. Proves ImageIO ran to completion on the worker isolate
      // rather than returning a truncated buffer — FFI, CoreGraphics and
      // ImageIO all being usable off the main thread is the assumption this
      // whole design rests on.
      expect(frame.data.length, greaterThan(4));
      expect(frame.data[0], 0xFF);
      expect(frame.data[1], 0xD8);
      expect(frame.data[frame.data.length - 2], 0xFF);
      expect(frame.data[frame.data.length - 1], 0xD9);
    });

    test('leaves the calling isolate free while it works', () async {
      // The reason the worker exists. With the encode inline, a 10 ms periodic
      // timer on this isolate cannot fire during a capture, and the timer that
      // could not fire in production was the transport's one-second heartbeat —
      // which is why a session that was merely streaming kept being declared
      // dead.
      var ticks = 0;
      final ticker = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => ticks++,
      );
      addTearDown(ticker.cancel);

      for (var i = 0; i < 5; i++) {
        await worker.capture(
          monitorId: 0,
          maxWidth: 1440,
          maxHeight: 1440,
          quality: 0.55,
        );
      }
      ticker.cancel();

      // Five captures take well over 100 ms of CPU, so a responsive loop fires
      // many times. Inline, this count collapses towards zero.
      expect(
        ticks,
        greaterThan(4),
        reason: 'the calling isolate was blocked while frames were encoded',
      );
    });

    test('lower quality produces a smaller frame', () async {
      // The knob that turned a 2.5 MB frame into 210 KB. Nothing downstream can
      // tell the difference between a quality setting that works and one that
      // is silently ignored, which is what happens when the properties go to
      // the destination instead of to the image.
      final coarse = await worker.capture(
        monitorId: 0,
        maxWidth: 1440,
        maxHeight: 1440,
        quality: 0.3,
      );
      final fine = await worker.capture(
        monitorId: 0,
        maxWidth: 1440,
        maxHeight: 1440,
        quality: 0.95,
      );

      expect(coarse, isNotNull);
      expect(fine, isNotNull);
      expect(coarse!.data.length, lessThan(fine!.data.length));
    });

    test('a smaller requested size produces a smaller picture', () async {
      final small = await worker.capture(
        monitorId: 0,
        maxWidth: 320,
        maxHeight: 320,
        quality: 0.55,
      );
      final large = await worker.capture(
        monitorId: 0,
        maxWidth: 1280,
        maxHeight: 1280,
        quality: 0.55,
      );

      expect(small!.width, lessThan(large!.width));
      expect(small.data.length, lessThan(large.data.length));
    });

    test('answers concurrent requests to the right caller', () async {
      // The frame loop issues one at a time, but a response routed by position
      // rather than by id would still pass that test and fail the moment
      // anything else asked for a frame — a preview thumbnail, a second viewer.
      final results =
          await Future.wait<CapturedFrame?>(<Future<CapturedFrame?>>[
        worker.capture(
            monitorId: 0, maxWidth: 200, maxHeight: 200, quality: 0.5),
        worker.capture(
            monitorId: 0, maxWidth: 800, maxHeight: 800, quality: 0.5),
      ]);

      final small = results[0]!;
      final large = results[1]!;
      expect(small.width, lessThanOrEqualTo(200));
      expect(large.width, lessThanOrEqualTo(800));
      expect(small.width, lessThan(large.width));
    });

    test('a disposed worker returns null rather than hanging', () async {
      worker.dispose();
      expect(
        await worker.capture(
          monitorId: 0,
          maxWidth: 640,
          maxHeight: 640,
          quality: 0.5,
        ),
        isNull,
      );
    });
  });
}
