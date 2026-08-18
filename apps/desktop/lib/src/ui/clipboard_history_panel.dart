import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';

import '../app/desktop_ui.dart';
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
          title: 'Clipboard history',
          subtitle: 'Quickly reuse recent content from this computer',
          trailing: snapshot.entries.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => _clearAll(context, ref),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: const Text('Clear all'),
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
      const SnackBar(content: Text('Clipboard history cleared.')),
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
            child: Icon(
              isPersistent ? Icons.lock_outline_rounded : Icons.memory_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isPersistent
                  ? 'Kept on this computer, encrypted. Content marked '
                      'confidential by a password manager is never recorded.'
                  : 'Kept in memory only — this list is gone when Remote Link '
                      'quits. Nothing is written to disk.',
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
              ? 'Clipboard history will be kept, encrypted, on this computer.'
              : 'Stored clipboard history deleted. Keeping it in memory only.',
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
    return const DesktopEmptyState(
      icon: Icons.content_paste_search_rounded,
      title: 'Nothing copied yet',
      message: 'The last $kClipboardHistoryCapacity items you copy will '
          'appear here.',
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
        child: Icon(
          switch (entry.kind) {
            ClipboardHistoryKind.image => Icons.image_rounded,
            ClipboardHistoryKind.url => Icons.link_rounded,
            ClipboardHistoryKind.html => Icons.code_rounded,
            ClipboardHistoryKind.text => Icons.notes_rounded,
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
        _relative(entry.copiedAt),
        style: theme.textTheme.bodySmall,
      ),
      // The whole row copies. Pin and delete are explicit buttons because both
      // are easy to hit by accident on a list the user is scanning.
      onTap: () => _recopy(context, ref),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: Icon(entry.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            tooltip: entry.pinned ? 'Unpin' : 'Pin',
            onPressed: () => _togglePin(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Remove from history',
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
        content: Text(copied ? 'Copied.' : 'The clipboard is unavailable.'),
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
        const SnackBar(
          content: Text(
            'You can pin up to $kMaxPinnedClipboardEntries items. Unpin one '
            'first.',
          ),
        ),
      );
    }
  }

  Future<void> _remove(WidgetRef ref) async {
    final history = await ref.read(clipboardHistoryProvider.future);
    history.remove(entry.id);
  }

  static String _relative(DateTime when) {
    final elapsed = DateTime.now().difference(when);
    if (elapsed.inSeconds < 60) return 'Just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours} h ago';
    return '${elapsed.inDays} d ago';
  }
}
