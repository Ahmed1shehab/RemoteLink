import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_icons.dart';
import '../../app/l10n.dart';
import '../../app/modern_ui.dart';
import 'billing_gateway.dart';
import 'premium_constants.dart';
import 'premium_providers.dart';

/// Screen presenting the monetization plans and premium upgrade flow.
///
/// Displays two options: Monthly auto-renewing subscription and Lifetime one-time purchase.
/// Prices are fetched dynamically from the app store and formatted locally by StoreKit / Google Play.
/// If billing is unconfigured or offerings cannot be retrieved, fallback prices and an
/// unavailable status are shown gracefully without crashing.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  BillingPlan _selectedPlan = BillingPlan.monthly;
  List<BillingPackage> _packages = const <BillingPackage>[];
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _isRestoring = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadPackages());
    });
  }

  Future<void> _loadPackages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final gateway = ref.read(billingGatewayProvider);
    if (!gateway.isAvailable) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = context.l10n.purchasesUnavailable;
      });
      return;
    }

    try {
      final packages = await gateway.getPackages();
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  BillingPackage? _packageForPlan(BillingPlan plan) {
    for (final pkg in _packages) {
      if (pkg.plan == plan) return pkg;
    }
    return null;
  }

  String _priceForPlan(BillingPlan plan) {
    final pkg = _packageForPlan(plan);
    if (pkg != null && pkg.storeProductPriceString.isNotEmpty) {
      return pkg.storeProductPriceString;
    }
    return plan == BillingPlan.monthly
        ? PremiumConstants.fallbackPriceMonthly
        : PremiumConstants.fallbackPriceLifetime;
  }

  Future<void> _purchase() async {
    final pkg = _packageForPlan(_selectedPlan);
    final gateway = ref.read(billingGatewayProvider);

    if (pkg == null || !gateway.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.purchasesUnavailable)),
      );
      return;
    }

    setState(() => _isPurchasing = true);
    try {
      final success = await gateway.purchase(pkg);
      if (!mounted) return;
      setState(() => _isPurchasing = false);

      if (success) {
        await ref.read(isPremiumProvider.notifier).refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.premiumActiveHeader)),
        );
        Navigator.of(context).pop();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.purchaseFailed(error.toString())),
        ),
      );
    }
  }

  Future<void> _restore() async {
    final gateway = ref.read(billingGatewayProvider);
    if (!gateway.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.purchasesUnavailable)),
      );
      return;
    }

    setState(() => _isRestoring = true);
    try {
      final success = await gateway.restorePurchases();
      if (!mounted) return;
      setState(() => _isRestoring = false);

      if (success) {
        await ref.read(isPremiumProvider.notifier).refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.purchasesRestored)),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.noPurchasesToRestore)),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _isRestoring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.purchaseFailed(error.toString())),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPremium = ref.watch(isPremiumProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.remoteLinkPremium),
        actions: <Widget>[
          if (!isPremium)
            TextButton(
              onPressed: (_isPurchasing || _isRestoring) ? null : _restore,
              child: _isRestoring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.l10n.restorePurchases),
            ),
        ],
      ),
      body: SafeArea(
        child: isPremium
            ? _buildActivePremiumView(context, scheme)
            : _buildPaywallContent(context, scheme),
      ),
      bottomNavigationBar: (!isPremium && _errorMessage == null)
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton(
                onPressed: (_isPurchasing || _isRestoring || _isLoading)
                    ? null
                    : _purchase,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isPurchasing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        context.l10n.continuePurchase,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            )
          : null,
    );
  }

  Widget _buildActivePremiumView(BuildContext context, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                AppIcons.protection,
                color: scheme.primary,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.premiumActiveHeader,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.premiumActiveMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.done),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaywallContent(BuildContext context, ColorScheme scheme) {
    final monthlyPrice = _priceForPlan(BillingPlan.monthly);
    final lifetimePrice = _priceForPlan(BillingPlan.lifetime);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: <Widget>[
        // Header
        Center(
          child: Column(
            children: <Widget>[
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      scheme.primary,
                      scheme.tertiary,
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: AppIcon(
                    AppIcons.protection,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.remoteLinkPremium,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.premiumSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Features list
        AppSectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.whatYouGet,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 14),
              _FeatureRow(
                icon: AppIcons.protection,
                text: context.l10n.featureNoAds,
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: AppIcons.handTap,
                text: context.l10n.featureWatchTrackpad,
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: AppIcons.clipboard,
                text: context.l10n.featureBackgroundClipboard,
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: AppIcons.textSquare,
                text: context.l10n.featureUnlimitedClipboard,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.info_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          )
        else ...<Widget>[
          // Plan Cards
          _PlanCard(
            plan: BillingPlan.lifetime,
            title: context.l10n.planLifetimeTitle,
            subtitle: context.l10n.planLifetimeSubtitle,
            price: lifetimePrice,
            isBestValue: true,
            isSelected: _selectedPlan == BillingPlan.lifetime,
            onTap: () => setState(() => _selectedPlan = BillingPlan.lifetime),
          ),
          const SizedBox(height: 12),
          _PlanCard(
            plan: BillingPlan.monthly,
            title: context.l10n.planMonthlyTitle,
            subtitle: context.l10n.planMonthlySubtitle,
            price: monthlyPrice,
            isBestValue: false,
            isSelected: _selectedPlan == BillingPlan.monthly,
            onTap: () => setState(() => _selectedPlan = BillingPlan.monthly),
          ),
        ],

        const SizedBox(height: 20),

        // Auto-renew disclosure (mandatory for App Store / Play Store subscription policies)
        if (_selectedPlan == BillingPlan.monthly)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              context.l10n.autoRenewDisclosure,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
              textAlign: TextAlign.center,
            ),
          ),

        const SizedBox(height: 16),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final AppIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: AppIcon(icon, size: 16, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.isBestValue,
    required this.isSelected,
    required this.onTap,
  });

  final BillingPlan plan;
  final String title;
  final String subtitle;
  final String price;
  final bool isBestValue;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.08)
              : scheme.surfaceContainerLow,
          border: Border.all(
            color: isSelected
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                      if (isBestValue) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            context.l10n.bestValueBadge,
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? scheme.primary : null,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
