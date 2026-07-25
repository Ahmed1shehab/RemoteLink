import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import 'pointer_controller.dart';

/// User-tunable pointer behaviour.
final pointerSettingsProvider = StateProvider<PointerSettings>(
  (ref) => const PointerSettings(),
);

/// The main control surface: the whole screen is a trackpad.
///
/// Gesture handling is written against `Listener` rather than `GestureDetector`
/// for a specific reason. `GestureDetector` runs the gesture arena, which
/// delays recognition until competing recognisers have settled — typically one
/// or two frames. On the cursor path that delay is directly visible as lag, and
/// the arena buys nothing here because this widget owns the entire surface and
/// has no competitors. `Listener` delivers raw pointer events immediately, and
/// the multi-touch logic below does the disambiguation itself.
class TouchpadScreen extends ConsumerStatefulWidget {
  const TouchpadScreen({super.key});

  @override
  ConsumerState<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends ConsumerState<TouchpadScreen> {
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
    _peakFingers = _pointers.length > _peakFingers
        ? _pointers.length
        : _peakFingers;

    if (_pointers.length == 1) {
      _gestureOrigin = event.localPosition;
      _travelled = 0;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _travelled += event.delta.distance;

    final settings = ref.read(pointerSettingsProvider);
    _pointer.settings = settings;

    if (_pointers.length >= 2) {
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
        MouseButtonEvent(button: button, pressed: false, clickCount: clickCount),
      );
      HapticFeedback.selectionClick();
    }

    _pointer.endGesture();
    _gestureOrigin = null;
    _travelled = 0;
    _peakFingers = 0;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
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
    final state = ref.watch(clientStateProvider).valueOrNull;
    final connected = state == ClientState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Touchpad'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _ConnectionBar(state: state),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
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
          _ButtonRow(
            onLeft: () => _click(MouseButton.left),
            onMiddle: () => _click(MouseButton.middle),
            onRight: () => _click(MouseButton.right),
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
}

class _TouchpadSurface extends StatelessWidget {
  const _TouchpadSurface({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: enabled
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.touch_app_outlined,
                    size: 44,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Drag to move · Tap to click\n'
                    'Two fingers to scroll or right-click\n'
                    'Hold to drag',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                  ),
                ],
              )
            : Text(
                'Not connected',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
      ),
    );
  }
}

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({
    required this.onLeft,
    required this.onMiddle,
    required this.onRight,
    required this.enabled,
  });

  final VoidCallback onLeft;
  final VoidCallback onMiddle;
  final VoidCallback onRight;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: SizedBox(
          // Large targets on purpose: this is used one-handed, often without
          // looking at the phone because the user is watching the computer.
          height: 72,
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: _PadButton(
                  label: 'Left',
                  onPressed: enabled ? onLeft : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PadButton(
                  label: 'Mid',
                  onPressed: enabled ? onMiddle : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _PadButton(
                  label: 'Right',
                  onPressed: enabled ? onRight : null,
                ),
              ),
            ],
          ),
        ),
      );
}

class _PadButton extends StatelessWidget {
  const _PadButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label),
      );
}

/// A thin line that turns amber while reconnecting.
///
/// Deliberately unobtrusive. Reconnection is expected and usually over in under
/// a second, so a dialog or a snackbar would draw far more attention than the
/// event deserves — the user should notice only if it persists.
class _ConnectionBar extends StatelessWidget {
  const _ConnectionBar({required this.state});

  final ClientState? state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, animate) = switch (state) {
      ClientState.connected => (scheme.primary, false),
      ClientState.reconnecting || ClientState.connecting => (
          scheme.tertiary,
          true,
        ),
      ClientState.failed => (scheme.error, false),
      _ => (scheme.surfaceContainerHighest, false),
    };

    return SizedBox(
      height: 2,
      child: animate
          ? LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: scheme.surfaceContainerHighest,
              color: color,
            )
          : ColoredBox(color: color, child: const SizedBox.expand()),
    );
  }
}
