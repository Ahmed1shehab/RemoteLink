import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/premium/billing_gateway.dart';

void main() {
  group('BillingGateway and FakeBillingGateway', () {
    late FakeBillingGateway gateway;

    setUp(() {
      gateway = FakeBillingGateway();
    });

    test('initializes with default monthly and lifetime packages', () async {
      expect(gateway.isAvailable, isTrue);
      expect(await gateway.checkEntitlement(), isFalse);

      final offerings = await gateway.getPackages();
      expect(offerings, hasLength(2));
      expect(
        offerings.any((BillingPackage p) => p.plan == BillingPlan.monthly),
        isTrue,
      );
      expect(
        offerings.any((BillingPackage p) => p.plan == BillingPlan.lifetime),
        isTrue,
      );
    });

    test('purchase updates entitlement and emits on entitlementStream',
        () async {
      final emissions = <bool>[];
      final subscription = gateway.entitlementStream.listen(emissions.add);
      addTearDown(subscription.cancel);

      final offerings = await gateway.getPackages();
      final monthly = offerings
          .firstWhere((BillingPackage p) => p.plan == BillingPlan.monthly);

      final success = await gateway.purchase(monthly);
      expect(success, isTrue);
      expect(await gateway.checkEntitlement(), isTrue);
      expect(gateway.purchaseCalls, 1);
      expect(emissions, contains(true));
    });

    test('restorePurchases updates entitlement and emits on entitlementStream',
        () async {
      final emissions = <bool>[];
      final subscription = gateway.entitlementStream.listen(emissions.add);
      addTearDown(subscription.cancel);

      final success = await gateway.restorePurchases();
      expect(success, isTrue);
      expect(await gateway.checkEntitlement(), isTrue);
      expect(gateway.restoreCalls, 1);
      expect(emissions, contains(true));
    });

    test('setAvailable simulates billing unavailable state', () async {
      gateway.setAvailable(false);
      expect(gateway.isAvailable, isFalse);

      final offerings = await gateway.getPackages();
      expect(offerings, isEmpty);

      final success = await gateway.purchase(
        const BillingPackage(
          identifier: 'test',
          plan: BillingPlan.monthly,
          storeProductPriceString: r'$0.99',
        ),
      );
      expect(success, isFalse);

      final restored = await gateway.restorePurchases();
      expect(restored, isFalse);
    });
  });
}
