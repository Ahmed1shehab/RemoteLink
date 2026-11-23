import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../../app/app_icons.dart';
import '../../app/l10n.dart';
import 'actions_controller.dart';

class ActionsScreen extends ConsumerWidget {
  const ActionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(actionsCatalogProvider);
    final l10n = context.l10n;
    ref.listen(actionsResultsProvider, (_, next) {
      final result = next.valueOrNull;
      if (result == null) return;
      final message = switch (result.outcome) {
        CommandOutcome.started => l10n.actionsStarted,
        CommandOutcome.refusedUnknown => l10n.actionsRefusedUnknown,
        CommandOutcome.refusedDisabled => l10n.actionsRefusedDisabled,
        CommandOutcome.refusedTier => l10n.actionsRefusedTier,
        CommandOutcome.refusedParameters => l10n.actionsRefusedParameters,
        CommandOutcome.failedToStart => l10n.actionsFailedToStart,
      };
      _showFeedback(context, message);
    });

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.actionsEmpty, textAlign: TextAlign.center),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 66 + 3 * MediaQuery.textScalerOf(context).scale(14),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Tooltip(
          message: entry.name,
          excludeFromSemantics: true,
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: TextButton(
              onPressed: () async {
                final sent =
                    await ref.read(actionsControllerProvider).run(entry.id);
                if (!sent && context.mounted) {
                  _showFeedback(context, context.l10n.actionsSendFailed);
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AppIcon(AppIcons.quickActions),
                  const SizedBox(height: 8),
                  Text(
                    entry.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }
}
