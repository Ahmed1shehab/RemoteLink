import 'dart:ui';

import 'package:flutter/material.dart';

import 'brand.dart';
import 'motion.dart';

@immutable
class DesktopNavDestination {
  const DesktopNavDestination({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

/// Translucent structural navigation for the desktop workspace.
///
/// The material is reserved for the sidebar so content cards remain opaque,
/// legible, and visually quieter on both macOS and Windows.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
    required this.statusLabel,
    required this.statusColor,
    super.key,
  });

  final int selectedIndex;
  final List<DesktopNavDestination> destinations;
  final ValueChanged<int> onSelected;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: 224,
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
          decoration: BoxDecoration(
            color: (dark ? scheme.surfaceContainerLow : Colors.white)
                .withValues(alpha: dark ? 0.78 : 0.72),
            border: Border(
              right: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: <Widget>[
                    const BrandMark(size: 40),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            kProductName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Desktop',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              for (var index = 0; index < destinations.length; index++) ...[
                _DesktopNavButton(
                  destination: destinations[index],
                  selected: selectedIndex == index,
                  onTap: () => onSelected(index),
                ),
                const SizedBox(height: 5),
              ],
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.28),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        statusLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavButton extends StatelessWidget {
  const _DesktopNavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final DesktopNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Tooltip(
        message: destination.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: context.motion(const Duration(milliseconds: 180)),
              curve: Curves.easeOutCubic,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    destination.icon,
                    size: 20,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact header used when the window is too narrow for a sidebar.
class DesktopCompactHeader extends StatelessWidget {
  const DesktopCompactHeader({
    required this.onDiagnostics,
    required this.onSettings,
    super.key,
  });

  final VoidCallback onDiagnostics;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          const BrandMark(size: 34),
          const SizedBox(width: 10),
          Text(kProductName, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          IconButton(
            onPressed: onDiagnostics,
            icon: const Icon(Icons.monitor_heart_outlined),
            tooltip: 'Diagnostics',
          ),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}

class DesktopSectionHeader extends StatelessWidget {
  const DesktopSectionHeader({
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
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

class DesktopEmptyState extends StatelessWidget {
  const DesktopEmptyState({
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Row(
          children: <Widget>[
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: scheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
