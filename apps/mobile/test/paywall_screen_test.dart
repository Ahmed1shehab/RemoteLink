import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/premium/billing_gateway.dart';
import 'package:remotelink_mobile/src/features/premium/paywall_screen.dart';
import 'package:remotelink_mobile/src/features/premium/premium_providers.dart';

import 'support/l10n.dart';

void main() {
  testWidgets(
      'PaywallScreen renders features, plans with store prices, and best value badge',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeBilling = FakeBillingGateway(
      packages: const <BillingPackage>[
        BillingPackage(
          identifier: r'$rc_monthly',
          plan: BillingPlan.monthly,
          storeProductPriceString: '€0.99',
        ),
        BillingPackage(
          identifier: r'$rc_lifetime',
          plan: BillingPlan.lifetime,
          storeProductPriceString: '€4.99',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          billingGatewayProvider.overrideWithValue(fakeBilling),
        ],
        child: wrapWithMobileLocalization(
          child: const PaywallScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Features list
    expect(find.text('What you get with Premium'), findsOneWidget);
    expect(find.textContaining('Removes all banners'), findsOneWidget);
    expect(find.textContaining('Apple Watch trackpad'), findsOneWidget);
    expect(find.textContaining('Background clipboard'), findsOneWidget);
    expect(find.textContaining('Unlimited clipboard history'), findsOneWidget);

    // Store prices (dynamic, localized)
    expect(find.text('€0.99'), findsOneWidget);
    expect(find.text('€4.99'), findsOneWidget);

    // Lifetime badge
    expect(find.text('Best Value'), findsOneWidget);

    // Restore button
    expect(find.text('Restore Purchases'), findsOneWidget);

    // Auto-renew disclosure for monthly plan (monthly is selected by default)
    expect(find.textContaining('auto-renewing subscription'), findsOneWidget);

    // Purchase button
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
  });

  testWidgets(
      'Selecting lifetime plan updates disclosure and allows purchasing',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeBilling = FakeBillingGateway();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          billingGatewayProvider.overrideWithValue(fakeBilling),
        ],
        child: wrapWithMobileLocalization(
          child: const PaywallScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Lifetime plan
    await tester.ensureVisible(find.text('Lifetime'));
    await tester.tap(find.text('Lifetime'));
    await tester.pumpAndSettle();

    // Monthly disclosure is hidden for lifetime plan
    expect(find.textContaining('auto-renewing subscription'), findsNothing);

    // Tap continue
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(fakeBilling.purchaseCalls, 1);
  });

  testWidgets('Tapping restore purchases triggers gateway restore',
      (tester) async {
    final fakeBilling = FakeBillingGateway();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          billingGatewayProvider.overrideWithValue(fakeBilling),
        ],
        child: wrapWithMobileLocalization(
          child: const PaywallScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore Purchases'));
    await tester.pumpAndSettle();

    expect(fakeBilling.restoreCalls, 1);
  });

  testWidgets('Shows purchases unavailable state when billing is unavailable',
      (tester) async {
    final fakeBilling = FakeBillingGateway(isAvailable: false);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          billingGatewayProvider.overrideWithValue(fakeBilling),
        ],
        child: wrapWithMobileLocalization(
          child: const PaywallScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Purchases are currently unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('Renders member active state when already premium',
      (tester) async {
    final fakeBilling = FakeBillingGateway(initialPremium: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          billingGatewayProvider.overrideWithValue(fakeBilling),
          isPremiumProvider.overrideWith((ref) {
            final notifier = IsPremiumNotifier(ref);
            notifier.state = true;
            return notifier;
          }),
        ],
        child: wrapWithMobileLocalization(
          child: const PaywallScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("You're a Premium Member"), findsOneWidget);
  });
}
