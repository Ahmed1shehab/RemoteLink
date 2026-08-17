import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import '../input/pointer_controller.dart';
import 'remote_cursor.dart';
import 'screen_coordinate_mapping.dart';
import 'screen_stream_request.dart';
import 'streamed_view_gestures.dart';

/// Screen frames pushed from the desktop.
final screenFrameProvider =
    StreamProvider.autoDispose<ScreenFrame?>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  yield null;
  await for (final message in client.messages) {
    if (message is ScreenFrame) yield message;
  }
});

/// Live screen viewer screen showing desktop frames and controls.
class ScreenViewerScreen extends ConsumerStatefulWidget {
  const ScreenViewerScreen({
    super.key,
    this.monitorId = kWholeVirtualDesktopMonitorId,
  });

  /// Which display is being watched, and therefore which one a tap addresses.
  ///
  /// Carried through to `MouseMoveAbsolute` rather than left at zero: zero
  /// means the whole virtual desktop, so on a two-monitor desk every tap on
  /// the picture of one screen would be resolved against the bounding box of
  /// both.
  final int monitorId;

  @override
  ConsumerState<ScreenViewerScreen> createState() => _ScreenViewerScreenState();
}

class _ScreenViewerScreenState extends ConsumerState<ScreenViewerScreen> {
  RemoteLinkClient? _client;
  bool _isStreaming = true;

  @override
  void initState() {
    super.initState();
    // The rest of this app is portrait-locked. A desk is a landscape
    // rectangle, so a portrait phone spends most of its screen on bars —
    // turning it sideways is the difference between a thumbnail and something
    // you can work in.
    unawaited(
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startStream();
    });
  }

  /// Sends without awaiting, for the input path.
  ///
  /// Pointer events arrive faster than a round trip and must never queue
  /// behind one another: awaiting here would turn a fast drag into a backlog
  /// of stale positions arriving after the finger has stopped moving.
  void _unawaitedSend(Message message) {
    final client = _client ?? ref.read(clientProvider).valueOrNull;
    if (client == null || !client.isConnected) return;
    unawaited(client.send(message));
  }

  Future<void> _startStream() async {
    final client = ref.read(clientProvider).valueOrNull;
    if (client == null || !client.isConnected) return;
    _client = client;
    final capabilities = client.session?.capabilities;
    if (capabilities == null || !capabilities.has(Capabilities.screenCapture)) {
      return;
    }

    setState(() => _isStreaming = true);
    await client.send(
      screenStreamRequestFor(
        monitorId: widget.monitorId,
        logicalSize: MediaQuery.sizeOf(context),
      ),
    );
  }

  Future<void> _stopStream({bool pop = false}) async {
    final client = _client ?? ref.read(clientProvider).valueOrNull;
    if (client != null && client.isConnected) {
      await client.send(
        const ScreenStreamStop(reason: ScreenStopReason.userClosed),
      );
    }
    if (mounted) {
      setState(() => _isStreaming = false);
      if (pop) {
        await Navigator.of(context).maybePop();
      }
    }
  }

  @override
  void dispose() {
    if (_isStreaming && _client != null && _client!.isConnected) {
      unawaited(
        _client!.send(
          const ScreenStreamStop(reason: ScreenStopReason.userClosed),
        ),
      );
    }
    // Put the lock back. Leaving it open means the *next* screen the user
    // opens can rotate, which reads as a bug on a screen that has nothing to
    // do with streaming and gives no hint where it came from.
    unawaited(
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        ref.watch(clientStateProvider).valueOrNull == ClientState.connected;
    final capabilities =
        ref.watch(clientProvider).valueOrNull?.session?.capabilities;
    final supported = capabilities?.has(Capabilities.screenCapture) ?? false;

    if (!connected || !supported) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Screen Stream'),
        ),
        body: const _UnsupportedScreenViewer(),
      );
    }

    final frameAsync = ref.watch(screenFrameProvider);
    final frame = frameAsync.valueOrNull;
    final canSendInput =
        ref.watch(currentPermissionTierProvider).valueOrNull?.canSendInput ??
            false;
    final pointerSettings = ref.watch(pointerSettingsProvider);
    final gesturesAvailable = capabilities?.has(Capabilities.gestures) ?? false;

    // Landscape gives the frame everything: no app bar, no floating button,
    // no padding. The controls are not deleted, they move into a compact
    // overlay — the stop button in particular must never become unreachable,
    // because it is the only way to end a stream from this side.
    //
    // No auto-hide timer. One was tried and it is a live `Timer` sitting in
    // the widget tree, which is a hazard in a test and buys very little: the
    // overlay is a small translucent strip in a corner, not a bar across the
    // picture.
    if (MediaQuery.orientationOf(context) == Orientation.landscape) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (frame != null)
              _ControllableFrame(
                frame: frame,
                monitorId: widget.monitorId,
                canSendInput: canSendInput,
                onSend: _unawaitedSend,
                pointerSettings: pointerSettings,
                gesturesAvailable: gesturesAvailable,
              )
            else
              const Center(
                child: Text(
                  'Waiting for screen frames…',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (frame != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '${frame.width}×${frame.height}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.stop_circle_outlined,
                              color: Colors.white),
                          tooltip: 'Stop Streaming',
                          onPressed: () => _stopStream(pop: true),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Screen Stream'),
        actions: <Widget>[
          if (frame != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  '${frame.width}×${frame.height}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(_isStreaming
                ? Icons.stop_circle_outlined
                : Icons.play_circle_outlined),
            tooltip: _isStreaming ? 'Stop Streaming' : 'Start Streaming',
            onPressed: () {
              if (_isStreaming) {
                _stopStream();
              } else {
                _startStream();
              }
            },
          ),
        ],
      ),
      body: Center(
        child: frame != null
            ? _ControllableFrame(
                frame: frame,
                monitorId: widget.monitorId,
                // Input is a separate grant from watching, and the desktop
                // refuses out-of-tier messages in silence by design. Passing
                // the answer down rather than letting the frame widget guess
                // keeps the one place that decides in one place.
                canSendInput: canSendInput,
                onSend: _unawaitedSend,
                pointerSettings: pointerSettings,
                gesturesAvailable: gesturesAvailable,
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ExcludeSemantics(
                    child: Icon(
                      Icons.screen_share_outlined,
                      size: 48,
                      color: Colors.white54,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Waiting for screen frames...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
      ),
      floatingActionButton: _isStreaming
          ? FloatingActionButton.extended(
              onPressed: () => _stopStream(pop: true),
              icon: const Icon(Icons.stop),
              label: const Text('Stop Sharing'),
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            )
          : FloatingActionButton.extended(
              onPressed: _startStream,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Stream'),
            ),
    );
  }
}

/// The streamed picture, with touches on it driving the desk's pointer.
///
/// Stateless apart from the gesture bookkeeping, and given the frame rather
/// than reading it from a provider, so the whole of the touch-to-coordinate
/// path can be exercised without a session behind it.
class _ControllableFrame extends StatefulWidget {
  const _ControllableFrame({
    required this.frame,
    required this.monitorId,
    required this.canSendInput,
    required this.onSend,
    required this.pointerSettings,
    required this.gesturesAvailable,
  });

  final ScreenFrame frame;
  final int monitorId;
  final bool canSendInput;
  final void Function(Message) onSend;

  /// The user's own pointer preferences, so scrolling here behaves the way it
  /// does on the touchpad — natural scrolling in particular, which is
  /// backwards from the wrong setting and immediately obvious.
  final PointerSettings pointerSettings;

  /// Whether the desk takes part in pinch and rotate. Passed rather than read
  /// here so the one place that inspects capabilities stays the one place.
  final bool gesturesAvailable;

  @override
  State<_ControllableFrame> createState() => _ControllableFrameState();
}

class _ControllableFrameState extends State<_ControllableFrame> {
  StreamedViewGestures? _gestures;

  /// The size of the widget the picture was last laid out in.
  ///
  /// Held as state because the gesture recogniser maps a touch against the
  /// drawn rectangle, and the drawn rectangle depends on both the frame and
  /// the widget. Recomputing it per event from a stale value is how a pointer
  /// ends up correct in portrait and wrong the instant the phone turns.
  Size _containerSize = Size.zero;

  Size get _imageSize => Size(
        widget.frame.width.toDouble(),
        widget.frame.height.toDouble(),
      );

  /// The desk's pointer position, if this frame reported one.
  Offset? get _cursor {
    final x = widget.frame.cursorX;
    final y = widget.frame.cursorY;
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  StreamedViewGestures _recogniser(PointerSettings settings) =>
      _gestures ??= StreamedViewGestures(
        send: widget.onSend,
        monitorId: widget.monitorId,
        gesturesAvailable: widget.gesturesAvailable,
        settings: settings,
        // A closure over the *current* size and frame rather than values
        // captured once: both change while the gesture recogniser lives, and a
        // recogniser holding the size it was built with aims at the picture as
        // it used to be.
        toNormalised: (local) => mapTouchToNormalisedCoordinates(
          touchPosition: local,
          containerSize: _containerSize,
          imageSize: _imageSize,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final image = Image.memory(
      widget.frame.data,
      gaplessPlayback: true,
      fit: BoxFit.contain,
    );

    // Without the tier for input this is a picture, and deliberately just a
    // picture — no listener, so nothing is sent that the desktop would refuse
    // without saying so. The cursor still gets drawn: watching where someone
    // else is pointing is the whole value of a view-only stream.
    if (!widget.canSendInput) return _withCursor(image);

    final gestures = _recogniser(widget.pointerSettings)
      ..settings = widget.pointerSettings;

    return LayoutBuilder(
      builder: (context, constraints) {
        _containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          // Long press is the only thing here that needs a recogniser rather
          // than raw pointers, because it is the only one defined by time
          // standing still rather than by movement.
          onLongPress: gestures.onLongPress,
          behavior: HitTestBehavior.opaque,
          child: Listener(
            // Keyed so a test can assert its absence. `findsNothing` on the
            // bare type is meaningless — Flutter's own scaffolding is full of
            // Listeners, and the assertion would pass whatever this widget did.
            key: const ValueKey<String>('screen-viewer-pointer-surface'),
            onPointerDown: gestures.onPointerDown,
            onPointerMove: gestures.onPointerMove,
            onPointerUp: gestures.onPointerUp,
            onPointerCancel: gestures.onPointerCancel,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                image,
                RemoteCursor(
                  normalised: _cursor,
                  containerSize: _containerSize,
                  imageSize: _imageSize,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Overlays the desk's pointer on [image].
  ///
  /// Its own [LayoutBuilder] because the cursor's position depends on where the
  /// picture was actually drawn, and under `BoxFit.contain` that is not the
  /// widget's own rectangle — it is the letterboxed rectangle inside it.
  Widget _withCursor(Widget image) => LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            image,
            RemoteCursor(
              normalised: _cursor,
              containerSize: Size(constraints.maxWidth, constraints.maxHeight),
              imageSize: _imageSize,
            ),
          ],
        ),
      );
}

class _UnsupportedScreenViewer extends StatelessWidget {
  const _UnsupportedScreenViewer();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ExcludeSemantics(
                child: Icon(Icons.screen_share_outlined, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                'Screen sharing isn’t available',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'This computer cannot share its screen. Screen capture is '
                'supported on macOS when Screen Recording permission is granted.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}
