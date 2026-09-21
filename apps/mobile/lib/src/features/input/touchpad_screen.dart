import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
// `show` rather than a bare import: `dart:ui` also declares Offset, Size and
// Color, and importing it whole shadows the ones material re-exports.
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/app_icons.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../settings/settings_screen.dart';
import 'pointer_controller.dart';
import 'sensitivity_tutorial_dialog.dart';

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
  const TouchpadSurfaceView({this.immersive = false, super.key});

  /// Whether the surface has the screen to itself.
  ///
  /// Set by [ControlScreen] when the user expands the gesture area: the tab
  /// bar and the host status strip are gone, so the box can run closer to the
  /// edges and the click row can shed the padding it needed to clear the
  /// floating navigation.
  final bool immersive;

  @override
  ConsumerState<TouchpadSurfaceView> createState() =>
      _TouchpadSurfaceViewState();
}

class _TouchpadSurfaceViewState extends ConsumerState<TouchpadSurfaceView>
    with SingleTickerProviderStateMixin {
  final PointerController _pointer = PointerController();
  final TapRecogniser _taps = TapRecogniser();

  late final _TouchGlowController _glowController;
  late final AnimationController _fadeController;

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

  /// Whether the surface is showing what its gestures do.
  ///
  /// Visible until the first touch, then gone: the instructions are for the
  /// first session, and after that they are three lines of text under the
  /// user's thumb. They come back after [_hintDelay] of stillness, which is
  /// long enough not to flicker between gestures and short enough that picking
  /// the phone up later finds them again. The same words are in this surface's
  /// semantics hint the whole time, so nothing is lost while they are hidden.
  bool _hintVisible = true;
  Timer? _hintTimer;

  static const Duration _hintDelay = Duration(seconds: 6);

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

  /// The distance and angle between the two fingers when they went down.
  ///
  /// Measured against the start of the gesture rather than the previous frame,
  /// because a frame-to-frame comparison cannot tell a pinch from the ordinary
  /// wobble of two fingers dragging together: at 120 Hz the span between them
  /// changes by a percent or two constantly, which is enough to trip any
  /// per-frame threshold small enough to catch a real pinch early.
  double? _spanAtStart;
  double? _angleAtStart;

  /// How far the fingers have travelled since the pair went down.
  ///
  /// A pinch is recognised only when the change in span beats this, which is
  /// what separates "the fingers moved apart" from "the fingers moved across
  /// the glass and drifted slightly apart on the way".
  double _twoFingerTravel = 0;

  /// Latched once the pair is scrolling, so span wobble cannot convert a
  /// scroll that is already underway into a zoom halfway down the page.
  bool _isTwoFingerScrolling = false;

  bool _isZooming = false;
  bool _isRotating = false;
  DateTime _lastZoomTime = DateTime.fromMicrosecondsSinceEpoch(0);
  DateTime _lastRotateTime = DateTime.fromMicrosecondsSinceEpoch(0);

  // Multi-finger swipe tracking.
  double _swipeDeltaX = 0;
  double _swipeDeltaY = 0;
  bool _swipeDispatched = false;

  @override
  void initState() {
    super.initState();
    _glowController = _TouchGlowController();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _glowController.attachAnimationController(_fadeController);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _taps.reset();
    _fadeController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  /// Hides the hint for the duration of a gesture.
  void _hideHint() {
    _hintTimer?.cancel();
    if (_hintVisible) setState(() => _hintVisible = false);
  }

  /// Starts the countdown that brings the hint back once the glass is quiet.
  void _restoreHintLater() {
    _hintTimer?.cancel();
    _hintTimer = Timer(_hintDelay, () {
      if (mounted) setState(() => _hintVisible = true);
    });
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
    _glowController.onPointerDown(event.pointer, event.localPosition);
    _hideHint();
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
      _spanAtStart = _lastSpan;
      _angleAtStart = _lastAngle;
      _twoFingerTravel = 0;
      _isTwoFingerScrolling = false;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _travelled += event.delta.distance;
    _glowController.onPointerMove(event.pointer, event.localPosition);

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

      final previousSpan = _lastSpan ?? currentSpan;
      final previousAngle = _lastAngle ?? currentAngle;
      // Updated on every frame, including the frames that scroll. Leaving them
      // behind on the scroll path was the bug this arbitration replaces: the
      // span kept being compared against the touch-down measurement, so the
      // slow drift of a long two-finger drag eventually crossed the pinch
      // threshold and the rest of the gesture became a zoom nobody asked for.
      _lastSpan = currentSpan;
      _lastAngle = currentAngle;
      _twoFingerTravel += event.delta.distance;

      final capabilities =
          ref.read(clientProvider).valueOrNull?.session?.capabilities;
      final gesturesAvailable =
          capabilities?.has(Capabilities.gestures) ?? false;

      // Measured from the start of the gesture, so the test is "have the
      // fingers ended up further apart" rather than "did they jitter".
      final spanChange = currentSpan - (_spanAtStart ?? currentSpan);
      var angleChange = currentAngle - (_angleAtStart ?? currentAngle);
      while (angleChange < -180) {
        angleChange += 360;
      }
      while (angleChange > 180) {
        angleChange -= 360;
      }

      // How far apart the fingers must end up before this counts as a pinch,
      // and how much of the total movement that has to be. A scroll drags both
      // fingers the same way, so its span barely changes however far it goes; a
      // pinch is nearly all span change.
      const pinchDistance = 24.0;
      const pinchShare = 0.5;
      const rotationDegrees = 12.0;
      // Enough movement to be sure the pair is dragging rather than settling.
      const scrollStart = 6.0;

      final pinching = gesturesAvailable &&
          !_isRotating &&
          !_isTwoFingerScrolling &&
          spanChange.abs() > pinchDistance &&
          spanChange.abs() > _twoFingerTravel * pinchShare;

      if (_isZooming || pinching) {
        final now = DateTime.now();
        final spanDelta = previousSpan > 0
            ? (currentSpan - previousSpan) / previousSpan
            : 0.0;
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
        return;
      }

      final rotating = gesturesAvailable &&
          !_isZooming &&
          !_isTwoFingerScrolling &&
          angleChange.abs() > rotationDegrees &&
          spanChange.abs() <= pinchDistance;

      if (_isRotating || rotating) {
        final now = DateTime.now();
        var degreesDelta = currentAngle - previousAngle;
        while (degreesDelta < -180) {
          degreesDelta += 360;
        }
        while (degreesDelta > 180) {
          degreesDelta -= 360;
        }
        if (!_isRotating) {
          _isRotating = true;
          _lastRotateTime = now;
          unawaitedSend(
            GestureRotate(
              degreesDelta: degreesDelta,
              phase: GesturePhase.began,
            ),
          );
        } else if (now.difference(_lastRotateTime).inMicroseconds >= 8333) {
          // Rate limit to at most 120 Hz
          _lastRotateTime = now;
          unawaitedSend(
            GestureRotate(
              degreesDelta: degreesDelta,
              phase: GesturePhase.changed,
            ),
          );
        }
        return;
      }

      if (_twoFingerTravel > scrollStart) _isTwoFingerScrolling = true;

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
    _glowController.onPointerUp(event.pointer);
    if (_pointers.isEmpty) _restoreHintLater();

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
      _spanAtStart = null;
      _angleAtStart = null;
      _twoFingerTravel = 0;
      _isTwoFingerScrolling = false;
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
    _glowController.onPointerCancel(event.pointer);
    if (_pointers.isEmpty) _restoreHintLater();

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
      _spanAtStart = null;
      _angleAtStart = null;
      _twoFingerTravel = 0;
      _isTwoFingerScrolling = false;
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
    _glowController.fadeDuration =
        context.motion(const Duration(milliseconds: 180));
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
              // The inset lives out here rather than inside the surface, so
              // the box the finger touches is exactly the box that is drawn.
              // With the margin inside, a pointer landing in the gap reported
              // a position the painter had no dot at, and the glow sat a
              // centimetre from the thumb.
              child: Padding(
                padding: EdgeInsets.all(widget.immersive ? 6 : 10),
                child: Listener(
                  // Opaque so the whole area receives events even where nothing
                  // is painted.
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: GestureDetector(
                    // Long press is the one gesture worth the arena's latency:
                    // it is defined by *not* moving, so a frame of delay is
                    // invisible.
                    onLongPress: _onLongPress,
                    child: _TouchpadSurface(
                      enabled: connected,
                      showHint: _hintVisible,
                      glowController: _glowController,
                      showTutorialBanner:
                          !ref.watch(sensitivityTutorialSeenProvider),
                      onOpenSettings: () {
                        ref
                            .read(sensitivityTutorialSeenProvider.notifier)
                            .markSeen();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      onOpenTutorial: () =>
                          SensitivityTutorialDialog.show(context, ref),
                      onDismissTutorial: () => ref
                          .read(sensitivityTutorialSeenProvider.notifier)
                          .markSeen(),
                    ),
                  ),
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
            immersive: widget.immersive,
            onLeft: () => _click(MouseButton.left),
            onMiddle: () => _click(MouseButton.middle),
            onRight: () => _click(MouseButton.right),
            onToggleCursorPad: () =>
                setState(() => _showCursorPad = !showCursorPad),
            onShowSensitivityTutorial: () =>
                SensitivityTutorialDialog.show(context, ref),
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

/// The glass itself: a dot field that lights up under the finger.
///
/// The dots are not decoration for its own sake. A blank rectangle gives a
/// finger nothing to judge movement against, and the one question this surface
/// has to answer instantly — "did it register that?" — was previously answered
/// only by the cursor moving on a screen across the room. The lattice gives the
/// eye a fixed frame, and the glow that follows the touch answers the question
/// on the phone, where the thumb already is.
class _TouchpadSurface extends StatelessWidget {
  const _TouchpadSurface({
    required this.enabled,
    required this.showHint,
    required this.glowController,
    this.showTutorialBanner = false,
    this.onOpenSettings,
    this.onOpenTutorial,
    this.onDismissTutorial,
  });

  final bool enabled;

  final bool showHint;

  final _TouchGlowController glowController;

  final bool showTutorialBanner;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenTutorial;
  final VoidCallback? onDismissTutorial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final duration = context.motion(const Duration(milliseconds: 200));

    return AnimatedContainer(
      duration: duration,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // A gradient rather than a flat fill, top lighter than bottom. It is
        // the cheapest way to make a surface this large read as a physical
        // panel rather than a hole in the page, and at these amplitudes it is
        // well under the threshold where a gradient starts banding.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: enabled
              ? <Color>[
                  dark
                      ? scheme.surfaceContainerHigh
                      : scheme.surfaceContainerHighest,
                  dark
                      ? scheme.surfaceContainerLowest
                      : scheme.surfaceContainer,
                ]
              : <Color>[
                  scheme.surfaceContainerLow,
                  scheme.surfaceContainerLowest,
                ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (enabled) ...<Widget>[
            // The resting lattice: drawn once into a display list and cached in
            // its own layer so it never repaints during touch gestures.
            RepaintBoundary(
              child: CustomPaint(
                // Expensive to build and never changes, which is exactly the
                // shape the raster cache exists for: told so explicitly, it is
                // rasterised once and reused for the life of the screen.
                isComplex: true,
                willChange: false,
                painter: _DotFieldPainter(
                  ink: scheme.onSurfaceVariant
                      .withValues(alpha: dark ? 0.18 : 0.30),
                ),
              ),
            ),
            // The dynamic touch-reactive field: only repaints its own isolated
            // layer within the bounding box of active pointers, swelling and
            // brightening dots in real time with zero widget rebuilds and zero
            // latency impact on pointer dispatch.
            RepaintBoundary(
              child: CustomPaint(
                // The opposite case, and worth saying out loud: this changes
                // every frame a finger is down, so the raster cache must not
                // spend a frame trying to cache it.
                willChange: true,
                painter: _DynamicDotGlowPainter(
                  controller: glowController,
                  dotColor: const Color(0xFF007ACC),
                ),
              ),
            ),
          ],
          Center(
            // Absorbs overflow rather than scrolling. With the pointer controls
            // open at a large text size the surface is squeezed to a couple of
            // hundred pixels and the watermark plus three lines of hint no
            // longer fit; this lets the content be laid out unbounded and
            // clipped instead of throwing.
            //
            // `NeverScrollableScrollPhysics` matters and is not
            // belt-and-braces: a scrollable here would enter the gesture arena
            // for vertical drags on the one surface in the app whose entire job
            // is vertical drags. The hint is duplicated in this surface's
            // semantics hint, so nothing is lost by clipping it.
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: enabled
                  ? IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: showHint ? 1 : 0,
                        duration: duration,
                        curve: Curves.easeOut,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            // A watermark, not information: everything it
                            // suggests is spelled out in the text below and in
                            // the surface's semantics. Excluded so a reader does
                            // not announce "touch app" between the label and the
                            // instructions, and left dim on purpose — as pure
                            // decoration it is outside the contrast requirement,
                            // and it sits behind the pointer.
                            ExcludeSemantics(
                              child: AppIcon(
                                AppIcons.handTap,
                                size: 44,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Drag to move · Tap to click\n'
                              'Two fingers to scroll or right-click\n'
                              'Hold to drag\n\n'
                              'Adjust sensitivity anytime in Settings',
                              textAlign: TextAlign.center,
                              // Full-strength `onSurfaceVariant`. This was drawn
                              // at 60% alpha — roughly 2.6:1 on the surface
                              // behind it — and it is the only instruction on
                              // the screen.
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Text(
                      'Not connected',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
            ),
          ),
          if (enabled && showTutorialBanner)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _SensitivityHintBanner(
                onOpenSettings: onOpenSettings ?? () {},
                onOpenTutorial: onOpenTutorial ?? () {},
                onDismiss: onDismissTutorial ?? () {},
              ),
            ),
        ],
      ),
    );
  }
}

/// Floating hint banner informing users about pointer sensitivity settings.
class _SensitivityHintBanner extends StatelessWidget {
  const _SensitivityHintBanner({
    required this.onOpenSettings,
    required this.onOpenTutorial,
    required this.onDismiss,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenTutorial;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: (dark ? colorScheme.surfaceContainerHigh : Colors.white)
              .withValues(alpha: dark ? 0.92 : 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF007ACC).withValues(alpha: 0.5),
            width: 1.2,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF007ACC).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.speed_rounded,
                color: Color(0xFF007ACC),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpenTutorial,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Pointer Sensitivity',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Tap for tutorial or adjust in Settings',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: const Color(0xFF007ACC),
              ),
              onPressed: onOpenSettings,
              child: const Text('Adjust'),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.close),
              tooltip: 'Dismiss hint',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// The dot lattice's geometry, worked out once per size.
///
/// Cached, and that is the whole point of the class. The first version built a
/// fresh five-hundred-element list of offsets inside `paint`, which is called on
/// every pointer move — up to 120 times a second, on the one code path in this
/// app whose latency a user can feel directly. The allocation alone was enough
/// to make the cursor lag behind the finger, and because [PointerController]
/// derives its acceleration from event timestamps, dropped frames also made the
/// pointer read as *slow*: fewer, later events look like slower movement to the
/// curve. Geometry that depends only on the box size has no business being
/// recomputed per frame.
@immutable
final class _Lattice {
  const _Lattice._({
    required this.originX,
    required this.originY,
    required this.columns,
    required this.rows,
  });

  final double originX;
  final double originY;
  final int columns;
  final int rows;

  /// Distance between dot centres, in logical pixels rather than a fraction of
  /// the box — so the dots stay the same distance apart whether the surface is
  /// a third of the screen or all of it, which is the point of a reference grid.
  static const double spacing = 22;

  static Size? _cachedSize;
  static _Lattice? _cached;

  /// The lattice for a surface of [size], or null if it is too small to hold a
  /// single dot. Centred, so the margins match on both sides at any width.
  static _Lattice? of(Size size) {
    if (_cachedSize == size) return _cached;
    final columns = (size.width / spacing).floor();
    final rows = (size.height / spacing).floor();
    _cachedSize = size;
    _cached = columns < 1 || rows < 1
        ? null
        : _Lattice._(
            originX: (size.width - (columns - 1) * spacing) / 2,
            originY: (size.height - (rows - 1) * spacing) / 2,
            columns: columns,
            rows: rows,
          );
    return _cached;
  }

  Offset dotAt(int column, int row) =>
      Offset(originX + column * spacing, originY + row * spacing);

  /// Every dot, for the layer that draws all of them.
  List<Offset> get all => <Offset>[
        for (var row = 0; row < rows; row++)
          for (var column = 0; column < columns; column++) dotAt(column, row),
      ];
}

/// The resting lattice.
class _DotFieldPainter extends CustomPainter {
  _DotFieldPainter({required this.ink})
      : _paint = Paint()
          ..color = ink
          ..strokeWidth = _dotRadius * 2
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;

  static const double _dotRadius = 1.5;

  /// The dots, already faded.
  ///
  /// Passed in rather than hard-coded, and that is not fastidiousness: the
  /// first version painted white at a low alpha, which is invisible on the
  /// light theme's paper — the whole field simply vanished. The colour has to
  /// come from the scheme, because the ink that reads on one page is the ink
  /// that disappears on the other.
  final Color ink;

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final lattice = _Lattice.of(size);
    if (lattice == null) return;

    // `drawPoints` with a round cap draws the whole field in one call, which
    // matters at five hundred dots: five hundred `drawCircle`s is five hundred
    // draw ops in the display list, and this layer is rasterised on the frame
    // the tab first appears — the frame the user is watching for.
    canvas.drawPoints(PointMode.points, lattice.all, _paint);
  }

  @override
  bool shouldRepaint(_DotFieldPainter oldDelegate) => oldDelegate.ink != ink;
}

/// Tracks active touch points on the touchpad to render the dynamic proximity
/// glow and dot swelling without triggering any widget tree rebuilds.
final class _TouchGlowController extends ChangeNotifier {
  final Map<int, Offset> _activeTouches = <int, Offset>{};
  List<Offset> _cachedFadingTouches = const <Offset>[];
  double _fade = 0.0;
  AnimationController? _fadeController;
  Duration fadeDuration = const Duration(milliseconds: 180);

  void attachAnimationController(AnimationController controller) {
    _fadeController = controller;
    _fadeController!.addListener(_onFadeTick);
  }

  void _onFadeTick() {
    if (_fadeController == null) return;
    _fade = _fadeController!.value;
    if (_fade <= 0.001) {
      _cachedFadingTouches = const <Offset>[];
    }
    notifyListeners();
  }

  void onPointerDown(int pointer, Offset position) {
    _activeTouches[pointer] = position;
    if (_fadeController?.isAnimating ?? false) {
      _fadeController!.stop();
    }
    _fade = 1.0;
    _cachedFadingTouches = const <Offset>[];
    notifyListeners();
  }

  void onPointerMove(int pointer, Offset position) {
    _activeTouches[pointer] = position;
    _fade = 1.0;
    notifyListeners();
  }

  void onPointerUp(int pointer) {
    if (_activeTouches.length == 1 && _activeTouches.containsKey(pointer)) {
      _cachedFadingTouches = _activeTouches.values.toList(growable: false);
    }
    _activeTouches.remove(pointer);
    if (_activeTouches.isEmpty) {
      if (fadeDuration == Duration.zero) {
        _fade = 0.0;
        _cachedFadingTouches = const <Offset>[];
        notifyListeners();
      } else if (_fadeController != null) {
        _fadeController!.duration = fadeDuration;
        _fadeController!.reverse(from: _fade);
      } else {
        _fade = 0.0;
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  void onPointerCancel(int pointer) {
    onPointerUp(pointer);
  }

  Iterable<Offset> get activePoints =>
      _activeTouches.isNotEmpty ? _activeTouches.values : _cachedFadingTouches;

  double get fade => _fade;

  bool get hasActiveTouches => _activeTouches.isNotEmpty;

  @override
  void dispose() {
    _fadeController?.removeListener(_onFadeTick);
    super.dispose();
  }
}

/// Renders the touch-reactive glow and swelling dots around active pointers.
///
/// Only repaints when [_TouchGlowController] notifies, and stays completely
/// inside a [RepaintBoundary] so neither the resting dot field nor any widget
/// rebuilds during cursor motion.
///
/// ## Why the falloff is quantised
///
/// The glow is a smooth gradient and the eye reads it as one, but a canvas does
/// not: a distinct radius and colour per dot is a distinct draw op per dot, and
/// the box one finger lights up holds around four hundred of them. Four hundred
/// `drawCircle`s, each preceded by a freshly allocated `Color`, were being built
/// into the display list on the UI thread of every frame of every drag — the
/// same thread that has to dispatch the pointer events this surface exists to
/// turn into cursor movement. When it runs late, the events arrive late, and the
/// cursor lags the finger for a reason that has nothing to do with the network.
///
/// So the falloff is cut into [_levels] steps. Every dot in a step shares one
/// radius and one colour, which makes it one `drawRawPoints` call over a reused
/// buffer: twelve ops a frame instead of four hundred, and no allocation in the
/// loop at all. Twelve steps across six pixels of swell puts each step under
/// half a pixel, which the dots' own anti-aliasing covers.
final class _DynamicDotGlowPainter extends CustomPainter {
  _DynamicDotGlowPainter({
    required this.controller,
    required this.dotColor,
  }) : super(repaint: controller);

  final _TouchGlowController controller;
  final Color dotColor;

  static const double _baseRadius = 1.5;
  static const double _maxRadius = 7.5;
  static const double _glowRadius = 220.0;
  static const double _glowRadiusSq = _glowRadius * _glowRadius;

  /// How many discrete sizes the falloff is drawn in.
  static const int _levels = 12;

  /// One paint per step, built once and re-coloured each frame.
  ///
  /// `PointMode.points` draws a square per point unless the cap is round, which
  /// is what makes a dot a dot here, and is why the resting field is drawn the
  /// same way.
  final List<Paint> _paints = List<Paint>.generate(
    _levels,
    (_) => Paint()
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true,
    growable: false,
  );

  /// Dot coordinates per step, reused between frames. Grown, never shrunk: the
  /// surface does not change size while a finger is on it.
  final List<Float32List> _coordinates = <Float32List>[];
  final Int32List _counts = Int32List(_levels);

  void _ensureCapacity(int dots) {
    if (_coordinates.isNotEmpty && _coordinates.first.length >= dots * 2) {
      return;
    }
    _coordinates
      ..clear()
      ..addAll(
        List<Float32List>.generate(_levels, (_) => Float32List(dots * 2)),
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fade = controller.fade;
    if (fade <= 0.001) return;

    final touches = controller.activePoints;
    if (touches.isEmpty) return;

    final lattice = _Lattice.of(size);
    if (lattice == null) return;

    // 1. Determine the bounding box of columns and rows affected by any touch.
    int minCol = lattice.columns;
    int maxCol = -1;
    int minRow = lattice.rows;
    int maxRow = -1;

    for (final p in touches) {
      final c0 = (((p.dx - _glowRadius) - lattice.originX) / _Lattice.spacing)
          .floor()
          .clamp(0, lattice.columns - 1);
      final c1 = (((p.dx + _glowRadius) - lattice.originX) / _Lattice.spacing)
          .ceil()
          .clamp(0, lattice.columns - 1);
      final r0 = (((p.dy - _glowRadius) - lattice.originY) / _Lattice.spacing)
          .floor()
          .clamp(0, lattice.rows - 1);
      final r1 = (((p.dy + _glowRadius) - lattice.originY) / _Lattice.spacing)
          .ceil()
          .clamp(0, lattice.rows - 1);

      if (c0 < minCol) minCol = c0;
      if (c1 > maxCol) maxCol = c1;
      if (r0 < minRow) minRow = r0;
      if (r1 > maxRow) maxRow = r1;
    }

    if (maxCol < minCol || maxRow < minRow) return;

    _counts.fillRange(0, _levels, 0);
    _ensureCapacity((maxCol - minCol + 1) * (maxRow - minRow + 1));

    // 2. Sort every lit dot into the step its brightness falls in.
    for (var r = minRow; r <= maxRow; r++) {
      final dotY = lattice.originY + r * _Lattice.spacing;
      for (var c = minCol; c <= maxCol; c++) {
        final dotX = lattice.originX + c * _Lattice.spacing;

        // Nearest touch wins, so two fingers brighten a dot between them to
        // whichever is closer rather than to their sum.
        double maxT = 0;
        for (final p in touches) {
          final dx = dotX - p.dx;
          final dy = dotY - p.dy;
          final distSq = dx * dx + dy * dy;
          if (distSq >= _glowRadiusSq) continue;
          final t = 1.0 - math.sqrt(distSq) / _glowRadius;
          if (t > maxT) maxT = t;
        }
        if (maxT <= 0.001) continue;

        // Smoothstep, for a falloff that reads as light rather than as a cone.
        final curve = maxT * maxT * (3.0 - 2.0 * maxT);
        var level = (curve * _levels).floor();
        if (level >= _levels) level = _levels - 1;

        final count = _counts[level];
        _coordinates[level][count * 2] = dotX;
        _coordinates[level][count * 2 + 1] = dotY;
        _counts[level] = count + 1;
      }
    }

    // 3. One call per step.
    for (var level = 0; level < _levels; level++) {
      final count = _counts[level];
      if (count == 0) continue;

      // The middle of the step's band rather than its floor, so quantising
      // does not systematically dim the whole field by half a step.
      final curve = (level + 0.5) / _levels;
      final paint = _paints[level]
        ..strokeWidth = 2 * (_baseRadius + (_maxRadius - _baseRadius) * curve)
        ..color = dotColor.withValues(
          alpha: (0.95 * curve * fade).clamp(0.0, 1.0),
        );

      canvas.drawRawPoints(
        PointMode.points,
        Float32List.sublistView(_coordinates[level], 0, count * 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DynamicDotGlowPainter oldDelegate) =>
      oldDelegate.dotColor != dotColor || oldDelegate.controller != controller;
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
    required this.immersive,
    required this.onLeft,
    required this.onMiddle,
    required this.onRight,
    required this.onToggleCursorPad,
    required this.onShowSensitivityTutorial,
    required this.cursorPadShowing,
    required this.enabled,
  });

  /// Whether the tab bar is out of the way.
  ///
  /// The bottom padding exists to clear the floating navigation. With the
  /// navigation gone it is dead space between the buttons and the home
  /// indicator, and this row sits directly under the surface it belongs to —
  /// so it is given back to the gesture box above.
  final bool immersive;

  final VoidCallback onLeft;
  final VoidCallback onMiddle;
  final VoidCallback onRight;
  final VoidCallback onToggleCursorPad;
  final VoidCallback onShowSensitivityTutorial;
  final bool cursorPadShowing;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, immersive ? 6 : 16),
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
                tooltip: 'Pointer sensitivity tutorial',
                icon: const Icon(Icons.tune_outlined),
                onPressed: onShowSensitivityTutorial,
              ),
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
