import 'dart:math';

import 'package:meta/meta.dart';

/// Computes how long to wait before the next connection attempt.
///
/// Exponential backoff with full jitter. The jitter is not cosmetic: when a
/// router reboots, every phone in the house retries at once, and a
/// deterministic schedule makes them collide on every attempt — the classic
/// thundering herd. Randomising the whole interval spreads them out.
///
/// The first retry is deliberately near-instant. The overwhelmingly common
/// failure is a two-second Wi-Fi handoff between access points, and waiting a
/// polite second before the first attempt would turn an invisible blip into a
/// visible disconnection.
@immutable
final class BackoffPolicy {
  const BackoffPolicy({
    this.initial = const Duration(milliseconds: 100),
    this.maximum = const Duration(seconds: 8),
    this.multiplier = 2.0,
    this.jitter = 1.0,
  });

  /// Aggressive schedule for a network that just dropped: 100 ms, 200, 400 …
  static const BackoffPolicy responsive = BackoffPolicy();

  /// Gentler schedule for a server that actively refused us.
  static const BackoffPolicy patient = BackoffPolicy(
    initial: Duration(seconds: 1),
    maximum: Duration(seconds: 60),
  );

  final Duration initial;
  final Duration maximum;
  final double multiplier;

  /// Fraction of the computed interval that is randomised, `0.0`–`1.0`.
  final double jitter;

  /// Delay before attempt number [attempt], counting from zero.
  Duration delayFor(int attempt, Random random) {
    if (attempt <= 0) return Duration.zero;

    final exponential =
        initial.inMicroseconds * pow(multiplier, attempt - 1).toDouble();
    final capped = min(exponential, maximum.inMicroseconds.toDouble());

    final jittered = jitter <= 0
        ? capped
        : capped * (1.0 - jitter) + capped * jitter * random.nextDouble();

    return Duration(microseconds: jittered.round());
  }
}
