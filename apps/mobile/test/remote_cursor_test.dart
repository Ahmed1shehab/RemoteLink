import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/screen/remote_cursor.dart';

void main() {
  const surface = Key('cursor-surface');

  /// Puts the cursor in the Stack it needs, at a known size.
  Future<void> pump(
    WidgetTester tester, {
    required Offset? normalised,
    Size container = const Size(400, 800),
    Size image = const Size(1600, 800),
  }) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: surface,
              width: container.width,
              height: container.height,
              child: Stack(
                children: <Widget>[
                  RemoteCursor(
                    normalised: normalised,
                    containerSize: container,
                    imageSize: image,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// Where the cursor sits inside its own container.
  ///
  /// Relative, not global: the test surface is 800x600 and the container is
  /// centred in it, so a global assertion would be measuring the harness's
  /// layout as much as the widget's.
  Offset cursorOffset(WidgetTester tester) =>
      tester.getTopLeft(find.byType(CustomPaint).first) -
      tester.getTopLeft(find.byKey(surface));

  group('the desk pointer drawn over the stream', () {
    testWidgets('appears where the frame says the pointer is', (tester) async {
      // A 2:1 desk in a 1:2 widget, so the picture is drawn 400x200 centred
      // vertically: the middle of the desk is at (200, 400) in widget space,
      // and the top of the picture is 300 down rather than at 0. Asserting a
      // concrete position is the point — a cursor drawn against the widget
      // instead of against the letterboxed picture still "appears", just in
      // the wrong place, and a findsOneWidget check would not notice.
      await pump(tester, normalised: const Offset(0.5, 0.5));

      final position = cursorOffset(tester);
      expect(position.dx, closeTo(200, 0.01));
      expect(position.dy, closeTo(400, 0.01));
    });

    testWidgets('follows the pointer to a corner of the desk', (tester) async {
      await pump(tester, normalised: Offset.zero);

      final position = cursorOffset(tester);
      expect(position.dx, closeTo(0, 0.01));
      // Not 0: the top of a letterboxed 2:1 picture in a 400x800 box.
      expect(position.dy, closeTo(300, 0.01));
    });

    testWidgets('draws nothing when the pointer is on another display',
        (tester) async {
      await pump(tester, normalised: null);
      expect(find.byType(CustomPaint), findsNothing);
    });

    testWidgets('draws nothing for a position outside the picture',
        (tester) async {
      await pump(tester, normalised: const Offset(1.4, 0.5));
      expect(find.byType(CustomPaint), findsNothing);
    });

    testWidgets('never swallows a touch', (tester) async {
      // The cursor sits exactly under the spot the user is about to tap, so an
      // overlay that hit-tests there would eat the taps that matter most —
      // and the symptom would be "tapping near the pointer does nothing",
      // which reads as a coordinate bug rather than as an overlay.
      var tapped = false;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: surface,
              width: 400,
              height: 400,
              child: Stack(
                children: <Widget>[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                    child: const SizedBox.expand(),
                  ),
                  const RemoteCursor(
                    normalised: Offset(0.5, 0.5),
                    containerSize: Size(400, 400),
                    imageSize: Size(1600, 800),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Exactly on the cursor's hotspot, which is the centre of the container
      // for a centred pointer.
      final hotspot = tester.getCenter(find.byKey(surface));
      expect(
        tester.getTopLeft(find.byType(CustomPaint).first),
        hotspot,
        reason: 'the test is not tapping where the cursor actually is',
      );

      await tester.tapAt(hotspot);
      expect(tapped, isTrue, reason: 'the cursor overlay intercepted the tap');
    });
  });
}
