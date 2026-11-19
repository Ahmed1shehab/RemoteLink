import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../app/app_icons.dart';
import '../app/l10n.dart';
import '../domain/command_process_runner.dart';
import '../domain/command_registry.dart';

Future<String?> _pickExecutable() async => (await openFile())?.path;

class CommandEditor extends StatefulWidget {
  const CommandEditor({
    required this.registry,
    this.pickExecutable = _pickExecutable,
    super.key,
  });

  final CommandRegistry registry;
  final Future<String?> Function() pickExecutable;

  @override
  State<CommandEditor> createState() => _CommandEditorState();
}

class _CommandEditorState extends State<CommandEditor> {
  bool _busy = false;

  Future<void> _edit([RegisteredCommand? command]) => showDialog<void>(
        context: context,
        builder: (context) => _CommandForm(
          registry: widget.registry,
          pickExecutable: widget.pickExecutable,
          command: command,
        ),
      );

  Future<void> _change(Future<void> Function() operation) async {
    setState(() => _busy = true);
    try {
      await operation();
    } on Object {
      if (mounted) _feedback(context.l10n.quickActionsSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(RegisteredCommand command) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.quickActionsRemove),
        content: Text(l10n.quickActionsRemovePrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.removeButton),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _change(() => widget.registry.remove(command.id));
    }
  }

  Future<void> _test(RegisteredCommand command) async {
    setState(() => _busy = true);
    try {
      await startRegisteredCommand(command);
      if (mounted) _feedback(context.l10n.quickActionsStarted);
    } on Object {
      if (mounted) _feedback(context.l10n.quickActionsStartFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _feedback(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StreamBuilder<void>(
      stream: widget.registry.changes,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.registry.loadWarning)
            ListTile(
              leading: const AppIcon(AppIcons.materialWarning),
              title: Text(l10n.quickActionsIntegrityWarning),
            ),
          for (final command in widget.registry.commands)
            Row(
              key: ValueKey(command.id),
              children: [
                Expanded(
                  child: SwitchListTile(
                    value: command.enabled,
                    title: Text(command.name),
                    subtitle: Text(command.enabled
                        ? l10n.quickActionsEnabled
                        : l10n.quickActionsDisabled),
                    onChanged: _busy
                        ? null
                        : (enabled) => _change(
                              () => widget.registry
                                  .setEnabled(command.id, enabled),
                            ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.quickActionsEdit,
                  onPressed: _busy ? null : () => _edit(command),
                  icon: const AppIcon(AppIcons.edit),
                ),
                IconButton(
                  tooltip: l10n.quickActionsTest,
                  onPressed: _busy ? null : () => _test(command),
                  icon: const Icon(Icons.play_arrow_outlined),
                ),
                IconButton(
                  tooltip: l10n.quickActionsRemove,
                  onPressed: _busy ? null : () => _remove(command),
                  icon: const AppIcon(AppIcons.delete),
                ),
                const SizedBox(width: 8),
              ],
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _edit(),
                icon: const Icon(Icons.add),
                label: Text(l10n.quickActionsAdd),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandForm extends StatefulWidget {
  const _CommandForm({
    required this.registry,
    required this.pickExecutable,
    required this.command,
  });

  final CommandRegistry registry;
  final Future<String?> Function() pickExecutable;
  final RegisteredCommand? command;

  @override
  State<_CommandForm> createState() => _CommandFormState();
}

class _CommandFormState extends State<_CommandForm> {
  late final _name = TextEditingController(text: widget.command?.name);
  late final _arguments = TextEditingController(
    text: widget.command?.arguments.join('\n'),
  );
  late final _workingDirectory = TextEditingController(
    text: widget.command?.workingDirectory,
  );
  late String? _executable = widget.command?.executable;
  late PermissionTier _tier =
      widget.command?.minimumTier == PermissionTier.admin
          ? PermissionTier.admin
          : PermissionTier.extended;
  bool _picking = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _arguments.dispose();
    _workingDirectory.dispose();
    super.dispose();
  }

  Future<void> _chooseExecutable() async {
    setState(() => _picking = true);
    try {
      final path = await widget.pickExecutable();
      if (path != null && mounted) {
        setState(() {
          _executable = path;
          _error = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _error = context.l10n.quickActionsPickerFailed);
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final executable = _executable;
    if (executable == null) {
      setState(() => _error = context.l10n.quickActionsValidation);
      return;
    }

    final workingDirectory =
        _workingDirectory.text.trim().isEmpty ? null : _workingDirectory.text;
    final arguments = _arguments.text.isEmpty
        ? const <String>[]
        : _arguments.text.split(RegExp(r'\r?\n'));
    final command = widget.command;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (command == null) {
        await widget.registry.add(
          name: _name.text,
          executable: executable,
          arguments: arguments,
          workingDirectory: workingDirectory,
          minimumTier: _tier,
        );
      } else {
        await widget.registry.update(
          command.id,
          name: _name.text,
          executable: executable,
          arguments: arguments,
          workingDirectory: workingDirectory,
          minimumTier: _tier,
        );
      }
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    } on ArgumentError {
      if (mounted) setState(() => _error = context.l10n.quickActionsValidation);
    } on Object {
      if (mounted) setState(() => _error = context.l10n.quickActionsSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final executable = _executable;
    return AlertDialog(
      title: Text(widget.command == null
          ? l10n.quickActionsAdd
          : l10n.quickActionsEdit),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              enabled: !_saving,
              decoration: InputDecoration(labelText: l10n.quickActionsName),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                onPressed: _picking || _saving ? null : _chooseExecutable,
                child: Text(l10n.quickActionsChooseExecutable),
              ),
            ),
            if (executable != null)
              Text(
                executable,
                // Keep the selected filesystem path together in an RTL form.
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _arguments,
              enabled: !_saving,
              minLines: 2,
              maxLines: 4,
              decoration:
                  InputDecoration(labelText: l10n.quickActionsArguments),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _workingDirectory,
              enabled: !_saving,
              // Filesystem paths use the same reading order in both locales.
              textDirection: TextDirection.ltr,
              decoration:
                  InputDecoration(labelText: l10n.quickActionsWorkingDirectory),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PermissionTier>(
              initialValue: _tier,
              decoration:
                  InputDecoration(labelText: l10n.quickActionsMinimumTier),
              items: [
                DropdownMenuItem(
                  value: PermissionTier.extended,
                  child: Text(l10n.quickActionsTierExtended),
                ),
                DropdownMenuItem(
                  value: PermissionTier.admin,
                  child: Text(l10n.quickActionsTierAdmin),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (tier) {
                      if (tier != null) setState(() => _tier = tier);
                    },
            ),
            if (widget.command?.enabled == true)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(l10n.quickActionsEditDisables),
              ),
            if (_error case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(message,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: _saving || _picking ? null : _save,
          child: Text(l10n.saveButton),
        ),
      ],
    );
  }
}
