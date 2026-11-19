import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../host/nearby_prompts.dart';
import '../media/media_screen.dart';
import '../transfer/transfer_controller.dart';
import 'ads_gateway.dart';
import 'billing_gateway.dart';
import 'interstitial_policy.dart';

/// The premium features guarded behind the entitlement.
enum PremiumFeature {
  /// Relaying input from the Apple Watch to the controlled computer.
  watchTrackpad,

  /// Continuous clipboard capture in the background via accessibility service.
  backgroundClipboard,

  /// Storing and restoring more than 5 clipboard history items.
  unlimitedClipboardHistory,
}

/// Provider for the platform billing gateway.
///
/// Overridden in tests with [FakeBillingGateway].
final billingGatewayProvider = Provider<BillingGateway>((ref) {
  final gateway = RevenueCatBillingGateway();
  return gateway;
});

/// Provider for the ads gateway.
///
/// Overridden in tests with [NoopAdsGateway].
final adsGatewayProvider = Provider<AdsGateway>((ref) {
  return AdMobAdsGateway();
});

/// Evaluates frequency cap and conditions for displaying interstitial ads.
final interstitialPolicyProvider = Provider<InterstitialPolicy>((ref) {
  return InterstitialPolicy(clock: ref.watch(clockProvider));
});

/// Tracks whether media controls are currently active (playing or dragging).
///
/// Used to keep banners off the media tab when the user is actively controlling playback.
final mediaDraggingProvider = StateProvider<bool>((ref) => false);

final mediaInUseProvider = Provider<bool>((ref) {
  final isPlaying =
      ref.watch(mediaStateProvider).valueOrNull?.isPlaying == true;
  final isDragging = ref.watch(mediaDraggingProvider);
  return isPlaying || isDragging;
});

/// Notifier exposing the user's current premium entitlement.
///
/// Follows ADR 0002 (hand-written provider, no code generation).
/// Initializes billing and updates [AdsGateway] whenever entitlement changes.
final class IsPremiumNotifier extends StateNotifier<bool> {
  IsPremiumNotifier(this._ref) : super(false) {
    _init();
  }

  final Ref _ref;
  StreamSubscription<bool>? _subscription;

  void _init() {
    final gateway = _ref.read(billingGatewayProvider);
    unawaited(gateway.initialize());
    _subscription = gateway.entitlementStream.listen((active) {
      state = active;
      _ref.read(adsGatewayProvider).updatePremiumStatus(active);
    });
    unawaited(refresh());
  }

  /// Explicitly re-queries entitlement from the billing gateway.
  Future<void> refresh() async {
    final active = await _ref.read(billingGatewayProvider).checkEntitlement();
    state = active;
    _ref.read(adsGatewayProvider).updatePremiumStatus(active);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

/// The single Riverpod provider exposing whether the user is premium.
final isPremiumProvider = StateNotifierProvider<IsPremiumNotifier, bool>(
  IsPremiumNotifier.new,
);

/// Coordinates interstitial presentation after file transfer completion.
///
/// Watched at the app root so completed transfers trigger the ad regardless of screen.
final interstitialCoordinatorProvider = Provider<void>((ref) {
  final controller = ref.watch(transferControllerProvider.notifier);
  final adsGateway = ref.watch(adsGatewayProvider);
  final policy = ref.watch(interstitialPolicyProvider);

  final sub = controller.onTransferCompleted.listen((_) async {
    final isPremium = ref.read(isPremiumProvider);
    final promptOnScreen = isNearbyPromptOnScreen;

    if (policy.canShow(
        isPremium: isPremium, isPromptOnScreen: promptOnScreen)) {
      final shown = await adsGateway.showInterstitial();
      if (shown) {
        policy.recordShown();
      }
    }
  });

  ref.onDispose(sub.cancel);
});
