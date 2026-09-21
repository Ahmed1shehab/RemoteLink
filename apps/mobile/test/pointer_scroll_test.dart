import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/input/pointer_controller.dart';

void main() {
  group('two-finger scroll translation', () {
    test('a slow drag still scrolls, a frame at a time', () {
      // Half the default sensitivity, which is what makes this visible: four
      // logical pixels a frame scaled to two used to round to zero pixels and
      // zero lines, so a steady finger produced nothing at all.
      final controller = PointerController(
        settings: const PointerSettings(scrollSensitivity: 0.5),
      );

      var pixels = 0;
      var lines = 0;
      for (var frame = 0; frame < 40; frame++) {
        final scroll = controller.translateScroll(const Offset(0, 4));
        pixels += scroll.pixelsY;
        lines += scroll.linesY;
      }

      // 40 frames x 4 px x 0.5 = 80 px, which is two notches.
      expect(pixels, 80);
      expect(lines, 2);
    });

    test('the fraction of a pixel is carried, not dropped', () {
      final controller = PointerController(
        settings: const PointerSettings(scrollSensitivity: 0.3),
      );

      var pixels = 0;
      for (var frame = 0; frame < 10; frame++) {
        pixels += controller.translateScroll(const Offset(0, 1)).pixelsY;
      }

      // 10 x 0.3 = 3, and dropping each 0.3 would have sent nothing. Allowed
      // to land a pixel short: the last frame's remainder is still carried,
      // and binary arithmetic on 0.3 decides whether it arrives on frame ten
      // or frame eleven.
      expect(pixels, inInclusiveRange(2, 3));
    });

    test('a notch is a notch in either direction', () {
      final natural = PointerController(
        settings: const PointerSettings(),
      ).translateScroll(const Offset(0, 40));
      final inverted = PointerController(
        settings: const PointerSettings(naturalScrolling: false),
      ).translateScroll(const Offset(0, 40));

      expect(natural.linesY, 1);
      expect(natural.pixelsY, 40);
      expect(inverted.linesY, -1);
      expect(inverted.pixelsY, -40);
    });

    test('ending a gesture does not leak its remainder into the next', () {
      final controller = PointerController(
        settings: const PointerSettings(scrollSensitivity: 0.5),
      );

      controller.translateScroll(const Offset(0, 3));
      controller.endGesture();

      // 1 px, not the 2 px a carried 0.5 would have rounded up to.
      expect(controller.translateScroll(const Offset(0, 3)).pixelsY, 1);
    });
  });
}
