import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:meta/meta.dart';

/// How the phone converts finger movement into cursor movement.
@immutable
final class PointerSettings {
  const PointerSettings({
    this.sensitivity = 1.6,
    this.acceleration = 1.0,
    this.naturalScrolling = true,
    this.scrollSensitivity = 1.0,
    this.tapToClick = true,
  });

  /// Linear multiplier applied to every delta.
  final double sensitivity;

  /// How strongly fast movement is amplified. `1.0` disables acceleration.
  final double acceleration;

  /// Content follows the finger, as on iOS and modern macOS.
  final bool naturalScrolling;

  final double scrollSensitivity;

  /// Whether a tap counts as a click, or only the physical buttons do.
  final bool tapToClick;

  PointerSettings copyWith({
    double? sensitivity,
    double? acceleration,
    bool? naturalScrolling,
    double? scrollSensitivity,
    bool? tapToClick,
  }) =>
      PointerSettings(
        sensitivity: sensitivity ?? this.sensitivity,
        acceleration: acceleration ?? this.acceleration,
        naturalScrolling: naturalScrolling ?? this.naturalScrolling,
        scrollSensitivity: scrollSensitivity ?? this.scrollSensitivity,
        tapToClick: tapToClick ?? this.tapToClick,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sensitivity': sensitivity,
        'acceleration': acceleration,
        'naturalScrolling': naturalScrolling,
        'scrollSensitivity': scrollSensitivity,
        'tapToClick': tapToClick,
      };

  factory PointerSettings.fromJson(Map<String, dynamic> json) =>
      PointerSettings(
        sensitivity: (json['sensitivity'] as num?)?.toDouble() ?? 1.6,
        acceleration: (json['acceleration'] as num?)?.toDouble() ?? 1.0,
        naturalScrolling: json['naturalScrolling'] as bool? ?? true,
        scrollSensitivity:
            (json['scrollSensitivity'] as num?)?.toDouble() ?? 1.0,
        tapToClick: json['tapToClick'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PointerSettings &&
          other.sensitivity == sensitivity &&
          other.acceleration == acceleration &&
          other.naturalScrolling == naturalScrolling &&
          other.scrollSensitivity == scrollSensitivity &&
          other.tapToClick == tapToClick;

  @override
  int get hashCode => Object.hash(
        sensitivity,
        acceleration,
        naturalScrolling,
        scrollSensitivity,
        tapToClick,
      );
}

/// Converts touch input into protocol-ready integer deltas.
///
/// ## Why acceleration lives on the phone
///
/// The desktop could apply it, but the phone is the only side that knows the
/// screen's physical DPI and therefore how far the finger actually travelled in
/// millimetres. Sending pre-scaled deltas also keeps the desktop a dumb
/// executor, which means sensitivity tuning ships in a mobile update rather
/// than requiring both sides to move in lockstep.
///
/// ## Why the residual accumulator exists
///
/// The protocol carries integer deltas, so scaled movement has to be rounded.
/// Discarding the fraction each frame is a slow, invisible drift: a 0.4-pixel
/// remainder dropped 120 times a second is 48 pixels of movement per second
/// that the user made and the cursor did not. Carrying the remainder forward
/// makes the mapping exact over any window longer than a single frame.
final class PointerController {
  PointerController({this.settings = const PointerSettings()});

  PointerSettings settings;

  /// Sub-pixel movement carried between frames.
  double _residualX = 0;
  double _residualY = 0;

  /// Timestamp of the previous sample, for velocity.
  Duration? _lastTimestamp;

  /// Converts a pan delta into an integer cursor delta.
  ///
  /// Returns `null` when the accumulated movement rounds to zero, so the caller
  /// can skip the send entirely rather than transmitting a no-op.
  (int, int)? translatePan(Offset delta, Duration timestamp) {
    final elapsed = _lastTimestamp == null
        ? const Duration(milliseconds: 8)
        : timestamp - _lastTimestamp!;
    _lastTimestamp = timestamp;

    final gain = _gainFor(delta, elapsed);

    final scaledX = delta.dx * settings.sensitivity * gain + _residualX;
    final scaledY = delta.dy * settings.sensitivity * gain + _residualY;

    final deltaX = scaledX.truncate();
    final deltaY = scaledY.truncate();

    _residualX = scaledX - deltaX;
    _residualY = scaledY - deltaY;

    if (deltaX == 0 && deltaY == 0) return null;
    return (deltaX, deltaY);
  }

  /// Pointer-acceleration curve.
  ///
  /// Slow movement is left alone so fine positioning stays precise; fast
  /// movement is amplified so crossing a 4K screen does not need six swipes.
  /// The curve is a power function of velocity, which is the same shape both
  /// desktop OSes use — matching it makes the remote feel like the machine's
  /// own trackpad rather than a different device.
  double _gainFor(Offset delta, Duration elapsed) {
    if (settings.acceleration <= 1.0) return 1;

    final millis = elapsed.inMicroseconds / 1000.0;
    if (millis <= 0) return 1;

    // Logical pixels per millisecond.
    final velocity = delta.distance / millis;

    // Below this the user is aiming, not travelling, and amplifying would make
    // precise targeting impossible.
    const threshold = 0.5;
    if (velocity <= threshold) return 1;

    const maximumGain = 3.5;
    final gain = pow(velocity / threshold, settings.acceleration - 1.0);
    return gain.toDouble().clamp(1.0, maximumGain);
  }

  /// Converts a two-finger pan into scroll deltas.
  ///
  /// Both line and pixel amounts are produced because the two desktops want
  /// different things: Windows applications expect discrete wheel notches while
  /// macOS expects continuous pixels with momentum. Sending both lets each
  /// backend use whichever is native instead of converting lossily in between.
  ({int linesX, int linesY, int pixelsX, int pixelsY}) translateScroll(
    Offset delta,
  ) {
    final direction = settings.naturalScrolling ? 1 : -1;
    final scaled = delta * settings.scrollSensitivity * direction.toDouble();

    // Roughly one notch per 40 logical pixels, matching the distance a physical
    // wheel click scrolls on both platforms.
    const pixelsPerLine = 40.0;

    return (
      linesX: (scaled.dx / pixelsPerLine).round(),
      linesY: (scaled.dy / pixelsPerLine).round(),
      pixelsX: scaled.dx.round(),
      pixelsY: scaled.dy.round(),
    );
  }

  /// Clears carried state at the end of a gesture.
  ///
  /// Without this, the residual from one swipe leaks into the first frame of
  /// the next, which shows up as the cursor twitching when the user puts their
  /// finger down.
  void endGesture() {
    _residualX = 0;
    _residualY = 0;
    _lastTimestamp = null;
  }
}

/// Distinguishes a tap from a drag and counts multi-taps.
///
/// Click counting happens here rather than on the desktop because network
/// jitter can stretch two taps past any OS double-click threshold. The phone
/// sees the real timing, so it decides, and the desktop is told the answer.
final class TapRecogniser {
  TapRecogniser({
    this.multiTapWindow = const Duration(milliseconds: 300),
    this.movementTolerance = 12.0,
  });

  /// Maximum gap between taps for them to count as one gesture.
  final Duration multiTapWindow;

  /// How far a finger may move and still count as a tap rather than a drag.
  ///
  /// Twelve logical pixels is forgiving on purpose: a thumb on a phone screen
  /// always moves a little, and treating that as a drag makes tap-to-click feel
  /// unreliable in exactly the way users describe as "it doesn't always work".
  final double movementTolerance;

  DateTime? _lastTapAt;
  int _consecutiveTaps = 0;

  /// Records a tap, returning the click count to report (1, 2, or 3).
  int registerTap(DateTime now) {
    final last = _lastTapAt;
    if (last != null && now.difference(last) <= multiTapWindow) {
      _consecutiveTaps = (_consecutiveTaps % 3) + 1;
    } else {
      _consecutiveTaps = 1;
    }
    _lastTapAt = now;
    return _consecutiveTaps;
  }

  /// Whether [distance] travelled still counts as a tap.
  bool isTap(double distance) => distance <= movementTolerance;

  void reset() {
    _lastTapAt = null;
    _consecutiveTaps = 0;
  }
}
