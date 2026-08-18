import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../input/pointer_controller.dart';

/// How far a multi-finger swipe must travel before it is dispatched.
///
/// Matches the touchpad. Below this a three-finger rest with a little wobble
/// would fire a Mission Control swipe the user never asked for.
const double kSwipeThreshold = 40;

/// Turns touches on the streamed picture into protocol messages.
///
/// The same vocabulary as the touchpad — one finger points, two scroll, two
/// tap for a right click, three for middle, three or four swipe, long-press
/// drags — because a second, different set of rules for the same hardware is a
/// thing to memorise for no reason. Pinch and rotate come along too, gated on
/// the desk advertising [Capabilities.gestures] exactly as the touchpad gates
/// them.
///
/// A single finger moves the pointer *relatively*, exactly as on the touchpad.
/// The obvious alternative — treat the picture as a touchscreen and put the
/// pointer wherever the finger lands — was tried and is worse in practice. A
/// finger is several millimetres wide and hides what it is aiming at, so on a
/// desk scaled down to fit a phone one finger-width covers a whole row of menu
/// items: you can see roughly where you are going and never land on it. Moving
/// the pointer instead means the fine positioning is done by the *pointer*,
/// which is a few pixels wide and drawn on top of the picture rather than under
/// a thumb, and the finger only has to supply direction. It also makes the far
/// corner of a 4K desk reachable by swiping repeatedly, rather than requiring a
/// touch inside a two-pixel target.
///
/// Everything else is unchanged.
///
/// Separate from the widget, and free of Flutter's widget layer, because this is
/// where the behaviour actually lives — which finger count means which button,
/// when a move stops being a tap, whether a drag is still held. All of that is
/// testable as a list of events in and a list of messages out, and none of it is
/// testable by pumping a widget and hoping.
final class StreamedViewGestures {
  StreamedViewGestures({
    required this.send,
    required PointerSettings settings,
    this.gesturesAvailable = false,
  })  : _settings = settings,
        _pointer = PointerController(settings: settings);

  /// Where a message goes. Never awaited by this class — see the viewer's
  /// `_unawaitedSend` for why a pointer stream must not queue on round trips.
  final void Function(Message) send;

  final bool gesturesAvailable;

  PointerSettings _settings;
  set settings(PointerSettings value) {
    _settings = value;
    _pointer.settings = value;
  }

  final PointerController _pointer;
  final TapRecogniser _taps = TapRecogniser();

  final Map<int, Offset> _pointers = <int, Offset>{};

  /// Most fingers seen at once during this gesture.
  ///
  /// The count at lift is useless: fingers never leave the glass together, so a
  /// two-finger tap is a one-finger tap by the time the last one goes up. The
  /// peak is what the user actually did.
  int _peakFingers = 0;

  double _travelled = 0;
  bool _dragging = false;

  double _swipeDeltaX = 0;
  double _swipeDeltaY = 0;
  bool _swipeDispatched = false;

  double? _lastSpan;
  double? _lastAngle;
  bool _isZooming = false;
  bool _isRotating = false;

  /// Whether a drag is currently held, so the viewer can show it.
  bool get isDragging => _dragging;

  void onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _peakFingers = math.max(_peakFingers, _pointers.length);

    if (_pointers.length == 1) {
      _travelled = 0;
      // Nothing is sent yet. The pointer is already somewhere, and a tap acts
      // where it is — putting a finger down is not itself a movement.
    } else if (_pointers.length == 2) {
      _lastSpan = _spanBetweenPointers();
      _lastAngle = _angleBetweenPointers();
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _travelled += event.delta.distance;

    if (_pointers.length >= 3) {
      _accumulateSwipe(event.delta);
      return;
    }

    if (_pointers.length == 2) {
      if (_handlePinchOrRotate()) return;
      _scroll(event.delta);
      return;
    }

    _move(event);
  }

  void onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _endPinchAndRotate(GesturePhase.ended);
    if (_pointers.isNotEmpty) return;

    if (_dragging) {
      _dragging = false;
      send(const MouseButtonEvent(button: MouseButton.left, pressed: false));
    } else if (_settings.tapToClick && _taps.isTap(_travelled)) {
      _click();
    }

    _reset();
  }

  void onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _endPinchAndRotate(GesturePhase.cancelled);
    if (_pointers.isNotEmpty) return;

    // A cancelled gesture mid-drag must still release the button, or the desk
    // is left holding it down with nothing on the phone able to let go.
    if (_dragging) {
      _dragging = false;
      send(const MouseButtonEvent(button: MouseButton.left, pressed: false));
    }

    _reset();
  }

  /// Long press holds the left button so the next movement drags.
  ///
  /// This is how a window gets moved: press on its title bar, then drag. It is
  /// also how text is selected and how anything is dropped somewhere else.
  void onLongPress() {
    if (_dragging || _pointers.length != 1) return;
    _dragging = true;
    send(const MouseButtonEvent(button: MouseButton.left, pressed: true));
  }

  void _click() {
    // One finger left, two right, three middle — the convention on every
    // modern trackpad, and the same one the touchpad screen uses.
    final button = switch (_peakFingers) {
      1 => MouseButton.left,
      2 => MouseButton.right,
      _ => MouseButton.middle,
    };

    // Counted here rather than on the desk: network jitter can stretch two
    // taps past any OS double-click threshold, and the phone saw the real
    // timing.
    final clickCount =
        button == MouseButton.left ? _taps.registerTap(DateTime.now()) : 1;

    send(
      MouseButtonEvent(button: button, pressed: true, clickCount: clickCount),
    );
    send(
      MouseButtonEvent(button: button, pressed: false, clickCount: clickCount),
    );
  }

  void _move(PointerMoveEvent event) {
    // Through the same controller the touchpad uses, so the user's sensitivity
    // and acceleration settings mean one thing across the app, and so the
    // sub-pixel remainder is carried between events rather than truncated away
    // — dropping a 0.4-pixel fraction sixty times a second is movement the
    // finger made and the pointer did not.
    final delta = _pointer.translatePan(event.delta, event.timeStamp);
    if (delta == null) return;
    send(MouseMove(deltaX: delta.$1, deltaY: delta.$2));
  }

  void _scroll(Offset delta) {
    final scroll = _pointer.translateScroll(delta);
    if (scroll.pixelsX == 0 && scroll.pixelsY == 0) return;
    send(
      MouseScroll(
        linesX: scroll.linesX,
        linesY: scroll.linesY,
        pixelsX: scroll.pixelsX,
        pixelsY: scroll.pixelsY,
      ),
    );
  }

  void _accumulateSwipe(Offset delta) {
    _swipeDeltaX += delta.dx;
    _swipeDeltaY += delta.dy;
    if (_swipeDispatched) return;
    if (_swipeDeltaX.abs() <= kSwipeThreshold &&
        _swipeDeltaY.abs() <= kSwipeThreshold) {
      return;
    }

    _swipeDispatched = true;
    final isVertical = _swipeDeltaY.abs() > _swipeDeltaX.abs();
    send(
      GestureSwipe(
        // The peak, so a four-finger swipe stays a four-finger swipe even
        // though the fingers never land at the same instant. On macOS the
        // count is the whole meaning: three switches windows, four switches
        // desktops.
        fingerCount: math.max(_peakFingers, _pointers.length),
        direction: isVertical
            ? (_swipeDeltaY < 0 ? SwipeDirection.up : SwipeDirection.down)
            : (_swipeDeltaX < 0 ? SwipeDirection.left : SwipeDirection.right),
      ),
    );
  }

  /// Returns true when the two fingers are pinching or rotating rather than
  /// scrolling.
  bool _handlePinchOrRotate() {
    if (!gesturesAvailable) return false;
    final lastSpan = _lastSpan;
    if (lastSpan == null || lastSpan <= 0) return false;

    final currentSpan = _spanBetweenPointers();
    final currentAngle = _angleBetweenPointers();
    if (currentSpan == null || currentAngle == null) return false;

    final spanDelta = (currentSpan - lastSpan) / lastSpan;
    var angleDelta = currentAngle - (_lastAngle ?? currentAngle);
    while (angleDelta < -180) {
      angleDelta += 360;
    }
    while (angleDelta > 180) {
      angleDelta -= 360;
    }

    // Once a gesture has committed to zooming it stays zooming until the
    // fingers lift. Re-deciding every frame makes a pinch flicker between zoom
    // and rotate whenever the fingers wobble.
    if (_isZooming || (!_isRotating && spanDelta.abs() > 0.03)) {
      send(
        GestureZoom(
          magnificationDelta: spanDelta,
          phase: _isZooming ? GesturePhase.changed : GesturePhase.began,
        ),
      );
      _isZooming = true;
      _lastSpan = currentSpan;
      return true;
    }

    if (_isRotating || (!_isZooming && angleDelta.abs() > 3.0)) {
      send(
        GestureRotate(
          degreesDelta: angleDelta,
          phase: _isRotating ? GesturePhase.changed : GesturePhase.began,
        ),
      );
      _isRotating = true;
      _lastAngle = currentAngle;
      return true;
    }

    return false;
  }

  void _endPinchAndRotate(GesturePhase phase) {
    if (_isZooming) {
      _isZooming = false;
      send(GestureZoom(magnificationDelta: 0, phase: phase));
    }
    if (_isRotating) {
      _isRotating = false;
      send(GestureRotate(degreesDelta: 0, phase: phase));
    }
    _lastSpan = null;
    _lastAngle = null;
  }

  double? _spanBetweenPointers() {
    if (_pointers.length < 2) return null;
    final points = _pointers.values.toList();
    return (points[0] - points[1]).distance;
  }

  double? _angleBetweenPointers() {
    if (_pointers.length < 2) return null;
    final points = _pointers.values.toList();
    return math.atan2(
          points[1].dy - points[0].dy,
          points[1].dx - points[0].dx,
        ) *
        180 /
        math.pi;
  }

  void _reset() {
    _pointer.endGesture();
    _travelled = 0;
    _peakFingers = 0;
    _swipeDispatched = false;
    _swipeDeltaX = 0;
    _swipeDeltaY = 0;
  }
}
