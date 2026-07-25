import 'dart:async';

import 'package:meta/meta.dart';

/// Injectable time source.
///
/// Every timestamp, timeout, and backoff computation in RemoteLink goes through
/// a [Clock] so that latency and reconnect logic is testable without real
/// waiting. Production code uses [SystemClock]; tests use [FakeClock].
abstract interface class Clock {
  /// Wall-clock time. Used for protocol timestamps and UI display only — never
  /// for measuring durations, because it can jump when NTP corrects the host.
  DateTime now();

  /// Monotonic microseconds since an arbitrary origin. Immune to clock steps
  /// and DST changes, so this is what RTT and timeout math uses.
  int monotonicMicros();

  /// Completes after [duration] has elapsed on this clock.
  Future<void> delay(Duration duration);
}

/// Real time, backed by [DateTime.now] and a process-lifetime [Stopwatch].
final class SystemClock implements Clock {
  SystemClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  DateTime now() => DateTime.now();

  @override
  int monotonicMicros() => _stopwatch.elapsedMicroseconds;

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}

/// Manually advanced clock for deterministic tests.
///
/// [delay] never waits on real time; it parks a [Completer] that is resolved
/// the next time [advance] moves past its deadline. A ten-minute reconnect
/// backoff sequence therefore runs in microseconds of test time.
@visibleForTesting
final class FakeClock implements Clock {
  FakeClock({DateTime? start})
      : _now = start ?? DateTime.utc(2026),
        _micros = 0;

  DateTime _now;
  int _micros;
  final List<_PendingDelay> _pending = <_PendingDelay>[];

  @override
  DateTime now() => _now;

  @override
  int monotonicMicros() => _micros;

  @override
  Future<void> delay(Duration duration) {
    if (duration <= Duration.zero) return Future<void>.value();
    final pending = _PendingDelay(_micros + duration.inMicroseconds);
    _pending.add(pending);
    return pending.completer.future;
  }

  /// Moves time forward, resolving every [delay] whose deadline has passed.
  ///
  /// Deadlines fire in chronological order, matching real timer semantics.
  void advance(Duration duration) {
    _micros += duration.inMicroseconds;
    _now = _now.add(duration);

    final due = _pending.where((p) => p.deadlineMicros <= _micros).toList()
      ..sort((a, b) => a.deadlineMicros.compareTo(b.deadlineMicros));
    _pending.removeWhere((p) => p.deadlineMicros <= _micros);
    for (final p in due) {
      p.completer.complete();
    }
  }

  /// Number of timers still armed. Assert this is zero to catch leaked timers.
  int get pendingCount => _pending.length;
}

final class _PendingDelay {
  _PendingDelay(this.deadlineMicros);

  final int deadlineMicros;
  final Completer<void> completer = Completer<void>();
}
