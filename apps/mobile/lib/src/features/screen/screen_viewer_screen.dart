import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import '../input/pointer_controller.dart';
import 'remote_cursor.dart';
import 'screen_frame_sink.dart';
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

/// Where the desk's pointer is, on its own stream.
///
/// Separate from [screenFrameProvider] because that is the whole point of
/// `ScreenCursor`. The pointer used to arrive on the frame, which meant it
/// could only move as often as a couple of hundred kilobytes of picture could
/// cross the link — five to ten times a second on real Wi-Fi, and the one
/// thing on screen the user is certain to be watching was the jerkiest.
///
/// A frame's own cursor fields are still read, as a fallback: a desktop built
/// before `ScreenCursor` sends nothing here, and a viewer that ignored the
/// frame would show it no pointer at all. A current desktop sends both, and the
/// dedicated message simply arrives far more often.
final screenCursorProvider = StreamProvider.autoDispose<Offset?>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  yield null;
  await for (final message in client.messages) {
    final update = screenCursorUpdate(message);
    if (update != null) yield update.position;
  }
});

/// What [message] says about where the desk's pointer is.
///
/// Three answers, not two, which is why this returns a record rather than an
/// `Offset?`: `null` means the message says nothing about the pointer, while a
/// record carrying a null [position] means the pointer has left the display and
/// the arrow must stop being drawn. Collapsing those two would either freeze a
/// departed cursor against an edge or blank a live one on every unrelated
/// message.
///
/// A function rather than logic inside the provider so it can be tested against
/// real messages. A widget test that overrides the provider proves the overlay
/// draws what it is handed and nothing about what produces it.
@visibleForTesting
({Offset? position})? screenCursorUpdate(Message message) {
  if (message is ScreenCursor) {
    final x = message.x;
    final y = message.y;
    return (position: x == null || y == null ? null : Offset(x, y));
  }
  // The fallback for a desktop built before `ScreenCursor` existed, which
  // reports the pointer only on the frame. A current desktop sends both; the
  // dedicated message simply arrives far more often, so this rarely decides
  // anything. Absence here is *not* treated as the pointer leaving — an older
  // desktop omits these fields whenever it cannot read the pointer, and
  // blanking the arrow on that would make it flicker.
  if (message is ScreenFrame) {
    final x = message.cursorX;
    final y = message.cursorY;
    if (x != null && y != null) return (position: Offset(x, y));
  }
  return null;
}

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
    final cursor = ref.watch(screenCursorProvider).valueOrNull;
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
                cursor: cursor,
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
                cursor: cursor,
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
/// Stateful because a video stream has to own its decoding. Given the frame
/// rather than reading it from a provider, so the whole of the touch-to-message
/// path can be exercised without a session behind it.
class _ControllableFrame extends StatefulWidget {
  const _ControllableFrame({
    required this.frame,
    required this.cursor,
    required this.canSendInput,
    required this.onSend,
    required this.pointerSettings,
    required this.gesturesAvailable,
  });

  final ScreenFrame frame;

  /// The desk's pointer, from its own stream. Null when it has left this
  /// display, or before the first report.
  final Offset? cursor;

  final bool canSendInput;
  final void Function(Message) onSend;

  /// The user's own pointer preferences, so moving and scrolling here behave
  /// the way they do on the touchpad — natural scrolling in particular, which
  /// is backwards from the wrong setting and immediately obvious.
  final PointerSettings pointerSettings;

  /// Whether the desk takes part in pinch and rotate. Passed rather than read
  /// here so the one place that inspects capabilities stays the one place.
  final bool gesturesAvailable;

  @override
  State<_ControllableFrame> createState() => _ControllableFrameState();
}

class _ControllableFrameState extends State<_ControllableFrame> {
  StreamedViewGestures? _gestures;

  late final ScreenFrameSink _sink = ScreenFrameSink(onImage: _onImage);

  /// The frame currently on screen. Owned here, and disposed here.
  ui.Image? _image;

  /// The bytes last handed to the decoder, so a rebuild that changes something
  /// else — the permission tier, a settings change — does not re-decode a
  /// picture that is already drawn.
  Uint8List? _submitted;

  /// The size of the widget the picture was last laid out in.
  ///
  /// Held as state because the cursor overlay is positioned against the drawn
  /// rectangle, and under `BoxFit.contain` that is not the widget's rectangle
  /// but the letterboxed one inside it.
  Size _containerSize = Size.zero;

  /// The size of the picture actually on screen.
  ///
  /// Taken from the decoded image rather than from the newest frame: while a
  /// decode is in flight those disagree, and the cursor must be placed against
  /// what the user is looking at.
  Size get _imageSize {
    final image = _image;
    if (image == null) {
      return Size(
        widget.frame.width.toDouble(),
        widget.frame.height.toDouble(),
      );
    }
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  @override
  void initState() {
    super.initState();
    _submitted = widget.frame.data;
    _sink.submit(widget.frame.data);
  }

  @override
  void didUpdateWidget(covariant _ControllableFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    final data = widget.frame.data;
    if (identical(data, _submitted)) return;
    _submitted = data;
    _sink.submit(data);
  }

  void _onImage(ui.Image image) {
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
    });
  }

  @override
  void dispose() {
    _sink.dispose();
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  StreamedViewGestures _recogniser(PointerSettings settings) =>
      _gestures ??= StreamedViewGestures(
        send: widget.onSend,
        gesturesAvailable: widget.gesturesAvailable,
        settings: settings,
      );

  @override
  Widget build(BuildContext context) {
    final image = _image;
    // A black rectangle until the first frame is decoded, rather than nothing:
    // the parent has already committed to filling the screen, and an empty
    // slot there flashes white for one frame on a black background.
    final picture = image == null
        ? const ColoredBox(color: Colors.black)
        // A clone, not the image itself. `RenderImage` takes ownership of what
        // it is given and disposes it when replaced, so handing it this state's
        // own handle would mean two owners and a double dispose. It recognises
        // a clone of what it already holds and drops the duplicate, so a
        // rebuild that changes nothing costs nothing.
        : RawImage(
            image: image.clone(),
            fit: BoxFit.contain,
            // Low, explicitly. This is a picture being scaled down and replaced
            // thirty times a second; the better filters build mipmaps per
            // image, which is work thrown away before it is ever reused.
            filterQuality: FilterQuality.low,
          );

    // Without the tier for input this is a picture, and deliberately just a
    // picture — no listener, so nothing is sent that the desktop would refuse
    // without saying so. The cursor still gets drawn: watching where someone
    // else is pointing is the whole value of a view-only stream.
    if (!widget.canSendInput) return _withCursor(picture);

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
                picture,
                RemoteCursor(
                  normalised: widget.cursor,
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

  /// Overlays the desk's pointer on [picture].
  ///
  /// Its own [LayoutBuilder] because the cursor's position depends on where the
  /// picture was actually drawn, and under `BoxFit.contain` that is not the
  /// widget's own rectangle — it is the letterboxed rectangle inside it.
  Widget _withCursor(Widget picture) => LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            picture,
            RemoteCursor(
              normalised: widget.cursor,
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
