import 'package:rl_core/rl_core.dart';

import 'premium_constants.dart';

/// Pure-Dart evaluation policy for interstitial ads.
///
/// Ensures interstitial rules can be unit tested without standing up
/// platform channels, widget trees, or mock ad networks:
/// 1. Interstitials are never shown at app start.
/// 2. Only triggered after a file transfer completes.
/// 3. Rate-limited to at most once per 10 minutes.
/// 4. Never shown while a pairing or file accept prompt is on screen.
/// 5. Never loaded or shown for premium users.
final class InterstitialPolicy {
  InterstitialPolicy({
    Clock? clock,
    Duration frequencyCap = PremiumConstants.interstitialFrequencyCap,
  })  : _clock = clock ?? SystemClock(),
        _frequencyCap = frequencyCap;

  final Clock _clock;
  final Duration _frequencyCap;

  DateTime? _lastShownAt;

  DateTime? get lastShownAt => _lastShownAt;

  /// Returns whether an interstitial ad may be presented right now.
  bool canShow({
    required bool isPremium,
    required bool isPromptOnScreen,
  }) {
    if (isPremium) return false;
    if (isPromptOnScreen) return false;

    final last = _lastShownAt;
    if (last != null) {
      final elapsed = _clock.now().difference(last);
      if (elapsed < _frequencyCap) {
        return false;
      }
    }

    return true;
  }

  /// Records that an interstitial was displayed, resetting the frequency cap window.
  void recordShown([DateTime? timestamp]) {
    _lastShownAt = timestamp ?? _clock.now();
  }

  /// Resets state (e.g., between tests).
  void reset() {
    _lastShownAt = null;
  }
}
