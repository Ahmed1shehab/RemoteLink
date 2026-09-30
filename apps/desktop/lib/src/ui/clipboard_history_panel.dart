import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';

import '../app/app_icons.dart';
import '../app/desktop_ui.dart';
import '../app/l10n.dart';
import '../app/providers.dart';

/// The last few things copied on this computer.
///
/// ## Why the storage state is on the face of it, not buried in a settings page
///
/// The switch and the line of text under the heading are not decoration. A
/// clipboard history is a list of things the user copied, which is one of the
/// more sensitive lists a computer can hold, and the difference between "this
/// disappears when I quit" and "this is on my disk" changes what a reasonable
/// person is willing to leave in it. Making them find that out somewhere else
/// would mean the answer is usually a guess.
class ClipboardHistoryPanel extends ConsumerWidget {
  const ClipboardHistoryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(clipboardHistoryViewProvider).valueOrNull ??
        ClipboardHistorySnapshot.empty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DesktopSectionHeader(
          title: context.l10n.clipboardHistoryTitle,
          subtitle: context.l10n.clipboardHistorySubtitle,
          trailing: snapshot.entries.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => _clearAll(context, ref),
                  icon: const AppIcon(AppIcons.materialDeleteSweep, size: 18),
                  label: Text(context.l10n.clearAll),
                ),
        ),
        const SizedBox(height: 12),
        _PersistenceRow(isPersistent: snapshot.isPersistent),
        const SizedBox(height: 12),
        if (snapshot.entries.isEmpty)
          _EmptyHistory(isPersistent: snapshot.isPersistent)
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (final entry in snapshot.entries)
                  _HistoryRow(
                    entry: entry,
                    canPinMore:
                        snapshot.pinnedCount < kMaxPinnedClipboardEntries,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final history = await ref.read(clipboardHistoryProvider.future);
    history.clear();
    messenger.showSnackBar(
      SnackBar(content: Text(context.l10n.clipboardCleared)),
    );
  }
}

class _PersistenceRow extends ConsumerWidget {
  const _PersistenceRow({required this.isPersistent});

  final bool isPersistent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AppIcon(
              isPersistent ? AppIcons.materialLock : AppIcons.materialMemory,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isPersistent
                  ? context.l10n.persistenceEncrypted
                  : context.l10n.persistenceMemoryOnly,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: isPersistent,
            onChanged: (value) => _toggle(context, ref, enabled: value),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref, {
    required bool enabled,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    await setClipboardHistoryPersistence(
      history: await ref.read(clipboardHistoryProvider.future),
      directory: await ref.read(appDirectoryProvider.future),
      enabled: enabled,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? context.l10n.persistenceEnabledSnackBar
              : context.l10n.persistenceDisabledSnackBar,
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.isPersistent});

  final bool isPersistent;

  @override
  Widget build(BuildContext context) {
    return DesktopEmptyState(
      icon: AppIcons.materialClipboard,
      title: context.l10n.nothingCopiedYetTitle,
      message: context.l10n.nothingCopiedYetMessage(kClipboardHistoryCapacity),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.entry, required this.canPinMore});

  final ClipboardHistoryEntry entry;
  final bool canPinMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AppIcon(
          switch (entry.kind) {
            ClipboardHistoryKind.image => AppIcons.materialGallery,
            ClipboardHistoryKind.url => AppIcons.materialLink,
            ClipboardHistoryKind.html => AppIcons.materialCode,
            ClipboardHistoryKind.text => AppIcons.paragraph,
          },
          size: 19,
          color: theme.colorScheme.primary,
        ),
      ),
      title: Text(
        entry.preview(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        _relative(context, entry.copiedAt),
        style: theme.textTheme.bodySmall,
      ),
      // The whole row copies. Pin and delete are explicit buttons because both
      // are easy to hit by accident on a list the user is scanning.
      onTap: () => _recopy(context, ref),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: AppIcon(
              entry.pinned ? AppIcons.materialPinFilled : AppIcons.pin,
              size: 18,
              color: entry.pinned ? theme.colorScheme.primary : null,
            ),
            tooltip: entry.pinned ? context.l10n.unpin : context.l10n.pin,
            onPressed: () => _togglePin(context, ref),
          ),
          IconButton(
            icon: const AppIcon(AppIcons.delete, size: 18),
            tooltip: context.l10n.removeFromHistory,
            onPressed: () => _remove(ref),
            color: theme.colorScheme.error,
          ),
        ],
      ),
    );
  }

  Future<void> _recopy(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = await ref.read(clipboardRecopyProvider)(entry);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
            copied ? context.l10n.copied : context.l10n.clipboardUnavailable),
      ),
    );
  }

  Future<void> _togglePin(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final history = await ref.read(clipboardHistoryProvider.future);
    final wants = !entry.pinned;
    final applied = history.setPinned(entry.id, pinned: wants);
    if (!applied && wants) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.pinLimitReached(kMaxPinnedClipboardEntries),
          ),
        ),
      );
    }
  }

  Future<void> _remove(WidgetRef ref) async {
    final history = await ref.read(clipboardHistoryProvider.future);
    history.remove(entry.id);
  }

  static String _relative(BuildContext context, DateTime when) {
    final elapsed = DateTime.now().difference(when);
    if (elapsed.inSeconds < 60) return context.l10n.timeJustNow;
    if (elapsed.inMinutes < 60) {
      return context.l10n.timeMinutesAgo(elapsed.inMinutes);
    }
    if (elapsed.inHours < 24) {
      return context.l10n.timeHoursAgo(elapsed.inHours);
    }
    return context.l10n.timeDaysAgo(elapsed.inDays);
  }
}
