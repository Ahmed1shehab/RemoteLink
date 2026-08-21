import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/brand.dart';
import '../app/providers.dart';
import '../domain/file_launcher.dart';
import 'diagnostics_screen.dart';

/// Everything about the app itself, as opposed to the devices it talks to.
///
/// Split from the diagnostics screen on purpose. Diagnostics answers "why is
/// this not working"; this answers "how do I want it to behave", and mixing the
/// two means a user looking for a switch has to read a page of counters first.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: const <Widget>[
              _AboutHeader(),
              SizedBox(height: 28),
              _StartupSection(),
              SizedBox(height: 24),
              _WindowSection(),
              SizedBox(height: 24),
              _ThisComputerSection(),
              SizedBox(height: 24),
              _SavingSection(),
              SizedBox(height: 24),
              _SupportSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutHeader extends StatelessWidget {
  const _AboutHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        const BrandMark(size: 64),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              kProductName,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              'Version $kAppVersion',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StartupSection extends ConsumerWidget {
  const _StartupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startAtLogin = ref.watch(startAtLoginProvider);

    return _Section(
      title: 'Startup',
      children: <Widget>[
        SwitchListTile(
          value: startAtLogin,
          title: const Text('Start when I log in'),
          subtitle: Text(
            startAtLogin
                ? 'Starts hidden, so your phone can reach this computer '
                    'without anyone opening a window first.'
                : "Your phone will not find this computer until you open "
                    '$kProductName yourself.',
          ),
          secondary: const Icon(Icons.play_circle_outline),
          onChanged: (value) =>
              ref.read(startAtLoginProvider.notifier).set(enabled: value),
        ),
      ],
    );
  }
}

/// Says out loud what the close button does.
///
/// Not decoration: the red button hiding rather than quitting is a deliberate
/// choice that looks exactly like a bug if nobody tells you, and "where did the
/// app go" is the question it produces. Saying it here, next to the switch that
/// controls the other half of the same behaviour, is cheaper than a support
/// thread.
class _WindowSection extends StatelessWidget {
  const _WindowSection();

  @override
  Widget build(BuildContext context) {
    final where = Platform.isMacOS
        ? 'the menu bar at the top of the screen'
        : 'the notification area beside the clock';

    return _Section(
      title: 'Closing the window',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.close_fullscreen_outlined),
          title: const Text('Closing this window keeps the service running'),
          subtitle: Text(
            'Your paired phones stay connected, and transfers in progress '
            'finish. Reopen or quit $kProductName from its icon in $where.',
          ),
        ),
      ],
    );
  }
}

/// Where files your phone sends end up.
///
/// Worth a setting rather than a constant. Downloads is the right default and
/// the wrong answer for plenty of people — anyone whose Downloads folder is a
/// scratch space they empty weekly does not want the photos off their phone
/// landing in it.
class _SavingSection extends ConsumerWidget {
  const _SavingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(downloadDirectoryProvider);

    return _Section(
      title: 'Saving received files',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Folder'),
          subtitle: Text(
            switch (directory) {
              AsyncData<Directory>(:final value) => value.path,
              AsyncError() => 'Could not work out where to save files.',
              _ => 'Checking…',
            },
          ),
          // Tapping the row opens it. Showing someone a path and making them
          // retype it into a file manager is the sort of thing that is only
          // fine until you have done it twice.
          onTap: switch (directory) {
            AsyncData<Directory>(:final value) => () =>
                unawaited(FileLauncher.openFolder(value.path)),
            _ => null,
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextButton(
                onPressed: () => unawaited(_reset(ref)),
                child: const Text('Use Downloads'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => unawaited(_choose(ref)),
                child: const Text('Change…'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _choose(WidgetRef ref) async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Save files here',
    );
    if (path == null) return;
    await ref.read(downloadDirectoryControllerProvider).choose(Directory(path));
  }

  Future<void> _reset(WidgetRef ref) =>
      ref.read(downloadDirectoryControllerProvider).reset();
}

class _ThisComputerSection extends ConsumerWidget {
  const _ThisComputerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(deviceNameProvider);

    return _Section(
      title: 'This computer',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.desktop_windows_outlined),
          title: const Text('Name'),
          subtitle: Text('$name — this is what your phone shows in its list.'),
          trailing: TextButton(
            onPressed: () => _rename(context, ref, name),
            child: const Text('Rename'),
          ),
        ),
      ],
    );
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, String current) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => _RenameComputerDialog(current: current),
    );
    if (chosen == null) return;
    ref.read(deviceNameProvider.notifier).state = chosen;
  }
}

class _RenameComputerDialog extends StatefulWidget {
  const _RenameComputerDialog({required this.current});

  final String current;

  @override
  State<_RenameComputerDialog> createState() => _RenameComputerDialogState();
}

class _RenameComputerDialogState extends State<_RenameComputerDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rename this computer'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => _submit(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      );

  void _submit() {
    final trimmed = _controller.text.trim();
    // An empty name would leave the phone showing a nameless row, which is
    // worse than the hostname it started with.
    if (trimmed.isEmpty) return;
    Navigator.of(context).pop(trimmed);
  }
}

class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) => _Section(
        title: 'Support',
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Diagnostics'),
            subtitle: const Text(
              'Connection counters, permissions, and a log you can copy into '
              'a bug report.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const DiagnosticsScreen(),
              ),
            ),
          ),
        ],
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}
