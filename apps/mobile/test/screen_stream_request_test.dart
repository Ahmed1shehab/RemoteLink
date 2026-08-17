import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/screen/screen_stream_request.dart';
import 'package:rl_protocol/rl_protocol.dart';

void main() {
  group('the frame size this phone asks the desk for', () {
    test('never asks for an unconstrained frame', () {
      // `maxWidth: 0` means "native resolution" on the wire. A phone that sends
      // it asks a Retina desk for a 2560-pixel-wide JPEG thirty times a second.
      // No input may produce it — including the degenerate ones below, which is
      // where a size calculation usually leaks a zero.
      for (final size in <Size>[
        Size.zero,
        const Size(0, 800),
        const Size(400, 0),
        const Size(double.nan, double.nan),
        const Size(double.infinity, double.infinity),
        const Size(-400, -800),
      ]) {
        final request = screenStreamRequestFor(monitorId: 3, logicalSize: size);
        expect(
          request.maxWidth,
          greaterThanOrEqualTo(kMinStreamedFrameWidth),
          reason: 'a $size viewport produced an unusable width',
        );
        expect(request.maxHeight, greaterThanOrEqualTo(kMinStreamedFrameWidth));
      }
    });

    test('stays under the cap on a large high-density phone', () {
      // An iPhone 17 in portrait is roughly this. Scaled by the pixel factor it
      // would ask for 1748, which is where the cap has to bite — this is the
      // realistic device, not a contrived one.
      final request = screenStreamRequestFor(
        monitorId: 0,
        logicalSize: const Size(402, 874),
      );

      expect(request.maxWidth, kMaxStreamedFrameWidth);
      expect(request.maxHeight, kMaxStreamedFrameWidth);
    });

    test('asks for the same size whichever way the phone is held', () {
      // The viewer rotates, and the request is sent once — whichever
      // orientation it happens to be sent in. A request that shrank because
      // the phone was upright would leave the landscape picture soft.
      final portrait = screenStreamRequestFor(
        monitorId: 0,
        logicalSize: const Size(402, 874),
      );
      final landscape = screenStreamRequestFor(
        monitorId: 0,
        logicalSize: const Size(874, 402),
      );

      expect(landscape.maxWidth, portrait.maxWidth);
      expect(landscape.maxHeight, portrait.maxHeight);
    });

    test('scales with a smaller screen rather than always hitting the cap', () {
      // Proves the size is actually derived from the viewport. Without this a
      // hard-coded constant would satisfy every other test in this group.
      final small = screenStreamRequestFor(
        monitorId: 0,
        logicalSize: const Size(320, 568),
      );

      expect(small.maxWidth, lessThan(kMaxStreamedFrameWidth));
      expect(small.maxWidth, greaterThanOrEqualTo(kMinStreamedFrameWidth));
    });

    test('quotes back the monitor being watched', () {
      // On a multi-monitor desk a request carrying 0 streams the whole virtual
      // desktop instead of the display the user picked.
      final request = screenStreamRequestFor(
        monitorId: 7,
        logicalSize: const Size(402, 874),
      );

      expect(request.monitorId, 7);
      expect(request.monitorId, isNot(kWholeVirtualDesktopMonitorId));
    });

    test('asks for JPEG, which is the only codec the desk can encode', () {
      final request = screenStreamRequestFor(
        monitorId: 0,
        logicalSize: const Size(402, 874),
      );

      expect(request.codec, ScreenCodec.jpeg);
      expect(request.targetFps, kStreamedFrameRate);
    });

    test('survives the wire without growing', () {
      // `targetFps` and the dimensions are clamped by the decoder. A request
      // the decoder has to correct is a request the desk will not honour as
      // sent, and the phone would have no idea.
      final sent = screenStreamRequestFor(
        monitorId: 2,
        logicalSize: const Size(402, 874),
      );
      final writer = ByteWriter();
      sent.writeTo(writer);
      final received = ScreenStreamStart.readFrom(ByteReader(writer.toBytes()));

      expect(received.maxWidth, sent.maxWidth);
      expect(received.maxHeight, sent.maxHeight);
      expect(received.targetFps, sent.targetFps);
      expect(received.monitorId, sent.monitorId);
    });
  });
}
