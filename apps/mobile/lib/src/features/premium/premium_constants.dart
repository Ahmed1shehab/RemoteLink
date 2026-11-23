import 'dart:io';

/// Constants and environment configurations for ads and billing.
///
/// Keys and ad units come from `--dart-define` so no secrets are committed.
/// Defaults use Google's published test ad unit identifiers. If RevenueCat keys
/// are omitted, billing degrades gracefully to an unavailable state without crashing.
abstract final class PremiumConstants {
  // Dart-define keys
  static const String revenueCatAppleKey =
      String.fromEnvironment('REVENUECAT_APPLE_KEY');
  static const String revenueCatGoogleKey =
      String.fromEnvironment('REVENUECAT_GOOGLE_KEY');

  static const String admobBannerAndroid = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const String admobBannerIos = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716',
  );

  static const String admobInterstitialAndroid = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );
  static const String admobInterstitialIos = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/4411468910',
  );

  /// Resolves the RevenueCat API key for the running platform.
  static String get activeRevenueCatKey {
    if (Platform.isIOS || Platform.isMacOS) return revenueCatAppleKey;
    if (Platform.isAndroid) return revenueCatGoogleKey;
    return '';
  }

  /// Resolves the AdMob banner unit ID for the running platform.
  static String get activeBannerAdUnitId {
    if (Platform.isIOS) return admobBannerIos;
    return admobBannerAndroid;
  }

  /// Resolves the AdMob interstitial unit ID for the running platform.
  static String get activeInterstitialAdUnitId {
    if (Platform.isIOS) return admobInterstitialIos;
    return admobInterstitialAndroid;
  }

  /// RevenueCat entitlement identifier for premium features and ad removal.
  static const String entitlementId = 'premium';

  /// Store product identifiers.
  static const String productMonthly = 'remotelink_premium_monthly';
  static const String productLifetime = 'remotelink_premium_lifetime';

  /// Fallback price strings used only if offerings fail to load from the store.
  static const String fallbackPriceMonthly = r'$0.99';
  static const String fallbackPriceLifetime = r'$4.99';

  /// Maximum entries preserved in clipboard history for free users.
  static const int freeClipboardHistoryLimit = 5;

  /// Frequency cap for interstitial ads between completed file transfers.
  static const Duration interstitialFrequencyCap = Duration(minutes: 10);
}
