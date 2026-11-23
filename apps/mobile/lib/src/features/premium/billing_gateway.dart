import 'dart:async';

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rl_core/rl_core.dart';

import 'premium_constants.dart';

/// Billing plan tier offered to users.
enum BillingPlan {
  monthly,
  lifetime,
}

/// A product package available for purchase from the underlying store.
final class BillingPackage {
  const BillingPackage({
    required this.identifier,
    required this.plan,
    required this.storeProductPriceString,
    this.rawPackage,
  });

  final String identifier;
  final BillingPlan plan;
  final String storeProductPriceString;
  final Package? rawPackage;
}

/// Abstract contract for billing and entitlement verification.
///
/// Implementations isolate the UI and controller layers from platform billing SDKs.
/// Tests use [FakeBillingGateway] so no platform channels or mock SDKs are needed.
abstract interface class BillingGateway {
  /// Initializes the billing service and verifies initial entitlement state.
  Future<void> initialize();

  /// Stream of entitlement changes (true = active premium entitlement).
  Stream<bool> get entitlementStream;

  /// Queries the current entitlement status.
  Future<bool> checkEntitlement();

  /// Fetches available packages from the current offering.
  Future<List<BillingPackage>> getPackages();

  /// Executes purchase of the given [package]. Returns true if premium entitlement is active.
  Future<bool> purchase(BillingPackage package);

  /// Restores previous purchases. Returns true if premium entitlement is restored.
  Future<bool> restorePurchases();

  /// Whether billing is configured and available on this platform.
  bool get isAvailable;
}

/// Production billing gateway powered by RevenueCat.
final class RevenueCatBillingGateway implements BillingGateway {
  RevenueCatBillingGateway({String? apiKey})
      : _apiKey = apiKey ?? PremiumConstants.activeRevenueCatKey;

  final String _apiKey;
  final Log _log = Log.scoped('mobile.billing.revenuecat');
  final StreamController<bool> _entitlementController =
      StreamController<bool>.broadcast();

  bool _initialized = false;
  bool _isEntitled = false;

  @override
  bool get isAvailable => _apiKey.isNotEmpty;

  @override
  Stream<bool> get entitlementStream => _entitlementController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!isAvailable) {
      _log.info(
          'RevenueCat API key not configured; billing disabled gracefully.');
      _isEntitled = false;
      _entitlementController.add(false);
      return;
    }

    try {
      final configuration = PurchasesConfiguration(_apiKey);
      await Purchases.configure(configuration);

      Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);

      final initialInfo = await Purchases.getCustomerInfo();
      _onCustomerInfoUpdate(initialInfo);
    } on Object catch (error) {
      _log.warn('Could not initialize RevenueCat: $error');
      _isEntitled = false;
      _entitlementController.add(false);
    }
  }

  void _onCustomerInfoUpdate(CustomerInfo info) {
    final active =
        info.entitlements.all[PremiumConstants.entitlementId]?.isActive == true;
    _isEntitled = active;
    _entitlementController.add(active);
    _log.debug(() => 'Customer entitlement updated: active=$active');
  }

  @override
  Future<bool> checkEntitlement() async {
    if (!isAvailable) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      _onCustomerInfoUpdate(info);
      return _isEntitled;
    } on Object catch (error) {
      _log.warn('Could not check CustomerInfo: $error');
      return _isEntitled;
    }
  }

  @override
  Future<List<BillingPackage>> getPackages() async {
    if (!isAvailable) return const <BillingPackage>[];

    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) {
        _log.warn('No current offering found in RevenueCat');
        return const <BillingPackage>[];
      }

      final packages = <BillingPackage>[];

      // Monthly package
      final monthly = current.monthly ??
          current.availablePackages.where((p) {
            return p.packageType == PackageType.monthly ||
                p.storeProduct.identifier == PremiumConstants.productMonthly;
          }).firstOrNull;

      if (monthly != null) {
        packages.add(
          BillingPackage(
            identifier: monthly.identifier,
            plan: BillingPlan.monthly,
            storeProductPriceString: monthly.storeProduct.priceString,
            rawPackage: monthly,
          ),
        );
      }

      // Lifetime package
      final lifetime = current.lifetime ??
          current.availablePackages.where((p) {
            return p.packageType == PackageType.lifetime ||
                p.storeProduct.identifier == PremiumConstants.productLifetime;
          }).firstOrNull;

      if (lifetime != null) {
        packages.add(
          BillingPackage(
            identifier: lifetime.identifier,
            plan: BillingPlan.lifetime,
            storeProductPriceString: lifetime.storeProduct.priceString,
            rawPackage: lifetime,
          ),
        );
      }

      return packages;
    } on Object catch (error) {
      _log.warn('Failed to fetch offerings: $error');
      return const <BillingPackage>[];
    }
  }

  @override
  Future<bool> purchase(BillingPackage package) async {
    if (!isAvailable) return false;
    final raw = package.rawPackage;
    if (raw == null) {
      _log.warn(
          'Cannot purchase package without underlying StoreKit/Play package');
      return false;
    }

    try {
      final purchaseResult =
          await Purchases.purchase(PurchaseParams.package(raw));
      _onCustomerInfoUpdate(purchaseResult.customerInfo);
      return _isEntitled;
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        _log.info('Purchase was cancelled by user');
      } else {
        _log.warn('Purchase failed: ${e.message}');
      }
      return false;
    } on Object catch (error) {
      _log.warn('Unexpected purchase error: $error');
      return false;
    }
  }

  @override
  Future<bool> restorePurchases() async {
    if (!isAvailable) return false;
    try {
      final customerInfo = await Purchases.restorePurchases();
      _onCustomerInfoUpdate(customerInfo);
      return _isEntitled;
    } on Object catch (error) {
      _log.warn('Restore purchases failed: $error');
      return false;
    }
  }
}

/// Fake implementation of [BillingGateway] for testing.
final class FakeBillingGateway implements BillingGateway {
  FakeBillingGateway({
    bool isAvailable = true,
    bool initialPremium = false,
    List<BillingPackage>? packages,
  })  : _isAvailable = isAvailable,
        _isPremium = initialPremium,
        _packages = packages ??
            const <BillingPackage>[
              BillingPackage(
                identifier: r'$rc_monthly',
                plan: BillingPlan.monthly,
                storeProductPriceString: r'$0.99',
              ),
              BillingPackage(
                identifier: r'$rc_lifetime',
                plan: BillingPlan.lifetime,
                storeProductPriceString: r'$4.99',
              ),
            ];

  bool _isAvailable;
  bool _isPremium;
  List<BillingPackage> _packages;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  bool purchaseShouldSucceed = true;
  bool restoreShouldSucceed = true;
  int purchaseCalls = 0;
  int restoreCalls = 0;

  @override
  bool get isAvailable => _isAvailable;

  void setAvailable(bool available) {
    _isAvailable = available;
  }

  @override
  Stream<bool> get entitlementStream => _controller.stream;

  void setPremium(bool premium) {
    _isPremium = premium;
    _controller.add(premium);
  }

  void setPackages(List<BillingPackage> packages) {
    _packages = packages;
  }

  @override
  Future<void> initialize() async {
    _controller.add(_isPremium);
  }

  @override
  Future<bool> checkEntitlement() async => _isPremium;

  @override
  Future<List<BillingPackage>> getPackages() async {
    if (!_isAvailable) return const <BillingPackage>[];
    return _packages;
  }

  @override
  Future<bool> purchase(BillingPackage package) async {
    purchaseCalls++;
    if (!_isAvailable || !purchaseShouldSucceed) return false;
    setPremium(true);
    return true;
  }

  @override
  Future<bool> restorePurchases() async {
    restoreCalls++;
    if (!_isAvailable || !restoreShouldSucceed) return false;
    setPremium(true);
    return true;
  }

  void dispose() {
    unawaited(_controller.close());
  }
}
