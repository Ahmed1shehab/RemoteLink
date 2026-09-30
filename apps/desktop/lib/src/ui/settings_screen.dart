import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';

import '../app/app_icons.dart';
import '../app/brand.dart';
import '../app/l10n.dart';
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
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
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
              _ConnectionsSection(),
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                kProductName,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                context.l10n.versionLabel(kAppVersion),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
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
      title: context.l10n.startupSectionTitle,
      children: <Widget>[
        SwitchListTile(
          value: startAtLogin,
          title: Text(context.l10n.startAtLoginTitle),
          subtitle: Text(
            startAtLogin
                ? context.l10n.startAtLoginSubtitleOn
                : context.l10n.startAtLoginSubtitleOff,
          ),
          secondary: const AppIcon(AppIcons.materialMonitorPlay),
          onChanged: (value) =>
              ref.read(startAtLoginProvider.notifier).set(enabled: value),
        ),
      ],
    );
  }
}

/// The one decision about who reaches this computer, and when.
class _ConnectionsSection extends ConsumerWidget {
  const _ConnectionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asks = ref.watch(askBeforeConnectingProvider);

    return _Section(
      title: context.l10n.connectionsSectionTitle,
      children: <Widget>[
        SwitchListTile(
          value: asks,
          title: Text(context.l10n.askBeforeConnectingTitle),
          // Both halves say what actually happens, because the cost of each
          // answer is real and the user is choosing between them rather than
          // between "safe" and "unsafe". Off is a legitimate choice for a
          // computer nobody else can reach.
          subtitle: Text(
            asks
                ? context.l10n.askBeforeConnectingSubtitleOn
                : context.l10n.askBeforeConnectingSubtitleOff,
          ),
          secondary: const AppIcon(AppIcons.materialSettings),
          onChanged: (value) => ref
              .read(askBeforeConnectingProvider.notifier)
              .set(enabled: value),
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
        ? context.l10n.menuBarLocationMac
        : context.l10n.notificationAreaLocationOther;

    return _Section(
      title: context.l10n.windowSectionTitle,
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.close_fullscreen_outlined),
          title: Text(context.l10n.closingWindowKeepsServiceTitle),
          subtitle: Text(
            context.l10n.closingWindowKeepsServiceSubtitle(where),
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
      title: context.l10n.savingSectionTitle,
      children: <Widget>[
        ListTile(
          leading: const AppIcon(AppIcons.materialFiles),
          title: Text(context.l10n.folderLabel),
          subtitle: Text(
            switch (directory) {
              AsyncData<Directory>(:final value) => value.path,
              AsyncError() => context.l10n.saveFolderError,
              _ => context.l10n.saveFolderChecking,
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
                child: Text(context.l10n.useDownloadsButton),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => unawaited(_choose(context, ref)),
                child: Text(context.l10n.changeFolderButton),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final path = await getDirectoryPath(
      confirmButtonText: context.l10n.saveFilesHerePrompt,
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
      title: context.l10n.thisComputerSectionTitle,
      children: <Widget>[
        ListTile(
          leading: const AppIcon(AppIcons.materialMonitorSmartphone),
          title: Text(context.l10n.computerNameLabel),
          subtitle: Text(context.l10n.computerNameSubtitle(name)),
          trailing: TextButton(
            onPressed: () => _rename(context, ref, name),
            child: Text(context.l10n.renameButton),
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
    final sanitised = sanitiseDeviceName(chosen);
    if (sanitised == null) return;
    ref.read(deviceNameProvider.notifier).state = sanitised;
    final service = ref.read(desktopServiceProvider).valueOrNull;
    if (service != null) await service.announceOwnName(sanitised);
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
        title: Text(context.l10n.renameComputerDialogTitle),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration:
              InputDecoration(labelText: context.l10n.computerNameLabel),
          onSubmitted: (_) => _submit(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancelButton),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(context.l10n.saveButton),
          ),
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
        title: context.l10n.supportSectionTitle,
        children: <Widget>[
          ListTile(
            leading: const AppIcon(AppIcons.analytics),
            title: Text(context.l10n.diagnosticsTitle),
            subtitle: Text(context.l10n.diagnosticsSubtitle),
            trailing: const AppIcon(AppIcons.materialChevronRight),
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
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
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
