import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

/// A destination in the connected experience's floating glass tab bar.
@immutable
class LiquidNavDestination {
  const LiquidNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating navigation that behaves like a light sheet above the content.
///
/// Blur is intentionally confined to this piece of structural chrome. Cards
/// stay opaque and readable, while content can still be perceived moving
/// beneath the navigation layer.
class LiquidNavigationBar extends StatelessWidget {
  const LiquidNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<LiquidNavDestination> destinations;

  /// Height of the bar including the inset it floats above.
  ///
  /// The bar is drawn over the content rather than beside it, so the content
  /// has to reserve this much room at its bottom or its last row sits under
  /// the glass. Measured rather than guessed at, because both terms move: the
  /// bar grows with the text setting, and the inset is whatever the phone's
  /// gesture bar or button row asks for.
  static double heightOf(BuildContext context) =>
      _barHeight(context) +
      math.max(MediaQuery.viewPaddingOf(context).bottom, _floatInset);

  static double _barHeight(BuildContext context) =>
      72 * textScaleFactorOf(context).clamp(1.0, 1.5);

  /// How far the bar floats above the bottom edge when the phone asks for less.
  static const double _floatInset = 10;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    // The bar is a fixed-height box holding text, so it has to grow with the
    // user's text setting the way the keycaps do. Clamped, because past this
    // the labels scale down inside instead (see [_LiquidDestination]) rather
    // than the bar eating the screen.
    final height = _barHeight(context);

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, _floatInset),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: (dark ? scheme.surfaceContainer : Colors.white)
                  .withValues(alpha: dark ? 0.78 : 0.72),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: (dark ? Colors.white : Colors.white)
                    .withValues(alpha: dark ? 0.12 : 0.82),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.32 : 0.10),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: SizedBox(
              height: height,
              child: Padding(
                // Keeps the outer destinations clear of the 28-radius corners.
                // Without it the first and last cells reach the rounded edge
                // and the [ClipRRect] takes a bite out of their highlight.
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  // Stretch so the tap target is the full height of the bar,
                  // not just the height of the icon and label stacked.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (var index = 0; index < destinations.length; index++)
                      Expanded(
                        child: _LiquidDestination(
                          destination: destinations[index],
                          selected: selectedIndex == index,
                          onTap: () => onDestinationSelected(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidDestination extends StatelessWidget {
  const _LiquidDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final LiquidNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = context.motion(const Duration(milliseconds: 240));
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Tooltip(
        message: destination.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // The pill wraps the icon alone rather than the whole cell. A
              // cell-wide pill is as wide as its label, so with five tabs the
              // widest one runs into its neighbours and into the edge of the
              // bar; around the icon it is the same shape on every tab.
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                width: 48,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: AnimatedSwitcher(
                  duration: duration,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    key: ValueKey<bool>(selected),
                    size: 22,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Scaled down to fit rather than faded off the end. Five tabs on
              // a 360dp screen leave about 55dp a label, which is narrower
              // than 'Touchpad' and 'Clipboard' render at even before the user
              // asks for larger text, and a half-word names nothing. The box
              // is fixed so the shrinking happens here and never as an
              // overflow in the row above.
              SizedBox(
                height: 16,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opaque, low-elevation surface used for related controls and information.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.margin,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
      ),
    );
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: color ?? scheme.surfaceContainerLow,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSectionCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: scheme.primary),
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
