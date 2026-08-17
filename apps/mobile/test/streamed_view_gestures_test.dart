import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/input/pointer_controller.dart';
import 'package:remotelink_mobile/src/features/screen/streamed_view_gestures.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// Drives the recogniser with synthetic pointers and collects what it sends.
///
/// A widget test cannot express most of what matters here — how many fingers
/// were down at the peak, whether a cancelled drag released its button — so the
/// recogniser is exercised directly, as events in and messages out.
final class _Harness {
  _Harness({
    bool gesturesAvailable = false,
    PointerSettings settings = const PointerSettings(),
    Offset? Function(Offset)? toNormalised,
  }) {
    gestures = StreamedViewGestures(
      send: sent.add,
      monitorId: 4,
      gesturesAvailable: gesturesAvailable,
      settings: settings,
      // A square picture filling a 100x100 widget, so widget coordinates are
      // simply percentages. Letterboxing has its own tests in the mapping
      // module; here it would only obscure the gesture behaviour.
      toNormalised: toNormalised ??
          (local) {
            if (local.dx < 0 || local.dx > 100) return null;
            if (local.dy < 0 || local.dy > 100) return null;
            return Offset(local.dx / 100, local.dy / 100);
          },
    );
  }

  late final StreamedViewGestures gestures;
  final List<Message> sent = <Message>[];

  final Map<int, Offset> _at = <int, Offset>{};

  void down(int pointer, Offset position) {
    _at[pointer] = position;
    gestures.onPointerDown(
      PointerDownEvent(pointer: pointer, position: position),
    );
  }

  void move(int pointer, Offset to) {
    final from = _at[pointer]!;
    _at[pointer] = to;
    gestures.onPointerMove(
      PointerMoveEvent(pointer: pointer, position: to, delta: to - from),
    );
  }

  void up(int pointer) {
    gestures.onPointerUp(
      PointerUpEvent(pointer: pointer, position: _at.remove(pointer)!),
    );
  }

  void cancel(int pointer) {
    gestures.onPointerCancel(
      PointerCancelEvent(pointer: pointer, position: _at.remove(pointer)!),
    );
  }

  List<T> ofType<T extends Message>() => sent.whereType<T>().toList();
}

void main() {
  group('one finger', () {
    test('aims where it touches, before any click goes out', () {
      // Order is the assertion. Every button event acts wherever the pointer
      // currently is, so a click sent before the move lands at the previous
      // position — which on a remote desktop means clicking whatever the user
      // last touched rather than what they just tapped.
      final harness = _Harness()
        ..down(1, const Offset(30, 70))
        ..up(1);

      expect(harness.sent.first, isA<MouseMoveAbsolute>());
      final move = harness.sent.first as MouseMoveAbsolute;
      expect(move.x, closeTo(0.3, 1e-9));
      expect(move.y, closeTo(0.7, 1e-9));
      expect(move.monitorId, 4, reason: 'the watched display, not the desktop');

      expect(harness.sent[1], isA<MouseButtonEvent>());
    });

    test('a tap is a left click, down then up', () {
      final harness = _Harness()
        ..down(1, const Offset(50, 50))
        ..up(1);

      final buttons = harness.ofType<MouseButtonEvent>();
      expect(buttons, hasLength(2));
      expect(buttons.every((b) => b.button == MouseButton.left), isTrue);
      expect(buttons[0].pressed, isTrue);
      expect(buttons[1].pressed, isFalse);
    });

    test('a drag moves the pointer and does not click', () {
      final harness = _Harness()..down(1, const Offset(10, 10));
      for (var i = 1; i <= 5; i++) {
        harness.move(1, Offset(10 + i * 10, 10));
      }
      harness.up(1);

      expect(harness.ofType<MouseMoveAbsolute>(), hasLength(6));
      expect(
        harness.ofType<MouseButtonEvent>(),
        isEmpty,
        reason: 'a 50-pixel drag was treated as a tap',
      );
    });

    test('a small wobble still counts as a tap', () {
      // A finger on glass never holds still. Treating three pixels as a drag
      // is what makes tap-to-click feel like it "doesn\'t always work".
      final harness = _Harness()
        ..down(1, const Offset(50, 50))
        ..move(1, const Offset(52, 51))
        ..up(1);

      expect(harness.ofType<MouseButtonEvent>(), hasLength(2));
    });

    test('a touch in a letterbox bar moves nothing', () {
      final harness = _Harness(toNormalised: (_) => null)
        ..down(1, const Offset(50, 50))
        ..move(1, const Offset(60, 50));

      expect(harness.ofType<MouseMoveAbsolute>(), isEmpty);
    });

    test('a second quick tap is reported as a double click', () {
      // Counted on the phone because network jitter can stretch two taps past
      // any threshold the desktop would apply.
      final harness = _Harness()
        ..down(1, const Offset(50, 50))
        ..up(1)
        ..down(2, const Offset(50, 50))
        ..up(2);

      final presses =
          harness.ofType<MouseButtonEvent>().where((b) => b.pressed).toList();
      expect(presses, hasLength(2));
      expect(presses[0].clickCount, 1);
      expect(presses[1].clickCount, 2);
    });
  });

  group('two fingers', () {
    test('tap right-clicks', () {
      final harness = _Harness()
        ..down(1, const Offset(40, 40))
        ..down(2, const Offset(60, 40))
        ..up(1)
        ..up(2);

      final buttons = harness.ofType<MouseButtonEvent>();
      expect(buttons, hasLength(2));
      expect(buttons.every((b) => b.button == MouseButton.right), isTrue);
    });

    test('the finger count is the peak, not the count at lift', () {
      // Fingers never leave the glass together. Reading the count when the
      // gesture ends turns every two-finger tap into a one-finger tap, which
      // is a right click that silently becomes a left click.
      final harness = _Harness()
        ..down(1, const Offset(40, 40))
        ..down(2, const Offset(60, 40))
        ..up(1)
        ..up(2);

      expect(
        harness.ofType<MouseButtonEvent>().first.button,
        MouseButton.right,
      );
    });

    test('drag scrolls rather than moving the pointer', () {
      final harness = _Harness()
        ..down(1, const Offset(40, 40))
        ..down(2, const Offset(60, 40))
        ..move(2, const Offset(60, 90));

      expect(harness.ofType<MouseScroll>(), isNotEmpty);
      expect(
        harness.ofType<MouseMoveAbsolute>(),
        hasLength(1),
        reason: 'only the initial aim; the two-finger drag must not move the '
            'pointer as well as scrolling',
      );
    });

    test('scroll direction follows the natural-scrolling preference', () {
      // Backwards scrolling is instantly obvious and infuriating, and this is
      // the setting that decides it. The streamed view reading a different
      // default from the touchpad would be its own small betrayal.
      List<MouseScroll> scrollWith({required bool natural}) {
        final harness = _Harness(
          settings: PointerSettings(naturalScrolling: natural),
        )
          ..down(1, const Offset(40, 40))
          ..down(2, const Offset(60, 40))
          ..move(2, const Offset(60, 90));
        return harness.ofType<MouseScroll>();
      }

      final naturalScroll = scrollWith(natural: true);
      final invertedScroll = scrollWith(natural: false);
      expect(naturalScroll.first.pixelsY, isNot(0));
      expect(naturalScroll.first.pixelsY, -invertedScroll.first.pixelsY);
    });

    test('pinch is only sent when the desk takes part in gestures', () {
      List<Message> pinchWith({required bool available}) {
        final harness = _Harness(gesturesAvailable: available)
          ..down(1, const Offset(40, 50))
          ..down(2, const Offset(60, 50))
          ..move(1, const Offset(20, 50))
          ..move(2, const Offset(80, 50));
        return harness.sent;
      }

      expect(pinchWith(available: true).whereType<GestureZoom>(), isNotEmpty);
      expect(
        pinchWith(available: false).whereType<GestureZoom>(),
        isEmpty,
        reason: 'sent a gesture the desk never said it would take part in',
      );
    });

    test('a pinch ends when the fingers lift', () {
      // Without the ended phase the desk is left mid-gesture and the next
      // pinch is interpreted as a continuation of this one.
      final harness = _Harness(gesturesAvailable: true)
        ..down(1, const Offset(40, 50))
        ..down(2, const Offset(60, 50))
        ..move(1, const Offset(20, 50))
        ..move(2, const Offset(80, 50))
        ..up(1)
        ..up(2);

      final phases = harness.ofType<GestureZoom>().map((z) => z.phase);
      expect(phases.first, GesturePhase.began);
      expect(phases.last, GesturePhase.ended);
    });
  });

  group('three fingers and more', () {
    test('tap is a middle click', () {
      final harness = _Harness()
        ..down(1, const Offset(30, 40))
        ..down(2, const Offset(50, 40))
        ..down(3, const Offset(70, 40))
        ..up(1)
        ..up(2)
        ..up(3);

      expect(
        harness.ofType<MouseButtonEvent>().first.button,
        MouseButton.middle,
      );
    });

    test('a swipe reports how many fingers made it', () {
      // On macOS the count is the entire meaning of the gesture: three moves
      // between windows, four moves between desktops. A swipe that reports the
      // wrong count does the wrong thing rather than nothing.
      GestureSwipe swipeWith(int fingers) {
        final harness = _Harness();
        for (var i = 1; i <= fingers; i++) {
          harness.down(i, Offset(20.0 * i, 50));
        }
        for (var step = 1; step <= 3; step++) {
          for (var i = 1; i <= fingers; i++) {
            harness.move(i, Offset(20.0 * i + step * 20, 50));
          }
        }
        return harness.ofType<GestureSwipe>().first;
      }

      expect(swipeWith(3).fingerCount, 3);
      expect(swipeWith(4).fingerCount, 4);
    });

    test('a swipe reports the direction it actually went', () {
      GestureSwipe swipeTowards(Offset step) {
        final harness = _Harness();
        for (var i = 1; i <= 3; i++) {
          harness.down(i, const Offset(50, 50) + Offset(i * 5, 0));
        }
        for (var s = 1; s <= 3; s++) {
          for (var i = 1; i <= 3; i++) {
            harness.move(i,
                const Offset(50, 50) + Offset(i * 5, 0) + step * s.toDouble());
          }
        }
        return harness.ofType<GestureSwipe>().first;
      }

      expect(swipeTowards(const Offset(0, -20)).direction, SwipeDirection.up);
      expect(swipeTowards(const Offset(0, 20)).direction, SwipeDirection.down);
      expect(swipeTowards(const Offset(-20, 0)).direction, SwipeDirection.left);
      expect(swipeTowards(const Offset(20, 0)).direction, SwipeDirection.right);
    });

    test('a swipe fires once, not on every frame of movement', () {
      // Repeating would switch desktops four times for one flick.
      final harness = _Harness();
      for (var i = 1; i <= 3; i++) {
        harness.down(i, Offset(20.0 * i, 50));
      }
      for (var step = 1; step <= 10; step++) {
        for (var i = 1; i <= 3; i++) {
          harness.move(i, Offset(20.0 * i, 50 - step * 20));
        }
      }

      expect(harness.ofType<GestureSwipe>(), hasLength(1));
    });

    test('a small three-finger wobble is not a swipe', () {
      final harness = _Harness();
      for (var i = 1; i <= 3; i++) {
        harness.down(i, Offset(20.0 * i, 50));
      }
      for (var i = 1; i <= 3; i++) {
        harness.move(i, Offset(20.0 * i + 4, 52));
      }

      expect(harness.ofType<GestureSwipe>(), isEmpty);
    });
  });

  group('long press to drag', () {
    test('holds the button down, moves, and releases on lift', () {
      // This is how a window gets moved: press its title bar, drag, let go.
      final harness = _Harness()..down(1, const Offset(50, 50));
      harness.gestures.onLongPress();
      harness
        ..move(1, const Offset(80, 50))
        ..up(1);

      final buttons = harness.ofType<MouseButtonEvent>();
      expect(buttons, hasLength(2));
      expect(buttons[0].pressed, isTrue);
      expect(buttons[1].pressed, isFalse);

      // The move has to happen between them, or the drag drops where it began.
      final pressIndex = harness.sent.indexOf(buttons[0]);
      final releaseIndex = harness.sent.indexOf(buttons[1]);
      final movedWhileHeld = harness.sent
          .getRange(pressIndex, releaseIndex)
          .whereType<MouseMoveAbsolute>();
      expect(movedWhileHeld, isNotEmpty);
    });

    test('a drag that ends in a cancel still releases the button', () {
      // Otherwise the desk is left holding the left button with nothing on the
      // phone able to let go — every later tap becomes part of one endless
      // selection.
      final harness = _Harness()..down(1, const Offset(50, 50));
      harness.gestures.onLongPress();
      harness
        ..move(1, const Offset(80, 50))
        ..cancel(1);

      final buttons = harness.ofType<MouseButtonEvent>();
      expect(buttons.last.pressed, isFalse);
      expect(harness.gestures.isDragging, isFalse);
    });

    test('a held drag does not also fire a tap on release', () {
      final harness = _Harness()..down(1, const Offset(50, 50));
      harness.gestures.onLongPress();
      harness.up(1);

      expect(
        harness.ofType<MouseButtonEvent>().where((b) => b.pressed),
        hasLength(1),
        reason: 'the release was followed by a click as well',
      );
    });
  });

  group('state between gestures', () {
    test('a swipe does not leak into the next gesture', () {
      // The accumulated distance and the peak finger count both have to be
      // cleared, or the next single-finger tap inherits a three-finger peak
      // and arrives as a middle click.
      final harness = _Harness();
      for (var i = 1; i <= 3; i++) {
        harness.down(i, Offset(20.0 * i, 50));
      }
      for (var step = 1; step <= 3; step++) {
        for (var i = 1; i <= 3; i++) {
          harness.move(i, Offset(20.0 * i, 50 - step * 20));
        }
      }
      for (var i = 1; i <= 3; i++) {
        harness.up(i);
      }
      harness.sent.clear();

      harness
        ..down(9, const Offset(50, 50))
        ..up(9);

      expect(
        harness.ofType<MouseButtonEvent>().first.button,
        MouseButton.left,
      );
      expect(harness.ofType<GestureSwipe>(), isEmpty);
    });
  });
}
