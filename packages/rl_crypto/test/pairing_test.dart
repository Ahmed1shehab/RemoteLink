import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:test/test.dart';

/// The rate limiter is the only thing standing between a six-digit SAS and an
/// attacker who can retry. `docs/SECURITY.md` §3 argues the numeric method is
/// safe to offer *because* this exists — so the argument is only as good as
/// these tests.
void main() {
  group('PairingRateLimiter', () {
    late FakeClock clock;
    late PairingRateLimiter limiter;

    setUp(() {
      clock = FakeClock();
      limiter = PairingRateLimiter(clock: clock);
    });

    test('allows a peer that has never failed', () {
      expect(limiter.isAllowed('peer-a'), isTrue);
      expect(limiter.attemptsRemaining('peer-a'), kMaxPairingAttempts);
      expect(limiter.retryAfterSeconds('peer-a'), isNull);
    });

    test('locks out after exactly the configured number of failures', () {
      for (var attempt = 1; attempt < kMaxPairingAttempts; attempt++) {
        limiter.recordFailure('peer-a');
        expect(
          limiter.isAllowed('peer-a'),
          isTrue,
          reason: 'still allowed after $attempt of $kMaxPairingAttempts',
        );
      }

      limiter.recordFailure('peer-a');
      expect(limiter.isAllowed('peer-a'), isFalse);
      expect(limiter.attemptsRemaining('peer-a'), 0);
    });

    test('reports how long the lockout has left', () {
      for (var i = 0; i < kMaxPairingAttempts; i++) {
        limiter.recordFailure('peer-a');
      }

      final remaining = limiter.retryAfterSeconds('peer-a');
      expect(remaining, isNotNull);
      expect(remaining, greaterThan(0));
      expect(remaining, lessThanOrEqualTo(kPairingLockout.inSeconds + 1));
    });

    test('a lockout expires once the clock passes it', () {
      for (var i = 0; i < kMaxPairingAttempts; i++) {
        limiter.recordFailure('peer-a');
      }
      expect(limiter.isAllowed('peer-a'), isFalse);

      // One second short of the lockout: still refused.
      clock.advance(kPairingLockout - const Duration(seconds: 1));
      expect(limiter.isAllowed('peer-a'), isFalse);

      clock.advance(const Duration(seconds: 2));
      expect(limiter.isAllowed('peer-a'), isTrue);
      expect(
        limiter.attemptsRemaining('peer-a'),
        kMaxPairingAttempts,
        reason: 'an expired lockout should restore a full budget, not resume '
            'mid-count',
      );
    });

    // The property SECURITY.md §3 explicitly claims, and the one that would be
    // easiest to get wrong: "Lockouts are per-peer rather than global, so one
    // hostile device on the network cannot lock a user out of pairing their
    // own phone."
    test('a lockout applies only to the peer that caused it', () {
      for (var i = 0; i < kMaxPairingAttempts; i++) {
        limiter.recordFailure('hostile-device');
      }

      expect(limiter.isAllowed('hostile-device'), isFalse);
      expect(
        limiter.isAllowed('my-own-phone'),
        isTrue,
        reason: 'a hostile device must not be able to lock the user out of '
            'pairing their own phone',
      );
      expect(limiter.attemptsRemaining('my-own-phone'), kMaxPairingAttempts);
    });

    test('a success clears the failure history', () {
      limiter
        ..recordFailure('peer-a')
        ..recordFailure('peer-a');
      expect(limiter.attemptsRemaining('peer-a'), kMaxPairingAttempts - 2);

      limiter.recordSuccess('peer-a');
      expect(limiter.attemptsRemaining('peer-a'), kMaxPairingAttempts);
      expect(limiter.isAllowed('peer-a'), isTrue);
    });

    test('a success on one peer does not clear another peer\'s failures', () {
      limiter
        ..recordFailure('peer-a')
        ..recordFailure('peer-b')
        ..recordSuccess('peer-a');

      expect(limiter.attemptsRemaining('peer-a'), kMaxPairingAttempts);
      expect(limiter.attemptsRemaining('peer-b'), kMaxPairingAttempts - 1);
    });

    test('pruning drops expired lockouts but keeps live ones', () {
      for (var i = 0; i < kMaxPairingAttempts; i++) {
        limiter.recordFailure('expired-peer');
      }

      clock.advance(kPairingLockout + const Duration(seconds: 1));

      for (var i = 0; i < kMaxPairingAttempts; i++) {
        limiter.recordFailure('live-peer');
      }

      limiter.prune();

      expect(limiter.isAllowed('expired-peer'), isTrue);
      expect(
        limiter.isAllowed('live-peer'),
        isFalse,
        reason: 'pruning is bookkeeping and must not release a live lockout',
      );
    });

    test('the attacker budget is what the security model assumes', () {
      // SECURITY.md reasons that three attempts per fifteen minutes reduces an
      // attacker to roughly twelve guesses an hour against a 10^6 space. If
      // either constant is ever changed, that argument changes with it, and
      // this test is where it should be noticed.
      expect(kMaxPairingAttempts, 3);
      expect(kPairingLockout, const Duration(minutes: 15));

      const guessesPerHour =
          kMaxPairingAttempts * (60 / 15); // attempts x lockouts per hour
      expect(guessesPerHour, 12);
    });
  });
}
