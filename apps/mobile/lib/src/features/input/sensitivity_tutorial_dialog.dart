import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_icons.dart';
import '../../app/providers.dart';
import '../settings/settings_screen.dart';

/// A modal tutorial dialog that explains how to configure pointer sensitivity
/// and touchpad gestures in Settings.
class SensitivityTutorialDialog extends ConsumerWidget {
  const SensitivityTutorialDialog({super.key});

  /// Displays the sensitivity tutorial dialog and marks it as seen once dismissed
  /// or navigated away from.
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const SensitivityTutorialDialog(),
    );
    // Awaited rather than fired and forgotten: the write is what stops the
    // tutorial coming back on the next launch, and a Future dropped here is a
    // failed write nothing would ever report.
    await ref.read(sensitivityTutorialSeenProvider.notifier).markSeen();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pointerSettings = ref.watch(pointerSettingsProvider);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF007ACC).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF007ACC).withValues(alpha: 0.45),
              ),
            ),
            child: const AppIcon(
              AppIcons.settings,
              color: Color(0xFF007ACC),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Pointer Sensitivity',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Customise cursor speed',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Cursor moving too fast or too slow? You can easily fine-tune pointer speed to suit your workflow:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            const _TutorialStep(
              icon: AppIcons.settings,
              title: 'Open Settings',
              description:
                  'Tap the Settings gear icon in the top right corner of the app bar.',
            ),
            const SizedBox(height: 12),
            const _TutorialStep(
              icon: AppIcons.settings,
              title: 'Pointer Sensitivity',
              description:
                  'Under Touchpad, drag the sensitivity slider between 0.5x and 3.5x.',
            ),
            const SizedBox(height: 12),
            const _TutorialStep(
              icon: AppIcons.handTap,
              title: 'Gestures & Scrolling',
              description:
                  'Toggle Natural Scrolling or Tap to Click to match your trackpad habits.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: <Widget>[
                  const AppIcon(
                    AppIcons.settings,
                    size: 18,
                    color: Color(0xFF007ACC),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Current sensitivity: ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${pointerSettings.sensitivity.toStringAsFixed(1)}x',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF007ACC),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
        FilledButton.icon(
          icon: const AppIcon(AppIcons.settings, size: 18),
          label: const Text('Open Settings'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF007ACC),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TutorialStep extends StatelessWidget {
  const _TutorialStep({
    required this.icon,
    required this.title,
    required this.description,
  });

  final AppIconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: AppIcon(
            icon,
            size: 20,
            color: const Color(0xFF007ACC),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
