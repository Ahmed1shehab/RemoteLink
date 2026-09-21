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
/// The pointer *acceleration* curve is not applied here. It was originally left
/// out because it could not be applied correctly: the watch summed movement
/// into one delta per round trip, so every delta that arrived looked like a
/// fast one to a curve that judges speed by delta size, and the cursor would
/// have leapt on the gentlest drag.
///
/// That obstacle is gone — [motion] carries each slice's duration, so real
/// velocity is a division away — but the curve is still not applied, because
/// nobody has tuned it for this path yet. The user's linear sensitivity is
/// applied, and the curve is left to the path it was tuned for, which is a
/// finger on the phone's own glass.
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

  /// The path the finger drew in [raw], in pixels, slice by slice.
  ///
  /// Empty when the message carries only a total — a watch older than the path
  /// format — in which case the caller falls back to the `MouseMove` in
  /// [translate]'s output. The two are alternatives and never both: they
  /// describe the same travel, and replaying both would move the cursor twice
  /// as far as the wrist did.
  ///
  /// Scaled but not rounded. The protocol carries integer deltas, but these are
  /// not protocol messages yet — [WatchMotionSmoother] re-cuts them into slices
  /// of its own and carries the sub-pixel remainder across those. Rounding here
  /// would throw away resolution that the very next step needs.
  List<WatchMotionSegment> motion(Map<Object?, Object?> raw) {
    if (raw['t'] != 'move') return const <WatchMotionSegment>[];
    final path = raw['path'];
    if (path is! List || path.length < 3) return const <WatchMotionSegment>[];

    final segments = <WatchMotionSegment>[];
    for (var i = 0; i + 2 < path.length; i += 3) {
      final dx = (path[i] as num?)?.toDouble() ?? 0;
      final dy = (path[i + 1] as num?)?.toDouble() ?? 0;
      final millis = (path[i + 2] as num?)?.toDouble() ?? 0;
      if (!dx.isFinite || !dy.isFinite || !millis.isFinite) {
        return const <WatchMotionSegment>[];
      }
      segments.add((
        dx: dx * settings.sensitivity,
        dy: dy * settings.sensitivity,
        // A slice has to take some time or it cannot be replayed over any. The
        // watch clamps this too; a message that has been through a channel and
        // a codec is not something to take on trust.
        millis: millis.clamp(1.0, 1000.0),
      ));
    }
    return segments;
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

/// One slice of the path the finger drew, in pixels, and how long it took.
typedef WatchMotionSegment = ({double dx, double dy, double millis});

/// One slice being paid out. Mutable, because a slice is consumed a tick at a
/// time and what is left of it is the state that matters.
final class _Slice {
  _Slice(this.dx, this.dy, this.millis);

  double dx;
  double dy;
  double millis;
}

/// Replays one batch of watch movement as the path the finger actually drew.
///
/// ## Why this exists
///
/// The watch cannot send continuously — see `WatchLink.pump` — so movement
/// arrives in batches, each carrying everything the finger did since the last
/// one, roughly five times a second. Handed to the computer as a single
/// `MouseMove`, a batch is a single instantaneous jump: the cursor advances in
/// five visible steps a second. That is not latency — the cursor is exactly
/// where it should be, at the right time — but it reads as skipped frames,
/// which is worse to use than being slightly behind.
///
/// So the batch is paid out over the interval the *next* one is expected in,
/// measured from the batches already seen rather than assumed, and paid out as
/// the path the watch recorded rather than as a straight line. The cursor
/// glides, and it glides along the curve the finger drew. The cost is at most
/// one batch interval of extra delay on the final pixel of any movement, on a
/// link where that interval is a fraction of the Bluetooth round trip that
/// produced it — and the first pixels still move immediately.
///
/// ## Why the payout is at a constant speed
///
/// Paying out a fixed *fraction* of what is left each tick decays: the cursor
/// sprints at the start of every batch and crawls at the end of it, so its
/// speed pulses at the batch rate even when no tick is ever empty. The hand
/// moves evenly and the cursor does not. Each slice is therefore paid out at
/// its own constant speed, and the slices together carry the variation that was
/// really there.
///
/// Nothing here depends on a timer of its own: the caller drives it. That keeps
/// it a plain, testable object, and means the ticker can be stopped when the
/// wrist is still rather than running all day for nothing.
final class WatchMotionSmoother {
  WatchMotionSmoother({this.predictMotion = false});

  /// Whether to keep the cursor moving between batches on the last known
  /// velocity — see [_predict]. Off by default, because a smoother that
  /// invents movement is a poor thing to get by accident; the app turns it on
  /// explicitly.
  final bool predictMotion;

  /// How often [slice] is expected to be called.
  static const Duration tickInterval = Duration(milliseconds: 8);

  static const double _tickMillis = 8;

  /// The gap assumed before any batch has been timed.
  ///
  /// Near the low end of what the link actually does — ADR 0004 measured the
  /// relay at 200–230 ms on device — so the first batch of a gesture is paid
  /// out a little fast rather than a lot slow. Guessing high would hold the
  /// first movement of every gesture back behind a window that has not been
  /// earned yet.
  static const double _defaultIntervalMillis = 120;

  /// The ceiling on the estimate, well above the measured round trip so an
  /// ordinary slow batch is recorded rather than clipped. Only a gap this side
  /// of a stall is a measurement of the link; beyond it, smoothing cannot hide
  /// what is happening anyway.
  static const double _maximumIntervalMillis = 350;

  /// Past this the wrist stopped and started again. The pause is not a
  /// measurement of the link and must not be folded into one.
  static const double _restartIntervalMillis = 1000;

  /// How much longer than the estimated gap a batch is paid out over.
  ///
  /// The estimate is a mean and the link is not: a batch that arrives later
  /// than average would find the queue already empty, and an empty queue is a
  /// stopped cursor. Draining slightly slower than the batches arrive keeps a
  /// little movement in hand for exactly that case, and the leftover is folded
  /// into the next batch rather than paid out as a tail.
  static const double _slack = 1.2;

  /// How far ahead [_predict] will guess, in milliseconds of travel.
  ///
  /// Everything guessed has to be given back, so this is the size of the worst
  /// correction the cursor can be asked to make. Prediction is usually right —
  /// a batch is late far more often than a finger stops — but it is wrong at
  /// the end of every gesture, by definition, and this is what bounds the cost
  /// of being wrong.
  static const double _predictionCapMillis = 56;

  /// How quickly a guess loses confidence. Movement that is still going gets
  /// most of its first tick; a finger that has stopped costs a few tens of
  /// pixels of overshoot rather than a slide across the screen.
  static const double _predictionHalfLifeMillis = 40;

  /// The path still to be paid out, oldest slice first.
  final List<_Slice> _queue = <_Slice>[];

  /// Sub-pixel remainder, carried between ticks. Without it every tick smaller
  /// than a pixel rounds to nothing and slow movement never arrives.
  double _residualX = 0;
  double _residualY = 0;

  double _intervalMillis = _defaultIntervalMillis;
  DateTime? _lastBatch;

  /// The speed the path was running at when it ran out, in pixels per
  /// millisecond, and how far past the end the guess has already gone.
  double _velocityX = 0;
  double _velocityY = 0;
  double _predictedMillis = 0;

  /// Movement handed to the computer on spec and not yet earned back.
  double _debtX = 0;
  double _debtY = 0;

  /// Whether the cursor is known to have arrived, so there is nothing left to
  /// guess about.
  ///
  /// Set by [land] and [flush], cleared by the next batch. Without it the
  /// gliding stop looks to [_take] exactly like ordinary movement running out,
  /// and prediction carries on into the correction — guessing the cursor
  /// further backwards, then owing that too.
  bool _settled = true;

  /// Whether there is anything left to do — real movement or a guess still
  /// worth making.
  bool get isIdle => _queue.isEmpty && !_canPredict;

  bool get _canPredict =>
      predictMotion &&
      !_settled &&
      _predictedMillis < _predictionCapMillis &&
      (_velocityX != 0 || _velocityY != 0);

  /// Takes one batch from the watch as a single delta, with no path.
  ///
  /// What a watch older than the path format sends, and the shape the tests use
  /// when the path is not what is under test.
  void addBatch(double dx, double dy, DateTime now) =>
      addPath(<WatchMotionSegment>[(dx: dx, dy: dy, millis: 1)], now);

  /// Takes one batch from the watch as the path it drew, and notes how long it
  /// has been since the last one so the payout matches the rhythm actually
  /// being observed.
  void addPath(List<WatchMotionSegment> path, DateTime now) {
    final previous = _lastBatch;
    _lastBatch = now;
    if (previous != null) {
      final gap = now.difference(previous).inMicroseconds / 1000;
      if (gap > 0 && gap < _restartIntervalMillis) {
        // Clamped, not discarded. Throwing away every gap over the ceiling
        // taught the estimate only from the batches that happened to arrive
        // quickly, and this link averages 200 ms. The estimate settled far
        // under the real rhythm, so every batch finished paying out before the
        // next one landed and the cursor moved, stopped, moved, stopped — which
        // is the stepping this class exists to remove. A slow batch is the most
        // informative sample there is; it is the one that must not be dropped.
        final sample = math.min(gap, _maximumIntervalMillis);
        // Asymmetric on purpose. Guessing the gap too short strands the cursor
        // between batches and is plainly visible; guessing it too long costs a
        // few milliseconds of lag and is not. So the estimate jumps to meet a
        // slow batch and drifts back down only once the link has stayed fast.
        final weight = sample > _intervalMillis ? 0.6 : 0.15;
        _intervalMillis = _intervalMillis * (1 - weight) + sample * weight;
      }
    }

    // A slice that goes nowhere is dropped rather than queued. The watch only
    // records a slice when the finger moved, so an empty one carries no pause
    // worth replaying — it would just hold a share of the window doing nothing
    // while real movement waited behind it.
    final slices = <_Slice>[
      for (final segment in path)
        if (segment.dx != 0 || segment.dy != 0)
          _Slice(segment.dx, segment.dy, math.max(segment.millis, 1)),
    ];

    // What the last window did not finish, less whatever was handed over on
    // spec and has not been earned back. The old queue goes entirely: its
    // slices were timed against a window that has now been replaced, and what
    // is owed is a distance, not a shape.
    var carriedX = -_debtX;
    var carriedY = -_debtY;
    for (final slice in _queue) {
      carriedX += slice.dx;
      carriedY += slice.dy;
    }
    _queue.clear();
    _debtX = 0;
    _debtY = 0;
    _predictedMillis = 0;
    _settled = false;

    if (slices.isEmpty) {
      // Nothing new to draw the carry along, so it goes out as its own short
      // slice rather than being dropped — it is movement the wrist really made.
      if (carriedX == 0 && carriedY == 0) return;
      slices.add(_Slice(carriedX, carriedY, 1));
      carriedX = 0;
      carriedY = 0;
    }

    _carryInto(slices, carriedX, carriedY);
    _queue.addAll(slices);
    _retime();
  }

  /// Folds what is still owed into the path about to be replayed.
  ///
  /// Scaled along the path rather than prepended to it. A correction of its own
  /// is a jump, and a jump is the thing this class exists to remove; spread
  /// along the path, the same pixels arrive as a slightly faster version of the
  /// movement the finger actually made, and the shape survives untouched.
  ///
  /// Never past a standstill: a debt larger than the batch that follows it
  /// would otherwise scale the path negative and run the cursor backwards. What
  /// cannot be paid without reversing is simply forgiven. The cursor is a
  /// relative device with no absolute reference — a few pixels never repaid are
  /// invisible, and a backwards lurch is not.
  void _carryInto(List<_Slice> slices, double dx, double dy) {
    if (dx == 0 && dy == 0) return;

    var totalX = 0.0;
    var totalY = 0.0;
    var totalMillis = 0.0;
    for (final slice in slices) {
      totalX += slice.dx;
      totalY += slice.dy;
      totalMillis += slice.millis;
    }

    // Where an axis did not move at all there is no shape to scale, so the
    // carry is spread evenly over the time instead.
    final scaleX = totalX.abs() > 1e-9;
    final scaleY = totalY.abs() > 1e-9;
    final factorX = scaleX ? math.max(1 + dx / totalX, 0.0) : 1.0;
    final factorY = scaleY ? math.max(1 + dy / totalY, 0.0) : 1.0;

    for (final slice in slices) {
      final share = slice.millis / totalMillis;
      slice.dx = scaleX ? slice.dx * factorX : slice.dx + dx * share;
      slice.dy = scaleY ? slice.dy * factorY : slice.dy + dy * share;
    }
  }

  /// Stretches the whole queue so it drains over one window.
  ///
  /// The slices keep their durations relative to each other — that is the shape
  /// of the gesture — and the window they share is what the link's rhythm
  /// decides.
  void _retime() {
    if (_queue.isEmpty) return;
    var total = 0.0;
    for (final slice in _queue) {
      total += slice.millis;
    }
    if (total <= 0) return;
    final window = math.max(_intervalMillis * _slack, _tickMillis);
    final scale = window / total;
    for (final slice in _queue) {
      slice.millis *= scale;
    }
  }

  /// The next slice of movement, or null when there is nothing to send.
  MouseMove? slice() {
    if (_queue.isNotEmpty) {
      final (dx, dy) = _take(_tickMillis);
      // Rounding, and clearing the remainder, only once there is nothing left
      // to carry it into. A tail that asymptotes towards zero is a cursor that
      // keeps creeping after the finger has stopped — but while a guess is
      // still to come, the remainder has somewhere to go.
      return _emit(dx, dy, last: _queue.isEmpty && !_canPredict);
    }
    return _predict();
  }

  /// Consumes [millis] of the queued path, returning the pixels it covers.
  (double, double) _take(double millis) {
    var dx = 0.0;
    var dy = 0.0;
    var remaining = millis;
    while (remaining > 0 && _queue.isNotEmpty) {
      final head = _queue.first;
      if (head.millis <= remaining) {
        dx += head.dx;
        dy += head.dy;
        remaining -= head.millis;
        _queue.removeAt(0);
        continue;
      }
      final fraction = remaining / head.millis;
      final stepX = head.dx * fraction;
      final stepY = head.dy * fraction;
      dx += stepX;
      dy += stepY;
      head.dx -= stepX;
      head.dy -= stepY;
      head.millis -= remaining;
      remaining = 0;
    }

    // What the path was doing as it ran out, for the guess that may follow it.
    final elapsed = millis - remaining;
    if (elapsed > 0) {
      _velocityX = dx / elapsed;
      _velocityY = dy / elapsed;
    }
    return (dx, dy);
  }

  /// Keeps the cursor moving on the last known velocity while the next batch is
  /// in the air.
  ///
  /// The round trip is 200 ms, so the cursor can only ever show where the
  /// finger was 200 ms ago — and between batches it shows nothing at all, which
  /// is the part that can be fixed. A finger that was moving is overwhelmingly
  /// likely to still be moving, so the payout continues on the last velocity
  /// rather than stopping dead, and what it invents is remembered as a debt and
  /// taken back out of the next batch.
  ///
  /// The guess decays, and it is capped. A finger that really did stop costs a
  /// few pixels of overshoot, paid back into the next movement; without the cap
  /// it would cost a slide across the screen.
  MouseMove? _predict() {
    if (!_canPredict) return null;
    final decay =
        math.pow(0.5, _predictedMillis / _predictionHalfLifeMillis).toDouble();
    final stepX = _velocityX * _tickMillis * decay;
    final stepY = _velocityY * _tickMillis * decay;
    _predictedMillis += _tickMillis;
    _debtX += stepX;
    _debtY += stepY;
    return _emit(stepX, stepY, last: !_canPredict);
  }

  /// Everything still outstanding, at once.
  ///
  /// Used before a click, and when the watch says the finger has left the
  /// glass. A button pressed while movement is still being paid out lands where
  /// the cursor has got to, not where the finger aimed it.
  ///
  /// Any debt is settled here too, and this is the only place it can be. Until
  /// the watch says the gesture ended, the phone cannot tell a finger that has
  /// stopped from one whose next batch is still in the air — so a guess that
  /// overshot is given back at the one moment the cursor is known to have
  /// arrived.
  MouseMove? flush() {
    var dx = -_debtX;
    var dy = -_debtY;
    for (final slice in _queue) {
      dx += slice.dx;
      dy += slice.dy;
    }
    _queue.clear();
    _debtX = 0;
    _debtY = 0;
    _velocityX = 0;
    _velocityY = 0;
    _predictedMillis = 0;
    _settled = true;
    if (dx == 0 && dy == 0) return null;
    return _emit(dx, dy, last: true);
  }

  /// Eases to a stop, because the finger has left the glass.
  ///
  /// Everything outstanding is queued to run out over half a window, and any
  /// guess that overshot is given back along the way. A stop is the one moment
  /// the cursor is known to have arrived, and it is the only moment a debt can
  /// be settled — but it is still movement, and it still glides. Paid back as a
  /// jump it would read as the cursor bouncing at the end of every flick, which
  /// is a worse fault than the stall it was covering for.
  void land() {
    var dx = -_debtX;
    var dy = -_debtY;
    for (final slice in _queue) {
      dx += slice.dx;
      dy += slice.dy;
    }
    _queue.clear();
    _debtX = 0;
    _debtY = 0;
    // Nothing more is coming, so there is nothing left to guess about.
    _velocityX = 0;
    _velocityY = 0;
    _predictedMillis = 0;
    _settled = true;
    if (dx == 0 && dy == 0) return;
    _queue.add(_Slice(dx, dy, math.max(_intervalMillis * 0.5, _tickMillis)));
  }

  /// Drops everything. Called when the link goes away, so movement from before
  /// an outage does not arrive after it.
  void reset() {
    _queue.clear();
    _residualX = 0;
    _residualY = 0;
    _velocityX = 0;
    _velocityY = 0;
    _predictedMillis = 0;
    _debtX = 0;
    _debtY = 0;
    _settled = true;
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

  // Prediction on: the round trip is 200 ms, and a cursor that stops dead
  // between batches feels further behind than one that keeps going. Flip this
  // to false to get the plain replay back — it is the one switch.
  final smoother = WatchMotionSmoother(predictMotion: true);
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
    final raw = event.cast<Object?, Object?>();

    // The path the finger drew, when the watch sent one. Preferred over the
    // summed delta below because a path can be replayed and a total can only be
    // jumped — and the total is then zeroed out of the message, because the two
    // describe the same travel and replaying both would move the cursor twice
    // as far as the wrist did.
    final path = translator.motion(raw);
    if (path.isNotEmpty) {
      smoother.addPath(path, DateTime.now());
      startTicker();
    }
    final rest =
        path.isEmpty ? raw : <Object?, Object?>{...raw, 'dx': 0, 'dy': 0};

    // The finger has left the glass. Nothing further is coming, so whatever is
    // still queued runs out and the smoother stops guessing — see
    // `WatchMotionSmoother.land`.
    if (raw['ended'] == true) {
      smoother.land();
      startTicker();
    }

    for (final message in translator.translate(rest)) {
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
