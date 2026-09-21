import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/app_icons.dart';
import '../../app/modern_ui.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../clipboard/clipboard_controller.dart';
import '../clipboard/clipboard_history_controller.dart';
import '../host/host_providers.dart';
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

/// The five things this screen can be.
///
/// An enum rather than an index, because which of them are on screen now
/// depends on the peer. A phone that connected to another phone can exchange
/// files and text and nothing else — there is no cursor over there to move —
/// so the tabs are filtered, and an `int` index into a filtered list means the
/// selected tab silently changes identity when the list does.
enum ControlTab {
  touchpad(Capabilities.mouse),
  keyboard(Capabilities.keyboard),
  media(Capabilities.mediaControl),
  clipboard(Capabilities.clipboardText),
  send(Capabilities.fileTransfer);

  const ControlTab(this.capability);

  /// The bit that has to be in the session for this tab to be worth showing.
  final int capability;

  /// Whether the surface *is* a gesture, and so wants the whole screen.
  ///
  /// Expanding a list of clipboard entries to fill the screen achieves
  /// nothing, and a control that does nothing on four tabs out of five is
  /// worse than a missing one.
  bool get isGesture => this == ControlTab.touchpad;
}

/// Which tabs a session with these capabilities can actually offer.
///
/// Unknown capabilities mean everything, not nothing. `session` is null for the
/// moment between the screen appearing and the handshake being read, and hiding
/// four tabs during it would be a visible flicker on every connection, to
/// pre-empt a case that only arises on a phone-to-phone link.
///
/// A pure function, and public for the same reason [mobileCapabilities] is:
/// the rule is worth a test, and a test of it should not need a provider
/// container, a keystore and a socket to reach it.
@visibleForTesting
List<ControlTab> visibleTabs(Capabilities? capabilities) => <ControlTab>[
      for (final tab in ControlTab.values)
        if (capabilities == null || capabilities.has(tab.capability)) tab,
    ];

class _ControlScreenState extends ConsumerState<ControlScreen> {
  ControlTab? _selected;

  /// Whether the gesture surface has been given the whole screen.
  ///
  /// Off by default: the tab bar is how the other four features are reached,
  /// and a control that hides it has to be the user's choice rather than the
  /// state they find the app in.
  bool _immersive = false;

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
    final scheme = Theme.of(context).colorScheme;
    final rawState = ref.watch(clientStateProvider).valueOrNull;
    final hasActivePeer = ref.watch(peerLinksProvider).isNotEmpty;
    final state =
        hasActivePeer && (rawState == null || rawState == ClientState.idle)
            ? ClientState.connected
            : rawState;
    final capabilities = ref.watch(activeCapabilitiesProvider);

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

    final tabs = visibleTabs(capabilities);
    // A peer that offers none of them is not a state the app can be in — the
    // handshake requires a shared protocol version and every build since the
    // first has had a clipboard — but falling back to the full list beats a
    // screen with no body at all if it ever happens.
    final visible = tabs.isEmpty ? ControlTab.values : tabs;
    // The chosen tab, unless the peer cannot offer it. Connecting to a phone
    // while the touchpad was the last thing open must not leave the selection
    // pointing at a tab that is not there.
    final current = _selected != null && visible.contains(_selected)
        ? _selected!
        : visible.first;
    final onGestureTab = current.isGesture;

    final expanded = _immersive && onGestureTab;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        // The expand control, where a back button would be. Only on the tabs
        // it means something on — see [_gestureTabs].
        leading: onGestureTab
            ? IconButton(
                icon: const AppIcon(
                  AppIcons.zoomOut,
                  size: 18,
                ),
                tooltip: expanded
                    ? 'Show the tabs again'
                    : 'Expand the gesture area',
                onPressed: () => setState(() => _immersive = !_immersive),
              )
            : null,
        // The connection state, in words, where the tab name used to be. Which
        // tab is open is already answered by the tab bar and by what fills the
        // screen; whether the computer is still on the other end is not
        // answered anywhere else, and it is the thing a user checks when a
        // gesture does nothing.
        //
        // What was here before this was a round-trip figure in milliseconds.
        // It was removed rather than moved: a number that changes several times
        // a second, in the corner of a screen someone is staring at while
        // aiming a cursor, is a distraction that reports nothing actionable —
        // the same fact, "the link is healthy", is carried by the bar below.
        title: _ConnectionTitle(state: state),
        actions: <Widget>[
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
            icon: AppIcon(
              AppIcons.settings,
              color: scheme.onSurfaceVariant,
            ),
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
          // Collapsed on a gesture tab, and animated rather than switched, so
          // the extra height reads as the surface growing into it. The strip is
          // reference information — the computer's battery, load and uptime —
          // and on a tab that is one large touch target it is thirty pixels of
          // text nobody is reading taken off the area the thumb works in.
          AnimatedSize(
            duration: context.motion(const Duration(milliseconds: 260)),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: onGestureTab
                ? const SizedBox(width: double.infinity)
                : const SystemStatusStrip(),
          ),
          Expanded(
            child: AnimatedPadding(
              duration: context.motion(const Duration(milliseconds: 260)),
              curve: Curves.easeOutCubic,
              // The navigation floats over the body, so the body keeps its
              // own bottom clear by exactly the room the bar takes — and
              // reclaims all of it when the bar is gone.
              padding: EdgeInsets.only(
                bottom: expanded ? 0 : LiquidNavigationBar.heightOf(context),
              ),
              // Still an [IndexedStack] over the visible tabs, so each keeps
              // its state — see the class comment for what rebuilding them
              // costs.
              child: IndexedStack(
                index: visible.indexOf(current),
                children: <Widget>[
                  for (final tab in visible)
                    switch (tab) {
                      ControlTab.touchpad =>
                        TouchpadSurfaceView(immersive: expanded),
                      ControlTab.keyboard => const KeyboardScreen(),
                      ControlTab.media => const MediaScreen(),
                      ControlTab.clipboard => const ClipboardView(),
                      ControlTab.send => const TransferScreen(),
                    },
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: expanded
          ? null
          : LiquidNavigationBar(
              selectedIndex: visible.indexOf(current),
              onDestinationSelected: (index) =>
                  setState(() => _selected = visible[index]),
              destinations: <LiquidNavDestination>[
                for (final tab in visible) _destinationFor(tab),
              ],
            ),
    );
  }

  static LiquidNavDestination _destinationFor(ControlTab tab) => switch (tab) {
        ControlTab.touchpad => const LiquidNavDestination(
            icon: AppIcons.handTap,
            selectedIcon: AppIcons.handTap,
            label: 'Touchpad',
          ),
        ControlTab.keyboard => const LiquidNavDestination(
            icon: AppIcons.keyboard,
            selectedIcon: AppIcons.keyboard,
            label: 'Keyboard',
          ),
        ControlTab.media => const LiquidNavDestination(
            icon: AppIcons.monitorPlay,
            selectedIcon: AppIcons.monitorPlay,
            label: 'Media',
          ),
        ControlTab.clipboard => const LiquidNavDestination(
            icon: AppIcons.clipboard,
            selectedIcon: AppIcons.clipboard,
            label: 'Clipboard',
          ),
        ControlTab.send => const LiquidNavDestination(
            icon: AppIcons.send,
            selectedIcon: AppIcons.send,
            label: 'Send',
          ),
      };
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
        ref.watch(clientStateProvider).valueOrNull == ClientState.connected ||
            ref.watch(peerLinksProvider).isNotEmpty;
    final syncEnabled =
        clipboardSettings.syncFromDesktop || clipboardSettings.syncToDesktop;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        AppSectionCard(
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: AppIcon(AppIcons.files, color: scheme.primary),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Clipboard sync',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      syncEnabled ? 'Connected and active' : 'Sync is paused',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: syncEnabled,
                onChanged: controller.toggleSync,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  AppIcon(
                    clipboard.fromDesktop
                        ? AppIcons.materialMonitorSmartphone
                        : AppIcons.materialMonitorSmartphone,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      clipboard.text == null
                          ? 'Ready to sync'
                          : clipboard.fromDesktop
                              ? 'From ${clipboard.sourceName ?? 'your computer'}'
                              : 'From this phone',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 76),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  clipboard.text ??
                      'Your latest clipboard item will appear here.',
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: clipboard.text == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: connected && syncEnabled && !clipboard.sending
                          ? () => controller.sendCurrent()
                          : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                      label: const Text('Send'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: connected && syncEnabled
                          ? controller.requestFromDesktop
                          : null,
                      icon: const Icon(Icons.arrow_downward_rounded),
                      label: const Text('Get'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
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
    final snapshot = ref.watch(clipboardHistoryControllerProvider);
    final controller = ref.read(clipboardHistoryControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppSectionTitle(
          title: 'History',
          subtitle: 'Tap an item to copy it again',
          trailing: snapshot.entries.isNotEmpty
              ? TextButton(
                  onPressed: controller.clear,
                  child: const Text('Clear all'),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (snapshot.entries.isEmpty)
          const AppEmptyState(
            icon: AppIcons.materialSettings,
            title: 'Nothing copied yet',
            message: 'Recent items appear here. Anything your password manager '
                'marks confidential is never recorded.',
          )
        else
          for (final entry in snapshot.entries)
            _HistoryTile(entry: entry, controller: controller),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.controller});

  final ClipboardHistoryEntry entry;
  final MobileClipboardHistoryController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSectionCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      child: ListTile(
        minTileHeight: 68,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Transform.scale(
            scale: entry.kind == ClipboardHistoryKind.text ? 0.6 : 1,
            child: AppIcon(
              switch (entry.kind) {
                ClipboardHistoryKind.image => AppIcons.gallery,
                ClipboardHistoryKind.url => AppIcons.materialSettings,
                ClipboardHistoryKind.html => AppIcons.materialSettings,
                ClipboardHistoryKind.text => AppIcons.paragraph,
              },
              size: 20,
              color: scheme.primary,
            ),
          ),
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
              icon: AppIcon(
                entry.pinned
                    ? AppIcons.materialPinFilled
                    : AppIcons.materialPin,
                size: 18,
                color: entry.pinned ? scheme.primary : scheme.onSurfaceVariant,
              ),
              tooltip: entry.pinned ? 'Unpin' : 'Pin',
              onPressed: () => _togglePin(context),
            ),
            IconButton(
              icon: AppIcon(
                AppIcons.delete,
                size: 18,
                color: scheme.error,
              ),
              tooltip: 'Remove',
              onPressed: () {
                final removed = controller.remove(entry.id);
                if (removed == null) return;
                showBottomUndoSnackBar(
                  context,
                  message: 'Deleted from history',
                  onUndo: () => controller.restore(removed),
                );
              },
            ),
          ],
        ),
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

/// The connection state as a dot and a word, centred in the app bar.
///
/// The dot alone would be quicker to read and is not enough on its own —
/// colour is not information every user receives — so the word carries it and
/// the dot is what makes it glanceable. Both come from the same switch, which
/// is what keeps them from disagreeing.
class _ConnectionTitle extends StatelessWidget {
  const _ConnectionTitle({required this.state});

  final ClientState? state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (state) {
      ClientState.connected => (const Color(0xFF3DD68C), 'Connected'),
      ClientState.reconnecting => (scheme.tertiary, 'Reconnecting'),
      ClientState.connecting => (scheme.tertiary, 'Connecting'),
      ClientState.pairing => (scheme.tertiary, 'Pairing'),
      ClientState.awaitingApproval => (scheme.tertiary, 'Waiting to be let in'),
      ClientState.failed => (scheme.error, 'Connection failed'),
      _ => (scheme.outline, 'Not connected'),
    };

    return Semantics(
      liveRegion: true,
      label: 'Connection status: $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          // Shrinks rather than overflowing: 'Connection failed' at a large
          // text setting is wider than what an app bar leaves between two
          // icon buttons, and an overflowing title is a title with no end.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
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
      ClientState.awaitingApproval => (
          scheme.tertiary,
          true,
          'Waiting to be let in'
        ),
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
                icon: Icon(
                  isCharging ? Icons.battery_charging_full : Icons.battery_full,
                ),
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
                icon: const Icon(Icons.memory),
                iconColor: colorScheme.onSurfaceVariant,
                label: 'CPU ${status.cpuPercent!.toStringAsFixed(0)}%',
                semanticLabel: 'Processor '
                    '${status.cpuPercent!.toStringAsFixed(0)} percent',
              ),
            if (hasMemory)
              _StatusChip(
                icon: const Icon(Icons.pie_chart_outline),
                iconColor: colorScheme.onSurfaceVariant,
                label: 'RAM ${status.memoryPercent!.toStringAsFixed(0)}%',
                semanticLabel: 'Memory '
                    '${status.memoryPercent!.toStringAsFixed(0)} percent',
              ),
            if (hasUptime)
              _StatusChip(
                icon: const Icon(Icons.schedule),
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

  final Widget icon;
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
          IconTheme.merge(
            data: IconThemeData(size: 14, color: iconColor),
            child: icon,
          ),
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
