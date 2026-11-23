import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:rl_core/rl_core.dart';

import 'premium_constants.dart';

/// Contract for ad loading, consent management, and rendering.
///
/// Implementations isolate the UI layer from AdMob and UMP specifics.
/// When the user is premium, all ad SDK network calls and loads are bypassed.
abstract interface class AdsGateway {
  /// Gathers user consent via Google UMP and initializes MobileAds if permitted.
  Future<void> initializeAndRequestConsent();

  /// Creates a banner ad widget sized for the current viewport width.
  Widget createBannerWidget({required BuildContext context});

  /// Requests presentation of a preloaded interstitial ad.
  Future<bool> showInterstitial();

  /// Preloads an interstitial ad in the background if eligible.
  void preloadInterstitial();

  /// Whether ads can be requested based on UMP consent and initialization state.
  bool get canRequestAds;

  /// Updates whether the user has premium entitlement (disables all ads if true).
  void updatePremiumStatus(bool isPremium);
}

/// Google AdMob implementation with UMP consent handling.
final class AdMobAdsGateway implements AdsGateway {
  AdMobAdsGateway({bool isPremium = false}) : _isPremium = isPremium;

  final Log _log = Log.scoped('mobile.ads.admob');
  bool _isPremium;
  bool _initialized = false;
  bool _canRequestAds = false;

  InterstitialAd? _preloadedInterstitial;
  bool _loadingInterstitial = false;

  @override
  bool get canRequestAds => _canRequestAds && !_isPremium;

  @override
  void updatePremiumStatus(bool isPremium) {
    _isPremium = isPremium;
    if (_isPremium) {
      _preloadedInterstitial?.dispose();
      _preloadedInterstitial = null;
      _log.debug(() => 'Premium entitlement active; disposed preloaded ads.');
    }
  }

  @override
  Future<void> initializeAndRequestConsent() async {
    if (_isPremium) {
      _log.debug(
          () => 'User is premium; skipping AdMob and UMP initialization.');
      return;
    }

    final completer = Completer<void>();
    final params = ConsentRequestParameters();

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((formError) async {
          if (formError != null) {
            _log.warn('Consent form error: ${formError.message}');
          }

          final canRequest = await ConsentInformation.instance.canRequestAds();
          _canRequestAds = canRequest;

          if (canRequest && !_isPremium && !_initialized) {
            await MobileAds.instance.initialize();
            _initialized = true;
            _log.info('MobileAds initialized successfully after UMP consent.');
            preloadInterstitial();
          }

          if (!completer.isCompleted) completer.complete();
        });
      },
      (FormError error) {
        _log.warn('Consent info update failed: ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  @override
  void preloadInterstitial() {
    if (_isPremium ||
        !_canRequestAds ||
        _preloadedInterstitial != null ||
        _loadingInterstitial) {
      return;
    }

    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: PremiumConstants.activeInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          if (_isPremium) {
            ad.dispose();
            return;
          }
          _preloadedInterstitial = ad;
          _log.debug(() => 'Interstitial ad loaded and cached.');
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          _log.warn('Interstitial failed to load: ${error.message}');
        },
      ),
    );
  }

  @override
  Future<bool> showInterstitial() async {
    if (_isPremium) return false;
    final ad = _preloadedInterstitial;
    if (ad == null) {
      preloadInterstitial();
      return false;
    }

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadedInterstitial = null;
        preloadInterstitial();
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _log.warn('Interstitial failed to show: ${error.message}');
        ad.dispose();
        _preloadedInterstitial = null;
        preloadInterstitial();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    await ad.show();
    return completer.future;
  }

  @override
  Widget createBannerWidget({required BuildContext context}) {
    if (_isPremium || !_canRequestAds) {
      return const SizedBox.shrink();
    }
    return _AdMobBannerView(gateway: this);
  }
}

/// Stateful widget hosting an anchored adaptive banner ad.
class _AdMobBannerView extends StatefulWidget {
  const _AdMobBannerView({required this.gateway});

  final AdMobAdsGateway gateway;

  @override
  State<_AdMobBannerView> createState() => _AdMobBannerViewState();
}

class _AdMobBannerViewState extends State<_AdMobBannerView> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  final Log _log = Log.scoped('mobile.ads.banner');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAd();
  }

  Future<void> _loadAd() async {
    if (!mounted ||
        widget.gateway._isPremium ||
        !widget.gateway.canRequestAds) {
      return;
    }
    if (_bannerAd != null) return;

    final width = MediaQuery.sizeOf(context).width.truncate();
    final adSize = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted) return;

    final banner = BannerAd(
      adUnitId: PremiumConstants.activeBannerAdUnitId,
      size: adSize ?? AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          _log.warn('Banner failed to load: ${error.message}');
          ad.dispose();
        },
      ),
    );

    await banner.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (!_isLoaded || ad == null || widget.gateway._isPremium) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}

/// No-op ads gateway for unit tests or platforms without ad support.
final class NoopAdsGateway implements AdsGateway {
  const NoopAdsGateway();

  @override
  bool get canRequestAds => false;

  @override
  void updatePremiumStatus(bool isPremium) {}

  @override
  Future<void> initializeAndRequestConsent() async {}

  @override
  Widget createBannerWidget({required BuildContext context}) =>
      const SizedBox.shrink();

  @override
  void preloadInterstitial() {}

  @override
  Future<bool> showInterstitial() async => false;
}
