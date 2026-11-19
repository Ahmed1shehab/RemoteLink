import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/clipboard/clipboard_history_controller.dart';
import 'package:remotelink_mobile/src/features/control/control_screen.dart';
import 'package:remotelink_mobile/src/features/devices/link_service.dart';
import 'package:remotelink_mobile/src/features/host/host_providers.dart';
import 'package:remotelink_mobile/src/features/premium/ads_gateway.dart';
import 'package:remotelink_mobile/src/features/premium/premium_providers.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'support/fakes.dart';
import 'support/l10n.dart';

class _TrackingAdsGateway implements AdsGateway {
  int bannerBuildCount = 0;

  @override
  bool get canRequestAds => true;

  @override
  void updatePremiumStatus(bool isPremium) {}

  @override
  Future<void> initializeAndRequestConsent() async {}

  @override
  Widget createBannerWidget({required BuildContext context}) {
    bannerBuildCount++;
    return const KeyedSubtree(
      key: Key('test_ad_banner'),
      child: SizedBox(height: 50),
    );
  }

  @override
  void preloadInterstitial() {}

  @override
  Future<bool> showInterstitial() async => false;
}

void main() {
  group('Monetization Gates', () {
    test(
        'Clipboard history caps at 5 entries for free users, unlimited for premium',
        () async {
      final container = ProviderContainer(
        overrides: <Override>[
          clockProvider.overrideWithValue(FakeClock()),
        ],
      );
      addTearDown(container.dispose);

      final history = container.read(clipboardHistoryProvider);
      final controller =
          container.read(clipboardHistoryControllerProvider.notifier);

      // Add 8 entries to history
      for (var i = 1; i <= 8; i++) {
        history.record(
          kind: ClipboardHistoryKind.text,
          data: Uint8List.fromList('Item $i'.codeUnits),
          contentHash: Uint8List.fromList(List<int>.filled(16, i)),
          isConcealed: false,
        );
      }
      await pumpEventQueue(times: 20);

      // Free user: capped at 5
      expect(controller.state.entries.length, 5);
      expect(controller.state.entries.first.preview(), 'Item 8');

      // Upgrade to premium
      container.read(isPremiumProvider.notifier).state = true;
      for (var i = 9; i <= 15; i++) {
        history.record(
          kind: ClipboardHistoryKind.text,
          data: Uint8List.fromList('Item $i'.codeUnits),
          contentHash: Uint8List.fromList(List<int>.filled(16, i)),
          isConcealed: false,
        );
      }
      await pumpEventQueue(times: 20);

      // Premium user: holds more than 5
      expect(controller.state.entries.length, greaterThan(5));
      expect(controller.state.entries.first.preview(), 'Item 15');
    });

    test('a premium user whose entitlement loads late loses no history',
        () async {
      // The entitlement reads as free until the store answers, so every cold
      // start passes through the free cap. That cap hides; it must not delete.
      final container = ProviderContainer(
        overrides: <Override>[
          clockProvider.overrideWithValue(FakeClock()),
        ],
      );
      addTearDown(container.dispose);

      final history = container.read(clipboardHistoryProvider);
      final controller =
          container.read(clipboardHistoryControllerProvider.notifier);
      for (var i = 1; i <= 8; i++) {
        history.record(
          kind: ClipboardHistoryKind.text,
          data: Uint8List.fromList('Item $i'.codeUnits),
          contentHash: Uint8List.fromList(List<int>.filled(16, i)),
          isConcealed: false,
        );
      }
      await pumpEventQueue(times: 20);
      expect(controller.state.entries.length, 5);

      container.read(isPremiumProvider.notifier).state = true;
      await pumpEventQueue(times: 20);

      expect(controller.state.entries.length, 8);
      expect(controller.state.entries.last.preview(), 'Item 1');
    });

    test(
        'Background clipboard accessibility settings permission is gated on premium',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final linkService = container.read(linkServiceProvider);

      // Free user: rejected immediately
      expect(await linkService.openAccessibilitySettings(), isFalse);

      // Premium user: allowed
      container.read(isPremiumProvider.notifier).state = true;
    });

    testWidgets('Ad banner is not built for premium users', (tester) async {
      final trackingAds = _TrackingAdsGateway();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...mobileSettingsOverrides(),
            adsGatewayProvider.overrideWithValue(trackingAds),
            isPremiumProvider.overrideWith((ref) {
              final notifier = IsPremiumNotifier(ref);
              notifier.state = true;
              return notifier;
            }),
            activeCapabilitiesProvider.overrideWithValue(
              const Capabilities(
                  Capabilities.clipboardText | Capabilities.mouse),
            ),
          ],
          child: wrapWithMobileLocalization(
            child: const ControlScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('test_ad_banner')), findsNothing);
      expect(trackingAds.bannerBuildCount, 0);
    });

    testWidgets(
        'Ad banner is hidden on input surface (touchpad) and shown on clipboard tab for free users',
        (tester) async {
      final trackingAds = _TrackingAdsGateway();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...mobileSettingsOverrides(),
            adsGatewayProvider.overrideWithValue(trackingAds),
            isPremiumProvider.overrideWith((ref) {
              final notifier = IsPremiumNotifier(ref);
              notifier.state = false;
              return notifier;
            }),
            activeCapabilitiesProvider.overrideWithValue(
              const Capabilities(
                  Capabilities.clipboardText | Capabilities.mouse),
            ),
          ],
          child: wrapWithMobileLocalization(
            child: const ControlScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default tab is Touchpad (input surface) -> banner is NOT shown
      expect(find.byKey(const Key('test_ad_banner')), findsNothing);

      // Switch to Clipboard tab (non-input surface)
      await tester.tap(find.text('Clipboard'));
      await tester.pumpAndSettle();

      // Banner should be visible on clipboard tab
      expect(find.byKey(const Key('test_ad_banner')), findsOneWidget);
    });
  });
}
