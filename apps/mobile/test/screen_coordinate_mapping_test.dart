import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/screen/screen_coordinate_mapping.dart';

void main() {
  group('computeContainedImageRect', () {
    test('returns Rect.zero on invalid/empty dimensions', () {
      expect(
        computeContainedImageRect(
          containerSize: Size.zero,
          imageSize: const Size(1920, 1080),
        ),
        Rect.zero,
      );
      expect(
        computeContainedImageRect(
          containerSize: const Size(400, 800),
          imageSize: Size.zero,
        ),
        Rect.zero,
      );
      expect(
        computeContainedImageRect(
          containerSize: const Size(-10, 800),
          imageSize: const Size(1920, 1080),
        ),
        Rect.zero,
      );
      expect(
        computeContainedImageRect(
          containerSize: const Size(400, 800),
          imageSize: const Size(1920, -10),
        ),
        Rect.zero,
      );
    });

    test('computes centered letterbox rectangle for wide frame in tall widget',
        () {
      // 16:9 frame in 1:2 widget -> letterboxed top and bottom
      final rect = computeContainedImageRect(
        containerSize: const Size(400, 800),
        imageSize: const Size(1920, 1080),
      );

      // scale = min(400/1920, 800/1080) = 400 / 1920 = 5/24 (~0.208333)
      // drawnWidth = 400
      // drawnHeight = 1080 * 5/24 = 225
      // top = (800 - 225) / 2 = 287.5
      expect(rect.left, 0.0);
      expect(rect.top, 287.5);
      expect(rect.width, 400.0);
      expect(rect.height, 225.0);
      expect(rect.right, 400.0);
      expect(rect.bottom, 512.5);
    });

    test('computes centered pillarbox rectangle for tall frame in wide widget',
        () {
      // 9:16 frame in 2:1 widget -> pillarboxed left and right
      final rect = computeContainedImageRect(
        containerSize: const Size(800, 400),
        imageSize: const Size(1080, 1920),
      );

      // scale = min(800/1080, 400/1920) = 400 / 1920 = 5/24 (~0.208333)
      // drawnWidth = 1080 * 5/24 = 225
      // drawnHeight = 400
      // left = (800 - 225) / 2 = 287.5
      expect(rect.left, 287.5);
      expect(rect.top, 0.0);
      expect(rect.width, 225.0);
      expect(rect.height, 400.0);
      expect(rect.right, 512.5);
      expect(rect.bottom, 400.0);
    });
  });

  group('mapTouchToNormalisedCoordinates', () {
    test('tap at the centre maps to (0.5, 0.5)', () {
      // Wide frame in tall widget
      final centerWideInTall = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(200, 400),
        containerSize: const Size(400, 800),
        imageSize: const Size(1920, 1080),
      );
      expect(centerWideInTall, isNotNull);
      expect(centerWideInTall!.dx, closeTo(0.5, 1e-6));
      expect(centerWideInTall.dy, closeTo(0.5, 1e-6));

      // Tall frame in wide widget
      final centerTallInWide = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(400, 200),
        containerSize: const Size(800, 400),
        imageSize: const Size(1080, 1920),
      );
      expect(centerTallInWide, isNotNull);
      expect(centerTallInWide!.dx, closeTo(0.5, 1e-6));
      expect(centerTallInWide.dy, closeTo(0.5, 1e-6));
    });

    test('tap at each corner of the drawn image maps to (0,0) and (1,1)', () {
      // Wide frame in tall widget: drawn rect is [0, 287.5, 400, 512.5]
      const containerSize = Size(400, 800);
      const imageSize = Size(1920, 1080);

      final topLeft = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(0.0, 287.5),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(topLeft, const Offset(0.0, 0.0));

      final topRight = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(400.0, 287.5),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(topRight, const Offset(1.0, 0.0));

      final bottomLeft = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(0.0, 512.5),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(bottomLeft, const Offset(0.0, 1.0));

      final bottomRight = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(400.0, 512.5),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(bottomRight, const Offset(1.0, 1.0));
    });

    test(
        'wide frame in tall widget: interior points map correctly, letterbox bars rejected',
        () {
      const containerSize = Size(400, 800);
      const imageSize = Size(1920, 1080);
      // drawn rect: [0, 287.5, 400, 512.5]

      // Interior quarter point: x = 100 (25%), y = 287.5 + 225 * 0.75 = 456.25 (75%)
      final interior = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(100, 456.25),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(interior, isNotNull);
      expect(interior!.dx, closeTo(0.25, 1e-6));
      expect(interior.dy, closeTo(0.75, 1e-6));

      // Touches in top letterbox bar (y < 287.5) are rejected rather than clamped
      final topBarTouch = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(200, 280),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(topBarTouch, isNull);

      final extremeTopBarTouch = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(200, 10),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(extremeTopBarTouch, isNull);

      // Touches in bottom letterbox bar (y > 512.5) are rejected rather than clamped
      final bottomBarTouch = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(200, 520),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(bottomBarTouch, isNull);

      final extremeBottomBarTouch = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(200, 790),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(extremeBottomBarTouch, isNull);
    });

    test(
        'tall frame in wide widget: interior points map correctly, pillarbox bars rejected',
        () {
      const containerSize = Size(800, 400);
      const imageSize = Size(1080, 1920);
      // drawn rect: [287.5, 0, 512.5, 400]

      // Interior quarter point: x = 287.5 + 225 * 0.25 = 343.75 (25%), y = 300 (75%)
      final interior = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(343.75, 300),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(interior, isNotNull);
      expect(interior!.dx, closeTo(0.25, 1e-6));
      expect(interior.dy, closeTo(0.75, 1e-6));

      // Touches in left pillarbox bar (x < 287.5) are rejected rather than clamped
      final leftBarTouch = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(280, 200),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(leftBarTouch, isNull);

      final extremeLeftBarTouch = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(10, 200),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(extremeLeftBarTouch, isNull);

      // Touches in right pillarbox bar (x > 512.5) are rejected rather than clamped
      final rightBarTouch = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(520, 200),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(rightBarTouch, isNull);

      final extremeRightBarTouch = mapTouchToNormalisedCoordinates(
        touchPosition: const Offset(790, 200),
        containerSize: containerSize,
        imageSize: imageSize,
      );
      expect(extremeRightBarTouch, isNull);
    });

    test('returns null for zero or invalid container/image size', () {
      expect(
        mapTouchToNormalisedCoordinates(
          touchPosition: const Offset(100, 100),
          containerSize: Size.zero,
          imageSize: const Size(1920, 1080),
        ),
        isNull,
      );
      expect(
        mapTouchToNormalisedCoordinates(
          touchPosition: const Offset(100, 100),
          containerSize: const Size(400, 800),
          imageSize: Size.zero,
        ),
        isNull,
      );
    });
  });
  _cursorMappingTests();
}

void _cursorMappingTests() {
  group('mapping the desk cursor back onto the picture', () {
    // The inverse has to agree with the forward mapping exactly. If it does
    // not, the drawn pointer sits beside the place a tap actually lands, and
    // the user aims at the drawn one — which is worse than showing no pointer,
    // because a missing pointer is obviously missing and a wrong one is not.
    test('round-trips with the touch mapping at every corner and centre', () {
      const container = Size(400, 800);
      const image = Size(1600, 1000);

      for (final point in <Offset>[
        Offset.zero,
        const Offset(1, 1),
        const Offset(0, 1),
        const Offset(1, 0),
        const Offset(0.5, 0.5),
        const Offset(0.13, 0.87),
      ]) {
        final drawn = mapNormalisedToContainerPosition(
          normalised: point,
          containerSize: container,
          imageSize: image,
        );
        expect(drawn, isNotNull, reason: '$point produced no position');

        final back = mapTouchToNormalisedCoordinates(
          touchPosition: drawn!,
          containerSize: container,
          imageSize: image,
        );
        expect(back, isNotNull, reason: '$point mapped outside the picture');
        expect(back!.dx, closeTo(point.dx, 1e-9));
        expect(back.dy, closeTo(point.dy, 1e-9));
      }
    });

    test('places the cursor inside the letterboxed picture, not the widget',
        () {
      // A wide desk in a tall widget. Mapping against the widget rather than
      // against the drawn rectangle puts the pointer in the black bar — the
      // same off-by-a-letterbox mistake, in the other direction.
      const container = Size(400, 800);
      const image = Size(1600, 800); // 2:1, so drawn 400x200, centred

      final centre = mapNormalisedToContainerPosition(
        normalised: const Offset(0.5, 0.5),
        containerSize: container,
        imageSize: image,
      );

      expect(centre!.dx, closeTo(200, 1e-9));
      expect(centre.dy, closeTo(400, 1e-9));

      final topLeft = mapNormalisedToContainerPosition(
        normalised: Offset.zero,
        containerSize: container,
        imageSize: image,
      );
      // 300, not 0: the picture starts below the bar.
      expect(topLeft!.dy, closeTo(300, 1e-9));
      expect(topLeft.dx, closeTo(0, 1e-9));
    });

    test('refuses a position that is not on the picture', () {
      const container = Size(400, 800);
      const image = Size(1600, 1000);

      for (final bad in <Offset>[
        const Offset(-0.01, 0.5),
        const Offset(1.01, 0.5),
        const Offset(0.5, -0.01),
        const Offset(0.5, 1.01),
        const Offset(double.nan, 0.5),
        const Offset(0.5, double.infinity),
      ]) {
        expect(
          mapNormalisedToContainerPosition(
            normalised: bad,
            containerSize: container,
            imageSize: image,
          ),
          isNull,
          reason: 'drew a cursor at $bad',
        );
      }
    });

    test('refuses a container or image that cannot be drawn in', () {
      for (final sizes in <List<Size>>[
        <Size>[Size.zero, const Size(100, 100)],
        <Size>[const Size(100, 100), Size.zero],
        <Size>[const Size(-100, 100), const Size(100, 100)],
      ]) {
        expect(
          mapNormalisedToContainerPosition(
            normalised: const Offset(0.5, 0.5),
            containerSize: sizes[0],
            imageSize: sizes[1],
          ),
          isNull,
        );
      }
    });
  });
}
