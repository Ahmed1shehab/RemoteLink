import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import '../input/pointer_controller.dart';

/// Intents from the Apple Watch, one event per gesture the wrist made.
///
/// The iOS half is `ios/Runner/WatchBridge.swift`; the watch half is the
/// `RemoteLinkWatch` target. Nothing on Android publishes this channel, and
/// nothing needs to — there is no Wear OS app.
const EventChannel kWatchCommandChannel =
    EventChannel('com.remotelink.app/watch_commands');

/// The channel this side talks back on: the state of the computer link, so the
/// watch can name what it is driving, and questions about the watch itself.
const MethodChannel kWatchChannel = MethodChannel('com.remotelink.app/watch');

/// Whether an Apple Watch is paired, has the app, and is in range.
///
/// Every field can be false on a perfectly healthy phone, so Settings reports
/// them separately rather than as one "watch: no". "Paired but the app is not
/// installed" and "installed but out of range" send the user to different
/// places.
@immutable
final class WatchAvailability {
  const WatchAvailability({
    this.supported = false,
    this.paired = false,
    this.installed = false,
    this.reachable = false,
  });

  /// False on Android, and on an iPhone too old for WatchConnectivity.
  final bool supported;
  final bool paired;
  final bool installed;
  final bool reachable;

  factory WatchAvailability.fromPlatform(Map<Object?, Object?> raw) =>
      WatchAvailability(
        supported: raw['supported'] as bool? ?? false,
        paired: raw['paired'] as bool? ?? false,
        installed: raw['installed'] as bool? ?? false,
        reachable: raw['reachable'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchAvailability &&
          other.supported == supported &&
          other.paired == paired &&
          other.installed == installed &&
          other.reachable == reachable;

  @override
  int get hashCode => Object.hash(supported, paired, installed, reachable);
}

/// Turns one message from the watch into the protocol messages it means.
///
/// Pure Dart, holding only the sub-pixel residual, and deliberately separate
/// from the channel: the mapping from "the wrist moved this far" to "the cursor
/// moves this many pixels" is the part worth testing, and it does not need a
/// platform to exercise.
///
/// The pointer *acceleration* curve is not applied here, and that is a
/// decision rather than an omission. The watch batches movement at 30 Hz before
/// sending it, so every delta that arrives looks like a fast one to a curve
/// that judges speed by delta size — the cursor would leap on the gentlest
/// drag. The user's linear sensitivity is applied; the curve is left to the
/// path it was tuned for, which is a finger on the phone's own glass.
final class WatchCommandTranslator {
  WatchCommandTranslator({required this.settings});

  PointerSettings settings;

  double _residualX = 0;
  double _residualY = 0;

  /// The protocol messages [raw] means, in the order they must be sent.
  ///
  /// An unrecognised command yields nothing rather than throwing. The watch and
  /// the phone are updated independently by the App Store, so a watch running a
  /// newer build will send verbs this one has never heard of, and the right
  /// response to that is silence rather than a crash on the user's wrist.
  List<Message> translate(Map<Object?, Object?> raw) {
    switch (raw['t']) {
      case 'move':
        // Movement and any clicks that happened alongside it, in one message.
        // The watch batches them together because a click sent on its own costs
        // a second round trip over Bluetooth and can arrive before the drag
        // that aimed it — see `WatchLink.pump`.
        final messages = _move(
          (raw['dx'] as num?)?.toDouble() ?? 0,
          (raw['dy'] as num?)?.toDouble() ?? 0,
        );
        // A press-and-hold, if the wrist started or ended one. Before the
        // clicks below, because a hold is what a click during a hold happens
        // inside of.
        switch ((raw['button'] as num?)?.toInt() ?? 0) {
          case 1:
            messages.add(
              const MouseButtonEvent(button: MouseButton.left, pressed: true),
            );
          case 2:
            messages.add(
              const MouseButtonEvent(button: MouseButton.left, pressed: false),
            );
        }

        final clicks = (raw['clicks'] as num?)?.toInt() ?? 0;
        // How many clicks this counts *as*, which is not how many arrived.
        // A double click is one gesture the computer must be told is a double —
        // macOS opens a file on `clickCount: 2` and does nothing at all for two
        // separate clicks of one, however close together they land.
        final clickCount = (raw['clickCount'] as num?)?.toInt() ?? 1;
        for (var i = 0; i < clicks; i++) {
          messages.addAll(<Message>[
            MouseButtonEvent(
              button: MouseButton.left,
              pressed: true,
              clickCount: clickCount,
            ),
            MouseButtonEvent(
              button: MouseButton.left,
              pressed: false,
              clickCount: clickCount,
            ),
          ]);
        }
        return messages;
      case 'click':
        final button = _button(raw['b']);
        return <Message>[
          MouseButtonEvent(button: button, pressed: true),
          MouseButtonEvent(button: button, pressed: false),
        ];
      case 'button':
        return <Message>[
          MouseButtonEvent(
            button: _button(raw['b']),
            pressed: raw['down'] as bool? ?? false,
          ),
        ];
      case 'scroll':
        return _scroll((raw['dy'] as num?)?.toDouble() ?? 0);
      default:
        return const <Message>[];
    }
  }

  List<Message> _move(double dx, double dy) {
    // The residual is what makes slow movement work at all. A gentle drag
    // produces deltas well under a pixel once scaled; rounding each one
    // independently rounds them all to zero, and the cursor does not move until
    // the user gives up and swipes.
    final scaledX = dx * settings.sensitivity + _residualX;
    final scaledY = dy * settings.sensitivity + _residualY;
    final stepX = scaledX.truncate();
    final stepY = scaledY.truncate();
    _residualX = scaledX - stepX;
    _residualY = scaledY - stepY;

    // Growable, and returned even when empty: the caller appends any clicks
    // that travelled with this movement, and a `const []` cannot be added to.
    if (stepX == 0 && stepY == 0) return <Message>[];
    return <Message>[MouseMove(deltaX: stepX, deltaY: stepY)];
  }

  List<Message> _scroll(double lines) {
    // The crown reports lines, so this is the one place the conversion runs the
    // other way round from the touch path: lines are what the user turned, and
    // pixels are derived at the same 40-to-the-line the rest of the app uses.
    final direction = settings.naturalScrolling ? 1 : -1;
    final scaled = lines * settings.scrollSensitivity * direction;
    final steps = scaled.round();
    if (steps == 0) return const <Message>[];
    return <Message>[
      MouseScroll(linesY: steps, pixelsY: steps * 40, linesX: 0, pixelsX: 0),
    ];
  }

  static MouseButton _button(Object? name) => switch (name) {
        'right' => MouseButton.right,
        'middle' => MouseButton.middle,
        _ => MouseButton.left,
      };

  /// Drops the carried remainder. Called when the link drops, so a residual
  /// from before an outage does not nudge the cursor on reconnect.
  void reset() {
    _residualX = 0;
    _residualY = 0;
  }
}

/// Spreads one batch of watch movement across several small cursor moves.
///
/// ## Why this exists
///
/// The watch cannot send continuously — see `WatchLink.pump` — so movement
/// arrives in batches, each carrying everything the finger did since the last
/// one. Handed to the computer as a single `MouseMove`, a batch is a single
/// instantaneous jump: at a batch every 30 ms and a hand moving at any speed,
/// the cursor advances in thirty visible steps a second. That is not latency —
/// the cursor is exactly where it should be, at the right time — but it reads
/// as skipped frames, which is worse to use than being slightly behind.
///
/// So the batch is paid out over the interval the *next* one is expected in,
/// measured from the batches already seen rather than assumed. The cursor
/// glides instead of stepping. The cost is at most one batch interval of extra
/// delay on the final pixel of any movement, on a link where that interval is a
/// fraction of the Bluetooth round trip that produced it — and the first pixels
/// still move immediately.
///
/// Nothing here depends on a timer of its own: the caller drives it. That keeps
/// it a plain, testable object, and means the ticker can be stopped when the
/// wrist is still rather than running all day for nothing.
final class WatchMotionSmoother {
  /// How often [slice] is expected to be called.
  static const Duration tickInterval = Duration(milliseconds: 8);

  /// The gap assumed before enough batches have arrived to measure one, and the
  /// ceiling on the measurement. A watch that has been idle produces an
  /// enormous apparent interval, and paying a batch out over four seconds would
  /// leave the cursor drifting long after the finger stopped.
  static const double _defaultIntervalMillis = 33;
  static const double _maximumIntervalMillis = 120;

  /// Movement handed over but not yet passed on, in pixels.
  double _outstandingX = 0;
  double _outstandingY = 0;

  /// Sub-pixel remainder, carried between slices. Without it every slice
  /// smaller than a pixel rounds to nothing and slow movement never arrives.
  double _residualX = 0;
  double _residualY = 0;

  double _intervalMillis = _defaultIntervalMillis;
  DateTime? _lastBatch;

  /// Whether there is anything left to pay out.
  bool get isIdle => _outstandingX == 0 && _outstandingY == 0;

  /// Takes one batch from the watch, and notes how long it has been since the
  /// last one so the next payout matches the rhythm actually being observed.
  void addBatch(double dx, double dy, DateTime now) {
    final previous = _lastBatch;
    _lastBatch = now;
    if (previous != null) {
      final gap = now.difference(previous).inMicroseconds / 1000;
      if (gap > 0 && gap <= _maximumIntervalMillis) {
        // Smoothed: one late batch should bend the estimate, not replace it.
        _intervalMillis = _intervalMillis * 0.7 + gap * 0.3;
      }
    }
    _outstandingX += dx;
    _outstandingY += dy;
  }

  /// The next slice of movement, or null when there is nothing to send.
  MouseMove? slice() {
    if (isIdle) return null;

    final fraction =
        (tickInterval.inMicroseconds / 1000) / math.max(_intervalMillis, 1);
    // Never hold anything back on the last slice: below a pixel there is
    // nothing left to smooth, and a tail that asymptotes towards zero is a
    // cursor that keeps creeping after the finger has stopped.
    final takeAll = fraction >= 1 ||
        (_outstandingX.abs() < 1 && _outstandingY.abs() < 1);

    final stepX = takeAll ? _outstandingX : _outstandingX * fraction;
    final stepY = takeAll ? _outstandingY : _outstandingY * fraction;
    _outstandingX -= stepX;
    _outstandingY -= stepY;
    if (takeAll) {
      _outstandingX = 0;
      _outstandingY = 0;
    }

    return _emit(stepX, stepY, last: takeAll);
  }

  /// Everything still outstanding, at once.
  ///
  /// Used before a click: a button pressed while movement is still being paid
  /// out lands where the cursor has got to, not where the finger aimed it.
  MouseMove? flush() {
    if (isIdle) return null;
    final stepX = _outstandingX;
    final stepY = _outstandingY;
    _outstandingX = 0;
    _outstandingY = 0;
    return _emit(stepX, stepY, last: true);
  }

  /// Drops everything. Called when the link goes away, so movement from before
  /// an outage does not arrive after it.
  void reset() {
    _outstandingX = 0;
    _outstandingY = 0;
    _residualX = 0;
    _residualY = 0;
    _lastBatch = null;
    _intervalMillis = _defaultIntervalMillis;
  }

  /// One `MouseMove`, carrying the sub-pixel remainder forward.
  ///
  /// [last] rounds instead of truncating, and clears the remainder. Truncating
  /// the final slice throws away whatever is left below a pixel, and because
  /// the batch is finished there is no later slice to carry it into — so every
  /// gesture landed a fraction short of where the wrist put it, and the error
  /// accumulated over a session. A test caught this; the cursor drifting a
  /// pixel per gesture is exactly the sort of thing nobody reports and
  /// everybody feels.
  MouseMove? _emit(double dx, double dy, {bool last = false}) {
    final scaledX = dx + _residualX;
    final scaledY = dy + _residualY;
    final stepX = last ? scaledX.round() : scaledX.truncate();
    final stepY = last ? scaledY.round() : scaledY.truncate();
    _residualX = last ? 0 : scaledX - stepX;
    _residualY = last ? 0 : scaledY - stepY;
    if (stepX == 0 && stepY == 0) return null;
    return MouseMove(deltaX: stepX, deltaY: stepY);
  }
}

/// Whether this build can have a watch at all.
///
/// The channels only exist in the iOS host, and invoking a missing channel
/// throws a [MissingPluginException] per call. Checked once rather than caught
/// five times below.
///
/// A provider rather than a bare getter so a test can say "pretend this is an
/// iPhone" and exercise the relay for real. The alternative — asserting against
/// a translator in isolation — would leave the part that has actually broken
/// before (a message reaching the channel and going nowhere) untested.
final watchSupportedProvider = Provider<bool>((ref) {
  try {
    return Platform.isIOS;
  } on UnsupportedError {
    // Thrown by `dart:io` on the web. There is no watch there either.
    return false;
  }
});

/// What the phone knows about the watch, refreshed on demand.
final watchAvailabilityProvider =
    FutureProvider<WatchAvailability>((ref) async {
  if (!ref.watch(watchSupportedProvider)) return const WatchAvailability();
  try {
    final raw = await kWatchChannel.invokeMapMethod<Object?, Object?>(
      'watchState',
    );
    if (raw == null) return const WatchAvailability();
    return WatchAvailability.fromPlatform(raw);
  } on PlatformException {
    return const WatchAvailability();
  } on MissingPluginException {
    return const WatchAvailability();
  }
});

/// Runs the watch relay for as long as the app is alive.
///
/// Watched at the app root, alongside the background link, for the same reason:
/// a provider nobody watches is never created, and this one has to be listening
/// whichever screen happens to be open — including none, when iOS has launched
/// the app in the background purely to deliver a message from the wrist.
final watchBridgeProvider = Provider<void>((ref) {
  if (!ref.watch(watchSupportedProvider)) return;

  final log = Log.scoped('mobile.watch');
  final translator = WatchCommandTranslator(
    settings: ref.read(pointerSettingsProvider),
  );

  // Read live rather than captured: the user can change sensitivity while the
  // watch is in use, and a captured copy would keep the old value until the app
  // restarted.
  ref.listen<PointerSettings>(
    pointerSettingsProvider,
    (_, next) => translator.settings = next,
  );

  final smoother = WatchMotionSmoother();
  Timer? ticker;

  Future<void> deliver(Message message) async {
    final client = ref.read(clientProvider).valueOrNull;
    if (client == null || !client.isConnected) return;
    try {
      await client.send(message);
    } on Object catch (error) {
      // Same reasoning as the touchpad's send path: this fires many times a
      // second, and during a brief outage the supervisor is already
      // reconnecting. One log line, not one per event.
      log.debug(() => 'Dropped a watch command: $error');
    }
  }

  /// Runs only while there is movement left to pay out. A periodic timer that
  /// survives the gesture is a wakeup every 8 ms for the rest of the day.
  void startTicker() {
    ticker ??= Timer.periodic(WatchMotionSmoother.tickInterval, (_) {
      final step = smoother.slice();
      if (step != null) unawaited(deliver(step));
      if (smoother.isIdle) {
        ticker?.cancel();
        ticker = null;
      }
    });
  }

  Future<void> dispatch(Object? event) async {
    if (event is! Map) return;

    for (final message in translator.translate(event.cast<Object?, Object?>())) {
      if (message is MouseMove) {
        smoother.addBatch(
          message.deltaX.toDouble(),
          message.deltaY.toDouble(),
          DateTime.now(),
        );
        startTicker();
        continue;
      }
      // Anything that is not movement — a click, a button going down — has to
      // land where the finger aimed it, so whatever movement is still being
      // paid out goes first and goes at once.
      final pending = smoother.flush();
      if (pending != null) await deliver(pending);
      await deliver(message);
    }
  }

  final subscription = kWatchCommandChannel
      .receiveBroadcastStream()
      .listen(dispatch, onError: (Object error) {
    log.warn('Watch command stream failed: $error');
  });
  ref.onDispose(() {
    ticker?.cancel();
    unawaited(subscription.cancel());
  });

  // Tell the watch what it is driving, whenever that changes. The watch shows
  // the computer's name in its header, and a header that lies is worse than a
  // header that says "no computer" — the user aims a cursor at a screen on the
  // strength of it.
  Future<void> publish() async {
    final connected =
        ref.read(clientStateProvider).valueOrNull == ClientState.connected;
    if (!connected) {
      translator.reset();
      smoother.reset();
      ticker?.cancel();
      ticker = null;
    }
    try {
      await kWatchChannel.invokeMethod<void>('setLinkState', <String, Object?>{
        'connected': connected,
        'peer': connected ? _peerName(ref) : '',
      });
    } on PlatformException catch (error) {
      log.debug(() => 'Could not tell the watch about the link: $error');
    } on MissingPluginException {
      // An iOS build without the watch target. Nothing to tell.
    }
  }

  ref.listen<AsyncValue<ClientState>>(
    clientStateProvider,
    (_, __) => unawaited(publish()),
    fireImmediately: true,
  );
  // The computer's own name arrives after the connection is up, so the first
  // publish carries the target's name and this one corrects it.
  ref.listen<AsyncValue<DeviceInfo?>>(
    connectedPeerProvider,
    (_, __) => unawaited(publish()),
  );
});

/// What to call the computer on the watch.
///
/// The connection target first for the same reason the background notification
/// prefers it: the target survives a session dropping, and `DeviceInfo` only
/// arrives once a session is up.
String _peerName(Ref ref) {
  final target = ref.read(clientProvider).valueOrNull?.target;
  final named = target?.displayName;
  if (named != null && named.isNotEmpty) return named;

  final reported = ref.read(connectedPeerProvider).valueOrNull?.name;
  if (reported != null && reported.isNotEmpty) return reported;

  return target?.host ?? '';
}
