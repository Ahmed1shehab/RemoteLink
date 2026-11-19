import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/premium/interstitial_policy.dart';
import 'package:remotelink_mobile/src/features/premium/premium_constants.dart';
import 'package:rl_core/rl_core.dart';

void main() {
  group('InterstitialPolicy', () {
    late FakeClock clock;
    late InterstitialPolicy policy;

    setUp(() {
      clock = FakeClock(start: DateTime(2026, 11, 19, 12, 0, 0));
      policy = InterstitialPolicy(
        clock: clock,
        frequencyCap: PremiumConstants.interstitialFrequencyCap,
      );
    });

    test('allows ad when no ad has been shown and conditions are met', () {
      expect(
        policy.canShow(isPremium: false, isPromptOnScreen: false),
        isTrue,
      );
    });

    test('suppresses ad when user is premium', () {
      expect(
        policy.canShow(isPremium: true, isPromptOnScreen: false),
        isFalse,
      );
    });

    test('suppresses ad when a nearby prompt is visible on screen', () {
      expect(
        policy.canShow(isPremium: false, isPromptOnScreen: true),
        isFalse,
      );
    });

    test('enforces 10-minute frequency cap using injected clock', () {
      // First ad shown at 12:00
      policy.recordShown();
      expect(
        policy.canShow(isPremium: false, isPromptOnScreen: false),
        isFalse,
        reason: 'Ad just shown; must be suppressed by frequency cap',
      );

      // Advance clock by 5 minutes (12:05) -> still capped
      clock.advance(const Duration(minutes: 5));
      expect(
        policy.canShow(isPremium: false, isPromptOnScreen: false),
        isFalse,
        reason: '5 minutes elapsed; frequency cap requires 10 minutes',
      );

      // Advance clock by another 4 minutes and 59 seconds (12:09:59) -> still capped
      clock.advance(const Duration(minutes: 4, seconds: 59));
      expect(
        policy.canShow(isPremium: false, isPromptOnScreen: false),
        isFalse,
      );

      // Advance clock past 10 minutes (12:10:01) -> cap elapsed, ad allowed
      clock.advance(const Duration(seconds: 2));
      expect(
        policy.canShow(isPremium: false, isPromptOnScreen: false),
        isTrue,
        reason: '10 minutes have elapsed since last ad',
      );
    });

    test('reset clears the frequency cap timestamp', () {
      policy.recordShown();
      expect(
          policy.canShow(isPremium: false, isPromptOnScreen: false), isFalse);

      policy.reset();
      expect(policy.canShow(isPremium: false, isPromptOnScreen: false), isTrue);
    });
  });
}
