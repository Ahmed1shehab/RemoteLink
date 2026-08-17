import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/motion.dart';
import '../../app/providers.dart';
import '../clipboard/clipboard_controller.dart';
import '../clipboard/clipboard_history_controller.dart';
import '../input/touchpad_screen.dart';
import '../keyboard/keyboard_screen.dart';
import '../media/media_screen.dart';
import '../screen/screen_viewer_screen.dart';
import '../settings/settings_screen.dart';
import '../transfer/transfer_screen.dart';

/// The connected experience: touchpad, keyboard, and clipboard.
///
/// One screen with tabs rather than separate routes, held in an [IndexedStack]
/// so each keeps its state. That matters more than it sounds: rebuilding the
/// keyboard on every switch would drop the text-input connection and dismiss
/// the soft keyboard, and rebuilding the touchpad would reset the pointer's
/// sub-pixel accumulator mid-gesture.
class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Ask for the computer's clipboard on connect, so the first paste after
    // picking up the phone already has the right content rather than waiting
    // for the next copy.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ref.read(clipboardControllerProvider.notifier).requestFromDesktop(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientStateProvider).valueOrNull;
    final quality = ref.watch(connectionQualityProvider).valueOrNull;
    final capabilities =
        ref.watch(clientProvider).valueOrNull?.session?.capabilities;

    // Two conditions, not one. The capability bit says the desk *can* share its
    // screen; it is advertised per server, not per device, so it says nothing
    // about whether this phone is allowed to ask. The tier is what decides
    // that, and a desktop refuses out-of-tier messages in silence by design —
    // so a button gated on the bit alone would be tappable, would send a
    // request, and would sit there receiving nothing.
    final tier = ref.watch(currentPermissionTierProvider).valueOrNull;
    final canViewScreen =
        capabilities?.has(Capabilities.screenCapture) == true &&
            (tier?.canViewScreen ?? false);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          switch (_index) {
            0 => 'Touchpad',
            1 => 'Keyboard',
            2 => 'Media',
            3 => 'Clipboard',
            _ => 'Send',
          },
        ),
        actions: <Widget>[
          if (quality != null && state == ClientState.connected)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '${quality.roundTripMillis.toStringAsFixed(0)} ms',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          if (canViewScreen)
            IconButton(
              icon: const Icon(Icons.screenshot_monitor_outlined),
              tooltip: 'Screen Stream',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ScreenViewerScreen(),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _ConnectionBar(state: state),
        ),
      ),
      body: Column(
        children: <Widget>[
          const SystemStatusStrip(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const <Widget>[
                TouchpadSurfaceView(),
                KeyboardScreen(),
                MediaScreen(),
                ClipboardView(),
                TransferScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.touch_app_outlined),
            selectedIcon: Icon(Icons.touch_app),
            label: 'Touchpad',
          ),
          NavigationDestination(
            icon: Icon(Icons.keyboard_outlined),
            selectedIcon: Icon(Icons.keyboard),
            label: 'Keyboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Media',
          ),
          NavigationDestination(
            icon: Icon(Icons.content_paste_outlined),
            selectedIcon: Icon(Icons.content_paste),
            label: 'Clipboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.send_outlined),
            selectedIcon: Icon(Icons.send),
            label: 'Send',
          ),
        ],
      ),
    );
  }
}

/// Clipboard status and the two manual actions.
///
/// The manual actions exist because automatic phone-to-computer sync is not
/// possible on iOS without a "pasted from" banner on every read. See
/// [MobileClipboardController] for the full reasoning — the short version is
/// that the computer-to-phone direction is automatic and this tab is only for
/// the direction the platform will not let us automate.
class ClipboardView extends ConsumerWidget {
  const ClipboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipboard = ref.watch(clipboardControllerProvider);
    final controller = ref.read(clipboardControllerProvider.notifier);
    final clipboardSettings = ref.watch(clipboardSettingsProvider);
    final connected =
        ref.watch(clientStateProvider).valueOrNull == ClientState.connected;
    final syncEnabled =
        clipboardSettings.syncFromDesktop || clipboardSettings.syncToDesktop;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: SwitchListTile(
            title: const Text('Clipboard sync'),
            subtitle: Text(
              syncEnabled
                  ? 'Syncing with connected computer'
                  : 'Clipboard sync is paused',
            ),
            value: syncEnabled,
            onChanged: (val) => controller.toggleSync(val),
            secondary: const Icon(Icons.sync_alt),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      clipboard.fromDesktop
                          ? Icons.laptop_mac
                          : Icons.smartphone,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      clipboard.text == null
                          ? 'Nothing synced yet'
                          : clipboard.fromDesktop
                              ? 'From your computer'
                              : 'Sent from this phone',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
                if (clipboard.text != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    clipboard.text!,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: connected && syncEnabled && !clipboard.sending
              ? () => controller.sendCurrent()
              : null,
          icon: const Icon(Icons.upload),
          label: const Text('Send this phone’s clipboard'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed:
              connected && syncEnabled ? controller.requestFromDesktop : null,
          icon: const Icon(Icons.download),
          label: const Text('Get the computer’s clipboard'),
        ),
        const SizedBox(height: 24),
        Text(
          'Copying on your computer syncs here automatically.\n\n'
          'The other direction needs a tap: iOS shows a “pasted from” alert '
          'every time an app reads your clipboard, so RemoteLink only reads it '
          'when you open the app or press the button.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        const ClipboardHistoryList(),
      ],
    );
  }
}

/// Recent clipboard items, with pin, delete, and clear-all.
///
/// Tapping a row puts it back on this phone's clipboard. That is the one
/// clipboard operation iOS does not interrupt — *writing* is silent, only
/// reading raises the "pasted from" banner — which is what makes a history
/// list genuinely useful on a phone rather than a nag generator.
class ClipboardHistoryList extends ConsumerWidget {
  const ClipboardHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final snapshot = ref.watch(clipboardHistoryControllerProvider);
    final controller = ref.read(clipboardHistoryControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('History', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (snapshot.entries.isNotEmpty)
              TextButton(
                onPressed: controller.clear,
                child: const Text('Clear all'),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: snapshot.isPersistent,
          onChanged: (value) => _setPersistence(context, controller, value),
          title: const Text('Keep history on this phone'),
          // Both halves matter to someone deciding what to leave in this list,
          // so both are said plainly rather than hidden behind a help link.
          subtitle: Text(
            snapshot.isPersistent
                ? 'Saved on this phone and encrypted with a key held in the '
                    'device keystore.'
                : 'Off — the list is kept in memory and disappears when you '
                    'close RemoteLink.',
          ),
        ),
        const SizedBox(height: 8),
        if (snapshot.entries.isEmpty)
          Text(
            'Nothing yet. The last $kClipboardHistoryCapacity items you copy '
            'or receive will appear here. Anything your password manager '
            'marks confidential is never recorded.',
            style: theme.textTheme.bodySmall,
          )
        else
          for (final entry in snapshot.entries)
            _HistoryTile(entry: entry, controller: controller),
      ],
    );
  }

  Future<void> _setPersistence(
    BuildContext context,
    MobileClipboardHistoryController controller,
    bool enabled,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final applied = await controller.setPersistenceEnabled(enabled: enabled);
    if (!applied) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'This phone’s secure storage is unavailable, so history stays in '
            'memory only.',
          ),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'History will be kept on this phone, encrypted.'
              : 'Saved history deleted. Keeping it in memory only.',
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.controller});

  final ClipboardHistoryEntry entry;
  final MobileClipboardHistoryController controller;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        switch (entry.kind) {
          ClipboardHistoryKind.image => Icons.image_outlined,
          ClipboardHistoryKind.url => Icons.link,
          ClipboardHistoryKind.html => Icons.code,
          ClipboardHistoryKind.text => Icons.notes,
        },
        size: 20,
      ),
      title: Text(
        entry.preview(maxCharacters: 80),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _copy(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: Icon(entry.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            tooltip: entry.pinned ? 'Unpin' : 'Pin',
            onPressed: () => _togglePin(context),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Remove',
            onPressed: () => controller.remove(entry.id),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = await controller.copyToClipboard(entry);
    messenger.showSnackBar(
      SnackBar(
        content: Text(copied ? 'Copied.' : 'That item can’t be copied here.'),
      ),
    );
  }

  void _togglePin(BuildContext context) {
    final wants = !entry.pinned;
    final applied = controller.setPinned(entry.id, pinned: wants);
    if (applied || !wants) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'You can pin up to $kMaxPinnedClipboardEntries items. Unpin one '
          'first.',
        ),
      ),
    );
  }
}

/// A thin line that turns amber while reconnecting.
class _ConnectionBar extends StatelessWidget {
  const _ConnectionBar({required this.state});

  final ClientState? state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, animate, label) = switch (state) {
      ClientState.connected => (scheme.primary, false, 'Connected'),
      ClientState.reconnecting => (scheme.tertiary, true, 'Reconnecting'),
      ClientState.connecting => (scheme.tertiary, true, 'Connecting'),
      ClientState.pairing => (scheme.tertiary, true, 'Pairing'),
      ClientState.failed => (scheme.error, false, 'Connection failed'),
      _ => (scheme.surfaceContainerHighest, false, 'Not connected'),
    };

    // The connection state was carried by this bar's colour and by nothing
    // else — the app bar shows a latency figure only once already connected.
    // Colour alone is not a signal available to every user, so the same fact is
    // stated here in words.
    return Semantics(
      label: 'Connection status: $label',
      liveRegion: true,
      child: SizedBox(
        height: 2,
        child: animate && !context.prefersReducedMotion
            ? LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: scheme.surfaceContainerHighest,
                color: color,
              )
            // Under reduced motion the same information is carried by the
            // colour, held still. An indeterminate bar is a perpetual motion
            // machine two pixels from the top of the screen — small, but it
            // never stops, and it is in peripheral vision the whole session.
            : ColoredBox(color: color, child: const SizedBox.expand()),
      ),
    );
  }
}

/// Host status strip: battery with charging indicator, CPU, RAM, uptime.
///
/// Degrades gracefully: returns [SizedBox.shrink] when disconnected, when no
/// telemetry has arrived, or when the host reports nothing (e.g. an unsupported
/// platform), avoiding an empty row of dashes or zeros.
class SystemStatusStrip extends ConsumerWidget {
  const SystemStatusStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientStateProvider).valueOrNull;
    if (state != ClientState.connected) {
      return const SizedBox.shrink();
    }

    final status = ref.watch(systemStatusProvider).valueOrNull;
    if (status == null) {
      return const SizedBox.shrink();
    }

    final hasBattery = status.batteryPercent != null;
    final hasCpu = status.cpuPercent != null;
    final hasMemory = status.memoryPercent != null;
    final hasUptime = status.uptimeSeconds > 0;

    if (!hasBattery && !hasCpu && !hasMemory && !hasUptime) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCharging = status.isCharging ?? false;

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            if (hasBattery)
              _StatusChip(
                icon: isCharging
                    ? Icons.battery_charging_full
                    : Icons.battery_full,
                iconColor: isCharging
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                label: '${status.batteryPercent}%',
                // Charging is shown by a different glyph and by nothing else.
                semanticLabel: isCharging
                    ? 'Computer battery ${status.batteryPercent} percent, '
                        'charging'
                    : 'Computer battery ${status.batteryPercent} percent',
              ),
            if (hasCpu)
              _StatusChip(
                icon: Icons.memory,
                iconColor: colorScheme.onSurfaceVariant,
                label: 'CPU ${status.cpuPercent!.toStringAsFixed(0)}%',
                semanticLabel: 'Processor '
                    '${status.cpuPercent!.toStringAsFixed(0)} percent',
              ),
            if (hasMemory)
              _StatusChip(
                icon: Icons.pie_chart_outline,
                iconColor: colorScheme.onSurfaceVariant,
                label: 'RAM ${status.memoryPercent!.toStringAsFixed(0)}%',
                semanticLabel: 'Memory '
                    '${status.memoryPercent!.toStringAsFixed(0)} percent',
              ),
            if (hasUptime)
              _StatusChip(
                icon: Icons.schedule,
                iconColor: colorScheme.onSurfaceVariant,
                label: _formatUptime(status.uptimeSeconds),
                semanticLabel: 'Up ${_formatUptime(status.uptimeSeconds)}',
              ),
          ],
        ),
      ),
    );
  }

  static String _formatUptime(int seconds) {
    if (seconds <= 0) return '0s';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (days > 0) {
      return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    }
    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
    if (minutes > 0) {
      return '${minutes}m';
    }
    return '${secs}s';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.semanticLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  /// The chip read out in full.
  ///
  /// The visible labels are abbreviations sized for a strip two lines tall:
  /// '88%' on its own says nothing about what is 88%, and the icon that
  /// supplies the missing noun is announced as nothing.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          // Shrinks rather than overflowing. The strip is a single row of four
          // chips: at a large text size the row was wider than the phone, and
          // an overflowing Row clips its last child — the uptime.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
