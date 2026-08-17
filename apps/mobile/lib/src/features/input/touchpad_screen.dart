import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import 'pointer_controller.dart';

/// The main control surface: the whole screen is a trackpad.
///
/// Gesture handling is written against `Listener` rather than `GestureDetector`
/// for a specific reason. `GestureDetector` runs the gesture arena, which
/// delays recognition until competing recognisers have settled — typically one
/// or two frames. On the cursor path that delay is directly visible as lag, and
/// the arena buys nothing here because this widget owns the entire surface and
/// has no competitors. `Listener` delivers raw pointer events immediately, and
/// the multi-touch logic below does the disambiguation itself.
class TouchpadSurfaceView extends ConsumerStatefulWidget {
  const TouchpadSurfaceView({super.key});

  @override
  ConsumerState<TouchpadSurfaceView> createState() =>
      _TouchpadSurfaceViewState();
}

class _TouchpadSurfaceViewState extends ConsumerState<TouchpadSurfaceView> {
  final PointerController _pointer = PointerController();
  final TapRecogniser _taps = TapRecogniser();

  /// Active pointers, keyed by device id, so finger count is always exact.
  final Map<int, Offset> _pointers = <int, Offset>{};

  /// Where the gesture started, for the tap-versus-drag decision.
  Offset? _gestureOrigin;
  double _travelled = 0;

  /// Finger count at its peak during this gesture.
  ///
  /// Tracked as a maximum rather than sampled at lift, because fingers rarely
  /// leave the glass simultaneously — a two-finger tap almost always ends as a
  /// one-finger touch for a few milliseconds, and sampling then would turn
  /// every right-click into a left-click.
  int _peakFingers = 0;

  bool _dragging = false;

  /// Whether the explicit cursor controls are showing.
  ///
  /// `null` means "follow the platform": open when a screen reader is running,
  /// closed otherwise. Once the user touches the toggle their choice sticks,
  /// because someone who opened it deliberately did not want it taken away, and
  /// someone who closed it does not want it back on the next rebuild.
  bool? _showCursorPad;

  /// How far one press of a direction button moves the cursor, in pixels.
  int _cursorStep = _CursorPad.defaultStep;

  // Continuous gesture tracking for scale / zoom and rotation.
  double? _lastSpan;
  double? _lastAngle;
  bool _isZooming = false;
  bool _isRotating = false;
  DateTime _lastZoomTime = DateTime.fromMicrosecondsSinceEpoch(0);
  DateTime _lastRotateTime = DateTime.fromMicrosecondsSinceEpoch(0);

  // Multi-finger swipe tracking.
  double _swipeDeltaX = 0;
  double _swipeDeltaY = 0;
  bool _swipeDispatched = false;

  @override
  void dispose() {
    _taps.reset();
    super.dispose();
  }

  Future<void> _send(Message message) async {
    final client = ref.read(clientProvider).valueOrNull;
    if (client == null) return;
    // Send failures are ignored deliberately: this fires at up to 120 Hz, and
    // during a brief outage the supervisor is already reconnecting. Surfacing
    // an error per frame would be noise, and the coalescing in the session
    // layer means nothing important is lost.
    await client.send(message);
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _peakFingers =
        _pointers.length > _peakFingers ? _pointers.length : _peakFingers;

    if (_pointers.length == 1) {
      _gestureOrigin = event.localPosition;
      _travelled = 0;
    } else if (_pointers.length == 2) {
      final pList = _pointers.values.toList();
      _lastSpan = (pList[0] - pList[1]).distance;
      _lastAngle = math.atan2(
            pList[1].dy - pList[0].dy,
            pList[1].dx - pList[0].dx,
          ) *
          180 /
          math.pi;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _travelled += event.delta.distance;

    final settings = ref.read(pointerSettingsProvider);
    _pointer.settings = settings;

    if (_pointers.length >= 3) {
      // Multi-finger swipe navigation (e.g. Mission Control, Spaces, Task View).
      _swipeDeltaX += event.delta.dx;
      _swipeDeltaY += event.delta.dy;

      if (!_swipeDispatched) {
        if (_swipeDeltaX.abs() > 40 || _swipeDeltaY.abs() > 40) {
          _swipeDispatched = true;
          final isVertical = _swipeDeltaY.abs() > _swipeDeltaX.abs();
          final direction = isVertical
              ? (_swipeDeltaY < 0 ? SwipeDirection.up : SwipeDirection.down)
              : (_swipeDeltaX < 0 ? SwipeDirection.left : SwipeDirection.right);
          unawaitedSend(
            GestureSwipe(
              fingerCount: _peakFingers >= 3 ? _peakFingers : _pointers.length,
              direction: direction,
            ),
          );
          HapticFeedback.mediumImpact();
        }
      }
      return;
    }

    if (_pointers.length == 2) {
      final pList = _pointers.values.toList();
      final currentSpan = (pList[0] - pList[1]).distance;
      final currentAngle = math.atan2(
            pList[1].dy - pList[0].dy,
            pList[1].dx - pList[0].dx,
          ) *
          180 /
          math.pi;

      final capabilities =
          ref.read(clientProvider).valueOrNull?.session?.capabilities;
      final gesturesAvailable =
          capabilities?.has(Capabilities.gestures) ?? false;

      if (gesturesAvailable && _lastSpan != null && _lastSpan! > 0) {
        final spanDelta = (currentSpan - _lastSpan!) / _lastSpan!;
        var angleDelta = currentAngle - (_lastAngle ?? currentAngle);
        while (angleDelta < -180) {
          angleDelta += 360;
        }
        while (angleDelta > 180) {
          angleDelta -= 360;
        }

        // Scale / Zoom gesture detection
        if (_isZooming || (!_isRotating && spanDelta.abs() > 0.03)) {
          final now = DateTime.now();
          if (!_isZooming) {
            _isZooming = true;
            _lastZoomTime = now;
            unawaitedSend(
              GestureZoom(
                magnificationDelta: spanDelta,
                phase: GesturePhase.began,
              ),
            );
          } else if (now.difference(_lastZoomTime).inMicroseconds >= 8333) {
            // Rate limit to at most 120 Hz (~8.33 ms)
            _lastZoomTime = now;
            unawaitedSend(
              GestureZoom(
                magnificationDelta: spanDelta,
                phase: GesturePhase.changed,
              ),
            );
          }
          _lastSpan = currentSpan;
          return;
        }

        // Rotation gesture detection
        if (_isRotating || (!_isZooming && angleDelta.abs() > 3.0)) {
          final now = DateTime.now();
          if (!_isRotating) {
            _isRotating = true;
            _lastRotateTime = now;
            unawaitedSend(
              GestureRotate(
                degreesDelta: angleDelta,
                phase: GesturePhase.began,
              ),
            );
          } else if (now.difference(_lastRotateTime).inMicroseconds >= 8333) {
            // Rate limit to at most 120 Hz
            _lastRotateTime = now;
            unawaitedSend(
              GestureRotate(
                degreesDelta: angleDelta,
                phase: GesturePhase.changed,
              ),
            );
          }
          _lastAngle = currentAngle;
          return;
        }
      }

      // Two fingers scroll. The delta of whichever finger moved is used rather
      // than an average, because averaging halves the reported movement when
      // one finger is stationary — which is exactly how people scroll.
      final scroll = _pointer.translateScroll(event.delta);
      if (scroll.pixelsX == 0 && scroll.pixelsY == 0) return;
      unawaitedSend(
        MouseScroll(
          linesX: scroll.linesX,
          linesY: scroll.linesY,
          pixelsX: scroll.pixelsX,
          pixelsY: scroll.pixelsY,
        ),
      );
      return;
    }

    final delta = _pointer.translatePan(event.delta, event.timeStamp);
    if (delta == null) return;
    unawaitedSend(MouseMove(deltaX: delta.$1, deltaY: delta.$2));
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);

    if (_pointers.length < 2) {
      if (_isZooming) {
        _isZooming = false;
        unawaitedSend(
          const GestureZoom(magnificationDelta: 0, phase: GesturePhase.ended),
        );
      }
      if (_isRotating) {
        _isRotating = false;
        unawaitedSend(
          const GestureRotate(degreesDelta: 0, phase: GesturePhase.ended),
        );
      }
      _lastSpan = null;
      _lastAngle = null;
    }

    if (_pointers.isNotEmpty) return;

    final settings = ref.read(pointerSettingsProvider);
    final wasTap = _taps.isTap(_travelled) && _gestureOrigin != null;

    if (_dragging) {
      _dragging = false;
      unawaitedSend(
        const MouseButtonEvent(button: MouseButton.left, pressed: false),
      );
    } else if (wasTap && settings.tapToClick) {
      // One finger left-clicks, two right-click, three middle-click — the
      // convention on every modern trackpad, so it needs no explanation.
      final button = switch (_peakFingers) {
        1 => MouseButton.left,
        2 => MouseButton.right,
        _ => MouseButton.middle,
      };

      final clickCount =
          button == MouseButton.left ? _taps.registerTap(DateTime.now()) : 1;

      unawaitedSend(
        MouseButtonEvent(button: button, pressed: true, clickCount: clickCount),
      );
      unawaitedSend(
        MouseButtonEvent(
            button: button, pressed: false, clickCount: clickCount),
      );
      HapticFeedback.selectionClick();
    }

    _pointer.endGesture();
    _gestureOrigin = null;
    _travelled = 0;
    _peakFingers = 0;
    _swipeDispatched = false;
    _swipeDeltaX = 0;
    _swipeDeltaY = 0;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);

    if (_pointers.length < 2) {
      if (_isZooming) {
        _isZooming = false;
        unawaitedSend(
          const GestureZoom(
            magnificationDelta: 0,
            phase: GesturePhase.cancelled,
          ),
        );
      }
      if (_isRotating) {
        _isRotating = false;
        unawaitedSend(
          const GestureRotate(
            degreesDelta: 0,
            phase: GesturePhase.cancelled,
          ),
        );
      }
      _lastSpan = null;
      _lastAngle = null;
    }

    if (_pointers.isNotEmpty) return;

    // A cancelled gesture mid-drag must still release the button, or the
    // desktop is left holding it with no way for the user to let go.
    if (_dragging) {
      _dragging = false;
      unawaitedSend(
        const MouseButtonEvent(button: MouseButton.left, pressed: false),
      );
    }
    _pointer.endGesture();
    _peakFingers = 0;
    _swipeDispatched = false;
    _swipeDeltaX = 0;
    _swipeDeltaY = 0;
  }

  /// Long press starts a drag: the button goes down and stays down until lift.
  void _onLongPress() {
    if (_dragging) return;
    _dragging = true;
    unawaitedSend(
      const MouseButtonEvent(button: MouseButton.left, pressed: true),
    );
    HapticFeedback.mediumImpact();
  }

  void unawaitedSend(Message message) => unawaited(_send(message));

  @override
  Widget build(BuildContext context) {
    final connected =
        ref.watch(clientStateProvider).valueOrNull == ClientState.connected;

    // Open by default when a screen reader is running. The gesture surface is
    // unusable then — the reader owns the touch events — so landing on the
    // touchpad tab with no way to move the cursor is landing on a dead screen.
    final showCursorPad =
        _showCursorPad ?? MediaQuery.accessibleNavigationOf(context);

    // No Scaffold or AppBar: this is one tab inside ControlScreen, which owns
    // the chrome. Nesting a second Scaffold would double the status bar inset
    // and give the tab its own disconnected app bar.
    // A LayoutBuilder because the cursor pad has to be given a ceiling: it is
    // laid out at its natural height, and at a large text size that height
    // exceeds the whole screen. Without a bound the Column overflows and the
    // button row is clipped off the bottom.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: <Widget>[
          Expanded(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Touchpad',
              // Stated rather than implied. Without it the surface announces
              // nothing at all, and a gesture area that announces nothing is
              // indistinguishable from empty space.
              hint: connected
                  ? 'Drag to move the pointer. Double tap to click. '
                      'Swipe with three fingers to scroll. '
                      'Directional controls are available below.'
                  : 'Not connected.',
              // Screen-reader equivalents of the gestures this surface is built
              // from. A reader intercepts raw touches, so without these the
              // pointer cannot be moved or clicked from here at all.
              onTap: connected ? () => _click(MouseButton.left) : null,
              onLongPress: connected ? _onLongPress : null,
              onScrollUp: connected ? () => _scroll(0, -_cursorStep) : null,
              onScrollDown: connected ? () => _scroll(0, _cursorStep) : null,
              onScrollLeft: connected ? () => _scroll(-_cursorStep, 0) : null,
              onScrollRight: connected ? () => _scroll(_cursorStep, 0) : null,
              child: Listener(
                // Opaque so the whole area receives events even where nothing is
                // painted.
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: GestureDetector(
                  // Long press is the one gesture worth the arena's latency: it
                  // is defined by *not* moving, so a frame of delay is invisible.
                  onLongPress: _onLongPress,
                  child: _TouchpadSurface(enabled: connected),
                ),
              ),
            ),
          ),
          if (showCursorPad)
            ConstrainedBox(
              // Never more than half the screen: the surface above still has to
              // be usable by anyone driving it by touch, and the pad scrolls
              // inside this rather than pushing the click buttons off-screen.
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: SingleChildScrollView(
                child: _CursorPad(
                  enabled: connected,
                  step: _cursorStep,
                  onStepChanged: (step) => setState(() => _cursorStep = step),
                  onMove: _move,
                  onClick: _click,
                  onScroll: _scroll,
                  onClose: () => setState(() => _showCursorPad = false),
                ),
              ),
            ),
          _ButtonRow(
            onLeft: () => _click(MouseButton.left),
            onMiddle: () => _click(MouseButton.middle),
            onRight: () => _click(MouseButton.right),
            onToggleCursorPad: () =>
                setState(() => _showCursorPad = !showCursorPad),
            cursorPadShowing: showCursorPad,
            enabled: connected,
          ),
        ],
      ),
    );
  }

  void _click(MouseButton button) {
    unawaitedSend(MouseButtonEvent(button: button, pressed: true));
    unawaitedSend(MouseButtonEvent(button: button, pressed: false));
    HapticFeedback.selectionClick();
  }

  /// Moves the cursor by a fixed amount, bypassing the gesture path entirely.
  ///
  /// Deliberately does not go through [PointerController]: its acceleration
  /// curve and sub-pixel accumulator both exist to make a *finger* feel right,
  /// and applied to a button press they would make the same button move a
  /// different distance depending on how fast it was tapped. A discrete control
  /// has to move a predictable distance or it cannot be aimed.
  void _move(int dx, int dy) {
    unawaitedSend(MouseMove(deltaX: dx, deltaY: dy));
    HapticFeedback.selectionClick();
  }

  void _scroll(int dx, int dy) {
    unawaitedSend(
      MouseScroll(
        // 40 px to the line, the same conversion the gesture path uses.
        linesX: (dx / 40).round(),
        linesY: (dy / 40).round(),
        pixelsX: dx,
        pixelsY: dy,
      ),
    );
    HapticFeedback.selectionClick();
  }
}

class _TouchpadSurface extends StatelessWidget {
  const _TouchpadSurface({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: context.motion(const Duration(milliseconds: 200)),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        // Absorbs overflow rather than scrolling. With the pointer controls
        // open at a large text size the surface is squeezed to a couple of
        // hundred pixels and the watermark plus three lines of hint no longer
        // fit; this lets the content be laid out unbounded and clipped instead
        // of throwing.
        //
        // `NeverScrollableScrollPhysics` matters and is not belt-and-braces: a
        // scrollable here would enter the gesture arena for vertical drags on
        // the one surface in the app whose entire job is vertical drags. The
        // hint is duplicated in this surface's semantics hint, so nothing is
        // lost by clipping it.
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: enabled
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // A watermark, not information: everything it suggests is
                    // spelled out in the text below and in the surface's
                    // semantics. Excluded so a reader does not announce "touch
                    // app" between the label and the instructions, and left dim
                    // on purpose — as pure decoration it is outside the contrast
                    // requirement, and it sits behind the pointer.
                    ExcludeSemantics(
                      child: Icon(
                        Icons.touch_app_outlined,
                        size: 44,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Drag to move · Tap to click\n'
                      'Two fingers to scroll or right-click\n'
                      'Hold to drag',
                      textAlign: TextAlign.center,
                      // Full-strength `onSurfaceVariant`. This was drawn at 60%
                      // alpha — roughly 2.6:1 on the surface behind it — and it
                      // is the only instruction on the screen.
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                )
              : Text(
                  'Not connected',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
        ),
      ),
    );
  }
}

/// Explicit controls that drive the cursor without a gesture.
///
/// ## Why this exists
///
/// The surface above is a bare gesture area. With a screen reader running, the
/// reader owns the touch events — a drag becomes an exploration gesture, a tap
/// becomes a focus move — so the cursor cannot be moved at all. The touchpad,
/// which is the whole product, was unusable without sight.
///
/// These buttons are not a nicer touchpad and are not meant to be. They move
/// the pointer a fixed distance per press, which is slow and deliberate, and
/// that is the point: the target is that the cursor *can* be driven, by anyone,
/// with controls a screen reader can find, name, and activate.
///
/// The step sizes are what make it usable rather than merely possible. A 1440p
/// display is 180 presses wide at the fine step; coarse crosses it in twelve
/// and fine then lands on the button. Without a step control this would be a
/// technically-accessible feature nobody could actually use.
class _CursorPad extends StatelessWidget {
  const _CursorPad({
    required this.enabled,
    required this.step,
    required this.onStepChanged,
    required this.onMove,
    required this.onClick,
    required this.onScroll,
    required this.onClose,
  });

  /// Pixels per press at each setting, and what to call them out loud.
  static const List<(int, String)> steps = <(int, String)>[
    (10, 'Fine'),
    (40, 'Normal'),
    (160, 'Coarse'),
  ];

  static const int defaultStep = 40;

  final bool enabled;
  final int step;
  final ValueChanged<int> onStepChanged;
  final void Function(int dx, int dy) onMove;
  final void Function(MouseButton button) onClick;
  final void Function(int dx, int dy) onScroll;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepName = steps
        .firstWhere((entry) => entry.$1 == step, orElse: () => steps[1])
        .$2
        .toLowerCase();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Pointer controls',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                tooltip: 'Hide pointer controls',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
          // Step size first: it changes what every button below does, so it is
          // announced before them rather than after.
          Semantics(
            container: true,
            label: 'Step size, currently $stepName',
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: <ButtonSegment<int>>[
                for (final (pixels, name) in steps)
                  ButtonSegment<int>(
                    value: pixels,
                    label: Text(name),
                    tooltip: '$name — $pixels pixels per press',
                  ),
              ],
              selected: <int>{step},
              onSelectionChanged:
                  enabled ? (set) => onStepChanged(set.first) : null,
            ),
          ),
          const SizedBox(height: 8),
          // A cross, laid out as one sees it, so "up" is above "down" to a
          // reader exploring by touch as well as by swipe order.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _CursorButton(
                icon: Icons.keyboard_arrow_left,
                label: 'Move pointer left $step pixels',
                onPressed: enabled ? () => onMove(-step, 0) : null,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _CursorButton(
                    icon: Icons.keyboard_arrow_up,
                    label: 'Move pointer up $step pixels',
                    onPressed: enabled ? () => onMove(0, -step) : null,
                  ),
                  _CursorButton(
                    icon: Icons.keyboard_arrow_down,
                    label: 'Move pointer down $step pixels',
                    onPressed: enabled ? () => onMove(0, step) : null,
                  ),
                ],
              ),
              _CursorButton(
                icon: Icons.keyboard_arrow_right,
                label: 'Move pointer right $step pixels',
                onPressed: enabled ? () => onMove(step, 0) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _CursorButton(
                icon: Icons.mouse_outlined,
                label: 'Left click',
                onPressed: enabled ? () => onClick(MouseButton.left) : null,
              ),
              _CursorButton(
                icon: Icons.menu_open,
                label: 'Right click',
                onPressed: enabled ? () => onClick(MouseButton.right) : null,
              ),
              _CursorButton(
                icon: Icons.expand_less,
                label: 'Scroll up',
                onPressed: enabled ? () => onScroll(0, -step) : null,
              ),
              _CursorButton(
                icon: Icons.expand_more,
                label: 'Scroll down',
                onPressed: enabled ? () => onScroll(0, step) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One labelled control on the cursor pad.
///
/// `tooltip` rather than a wrapping `Semantics`: on an [IconButton] the tooltip
/// *is* the semantic label, so the two cannot drift apart, and a sighted user
/// discovers the same wording a screen reader announces.
class _CursorButton extends StatelessWidget {
  const _CursorButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        tooltip: label,
        icon: Icon(icon),
        onPressed: onPressed,
      );
}

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({
    required this.onLeft,
    required this.onMiddle,
    required this.onRight,
    required this.onToggleCursorPad,
    required this.cursorPadShowing,
    required this.enabled,
  });

  final VoidCallback onLeft;
  final VoidCallback onMiddle;
  final VoidCallback onRight;
  final VoidCallback onToggleCursorPad;
  final bool cursorPadShowing;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: ConstrainedBox(
          // Large targets on purpose: this is used one-handed, often without
          // looking at the phone because the user is watching the computer.
          //
          // A minimum rather than a fixed height, because at a large text size
          // a fixed 72 clipped the labels — the buttons stayed put and the
          // words inside them lost their descenders.
          constraints: BoxConstraints(
            minHeight: 72 * textScaleFactorOf(context).clamp(1.0, 2.0),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: _PadButton(
                  label: 'Left',
                  // "Left" alone is a direction, not an action. Each of these
                  // announced a word that could equally have meant "move
                  // left" — on a screen whose whole job is moving left.
                  semanticLabel: 'Left click',
                  onPressed: enabled ? onLeft : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                // Two, not one. At flex 1 against two flex-3 neighbours this
                // came out about 42pt wide on a 393pt phone, and a tonal
                // button spends roughly half of that on its own horizontal
                // padding — so "Mid" was laid out in a column one letter tall
                // and three letters high. Still the narrow one, because it is
                // the least-used of the three and the other two are what a
                // thumb reaches for without looking.
                flex: 2,
                child: _PadButton(
                  label: 'Mid',
                  semanticLabel: 'Middle click',
                  onPressed: enabled ? onMiddle : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _PadButton(
                  label: 'Right',
                  semanticLabel: 'Right click',
                  onPressed: enabled ? onRight : null,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: cursorPadShowing
                    ? 'Hide pointer controls'
                    : 'Show pointer controls',
                icon: Icon(
                  cursorPadShowing ? Icons.gamepad : Icons.gamepad_outlined,
                ),
                onPressed: onToggleCursorPad,
              ),
            ],
          ),
        ),
      );
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;

  /// What the button is announced as, where the visible label is too terse to
  /// stand on its own.
  final String semanticLabel;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          // The default horizontal padding is most of the width of the
          // narrowest button here, which leaves the label less room than the
          // label needs. The tap target is unaffected — it is the whole
          // button, and the row's minHeight is what keeps it thumb-sized.
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        // `semanticsLabel` replaces the announced string without touching what
        // is drawn, which is exactly the split wanted here: the button stays
        // narrow, and it stops announcing a bare direction.
        //
        // `maxLines: 1` and no soft wrap because the failure to avoid is not
        // an overflow warning but a silent one: a three-letter word in a
        // too-narrow box wraps *per character* and still fits its parent, so
        // nothing throws and nothing is clipped. It just becomes unreadable.
        // Ellipsis is the honest end state if a translation ever makes the
        // label genuinely too long for the space.
        child: Text(
          label,
          semanticsLabel: semanticLabel,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      );
}
