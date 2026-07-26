import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import '../clipboard/clipboard_controller.dart';
import '../input/touchpad_screen.dart';
import '../keyboard/keyboard_screen.dart';
import '../media/media_screen.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          switch (_index) {
            0 => 'Touchpad',
            1 => 'Keyboard',
            2 => 'Media',
            _ => 'Clipboard',
          },
        ),
        actions: <Widget>[
          if (quality != null && state == ClientState.connected)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${quality.roundTripMillis.toStringAsFixed(0)} ms',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _ConnectionBar(state: state),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          TouchpadSurfaceView(),
          KeyboardScreen(),
          MediaScreen(),
          ClipboardView(),
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
    final connected =
        ref.watch(clientStateProvider).valueOrNull == ClientState.connected;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
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
          onPressed: connected && !clipboard.sending
              ? () => controller.sendCurrent()
              : null,
          icon: const Icon(Icons.upload),
          label: const Text('Send this phone’s clipboard'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: connected ? controller.requestFromDesktop : null,
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
      ],
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
    final (color, animate) = switch (state) {
      ClientState.connected => (scheme.primary, false),
      ClientState.reconnecting || ClientState.connecting => (
          scheme.tertiary,
          true,
        ),
      ClientState.failed => (scheme.error, false),
      _ => (scheme.surfaceContainerHighest, false),
    };

    return SizedBox(
      height: 2,
      child: animate
          ? LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: scheme.surfaceContainerHighest,
              color: color,
            )
          : ColoredBox(color: color, child: const SizedBox.expand()),
    );
  }
}
