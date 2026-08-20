import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/brand.dart';
import '../../app/providers.dart';
import '../devices/bonjour_discovery.dart';

/// Settings screen for configuring device identity, managing paired computers,
/// adjusting touchpad and clipboard preferences, inspecting diagnostics, and
/// viewing app licenses.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: const <Widget>[
          _ThisPhoneSection(),
          SizedBox(height: 16),
          _PairedComputersSection(),
          SizedBox(height: 16),
          _TouchpadSection(),
          SizedBox(height: 16),
          _ClipboardSection(),
          SizedBox(height: 16),
          _DiagnosticsSection(),
          SizedBox(height: 16),
          _AboutSection(),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. THIS PHONE
// ---------------------------------------------------------------------------

class _ThisPhoneSection extends ConsumerWidget {
  const _ThisPhoneSection();

  static String _formatFingerprint(Uint8List key) {
    if (key.isEmpty) return 'None';
    final prefix = key.length >= 8 ? key.sublist(0, 8) : key;
    return prefix
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final phoneName = ref.watch(deviceNameProvider);
    final identityAsync = ref.watch(identityProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: Icons.smartphone,
              title: 'This Phone',
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Device name'),
              subtitle: Text(
                phoneName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Rename this phone',
                onPressed: () => _promptRenamePhone(context, ref, phoneName),
              ),
            ),
            const Divider(height: 16),
            identityAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (err, _) => Text(
                'Could not load device identity: $err',
                style: TextStyle(color: colorScheme.error),
              ),
              data: (identity) {
                final fingerprint = _formatFingerprint(identity.publicKey);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Device ID',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      identity.id.value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Public-key fingerprint',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      fingerprint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptRenamePhone(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _RenamePhoneDialog(currentName: currentName),
    );
  }
}

class _RenamePhoneDialog extends ConsumerStatefulWidget {
  const _RenamePhoneDialog({required this.currentName});

  final String currentName;

  @override
  ConsumerState<_RenamePhoneDialog> createState() => _RenamePhoneDialogState();
}

class _RenamePhoneDialogState extends ConsumerState<_RenamePhoneDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _controller.text;
    final error =
        await ref.read(deviceNameProvider.notifier).setDeviceName(raw);
    if (!mounted) return;

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rename this phone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Phone name',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('Save'),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// 2. PAIRED COMPUTERS
// ---------------------------------------------------------------------------

class _PairedComputersSection extends ConsumerWidget {
  const _PairedComputersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final peersAsync = ref.watch(trustedPeersProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: Icons.devices,
              title: 'Paired Computers',
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            peersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (err, _) => Text(
                'Could not load paired computers: $err',
                style: TextStyle(color: colorScheme.error),
              ),
              data: (peers) {
                if (peers.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No paired computers yet. Pair with a computer on your '
                      'Wi-Fi network to start.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }

                return Column(
                  children: <Widget>[
                    for (var i = 0; i < peers.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 16),
                      _PairedComputerTile(peer: peers[i]),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PairedComputerTile extends ConsumerWidget {
  const _PairedComputerTile({required this.peer});

  final TrustedPeer peer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final platformIcon = switch (peer.platform) {
      PlatformKind.macos => Icons.laptop_mac,
      PlatformKind.windows => Icons.laptop_windows,
      PlatformKind.linux => Icons.computer,
      _ => Icons.computer,
    };

    final tier = PermissionTier.fromWire(peer.permissionTier);
    final tierLabel = switch (tier) {
      PermissionTier.readOnly => 'View Only',
      PermissionTier.standard => 'Standard',
      PermissionTier.extended => 'Extended',
      PermissionTier.admin => 'Admin',
    };

    final addressText = peer.lastAddress != null
        ? 'Last seen: ${peer.lastAddress} · Tier: $tierLabel'
        : 'No address recorded · Tier: $tierLabel';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(platformIcon, color: colorScheme.primary, size: 28),
      title: Text(
        peer.name,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        addressText,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Permissions for ${peer.name}',
            onPressed: () => _requestPermission(context, ref, peer),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename ${peer.name}',
            onPressed: () => _renameComputer(context, ref, peer),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: colorScheme.error),
            tooltip: 'Forget ${peer.name}',
            onPressed: () => _confirmForgetComputer(context, ref, peer),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPermission(
    BuildContext context,
    WidgetRef ref,
    TrustedPeer peer,
  ) async {
    final liveTier = ref.read(currentPermissionTierProvider).valueOrNull;
    final currentTier =
        liveTier ?? PermissionTier.fromWire(peer.permissionTier);

    await showDialog<void>(
      context: context,
      builder: (context) => _RequestPermissionDialog(
        peer: peer,
        currentTier: currentTier,
      ),
    );
  }

  Future<void> _renameComputer(
    BuildContext context,
    WidgetRef ref,
    TrustedPeer peer,
  ) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _RenameComputerDialog(initialName: peer.name),
    );
    if (newName == null || !context.mounted) return;

    final trustStore = await ref.read(trustStoreProvider.future);
    await trustStore.upsert(peer.copyWith(name: newName));
    await persistTrustStore(
      trustStore,
      await ref.read(identityStoreProvider.future),
    );
    ref.invalidate(trustedPeersProvider);

    final client = ref.read(clientProvider).valueOrNull;
    if (client != null && client.isConnected) {
      if (client.session?.peerId == peer.id ||
          client.target?.deviceId == peer.id) {
        try {
          await client.session?.send(DeviceRename(newName));
        } on TransportError {
          // Ignore if teardown.
        }
      }
    }
  }

  Future<void> _confirmForgetComputer(
    BuildContext context,
    WidgetRef ref,
    TrustedPeer peer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${peer.name}?'),
        content: const Text(
          'This will remove this computer from your trusted list. You will '
          'need to pair again to reconnect.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final trustStore = await ref.read(trustStoreProvider.future);
    await trustStore.forget(peer.id);
    await persistTrustStore(
      trustStore,
      await ref.read(identityStoreProvider.future),
    );
    ref.invalidate(trustedPeersProvider);

    final client = ref.read(clientProvider).valueOrNull;
    if (client != null &&
        client.isConnected &&
        (client.session?.peerId == peer.id ||
            client.target?.deviceId == peer.id)) {
      await client.disconnect();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Forgot ${peer.name}')),
      );
    }
  }
}

class _RenameComputerDialog extends StatefulWidget {
  const _RenameComputerDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameComputerDialog> createState() => _RenameComputerDialogState();
}

class _RenameComputerDialogState extends State<_RenameComputerDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text;
    final sanitised = sanitiseDeviceName(raw);
    if (sanitised == null) {
      setState(() {
        _error =
            'Invalid name: 1–64 characters, no control codes or line breaks.';
      });
      return;
    }
    Navigator.of(context).pop(sanitised);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rename computer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Computer name',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('Save'),
          ),
        ],
      );
}

class _RequestPermissionDialog extends ConsumerStatefulWidget {
  const _RequestPermissionDialog({
    required this.peer,
    required this.currentTier,
  });

  final TrustedPeer peer;
  final PermissionTier currentTier;

  @override
  ConsumerState<_RequestPermissionDialog> createState() =>
      _RequestPermissionDialogState();
}

class _RequestPermissionDialogState
    extends ConsumerState<_RequestPermissionDialog> {
  late PermissionTier _selectedTier;
  final TextEditingController _justificationController =
      TextEditingController();
  bool _isSending = false;

  static String _tierTitle(PermissionTier tier) => switch (tier) {
        PermissionTier.readOnly => 'View Only',
        PermissionTier.standard => 'Standard',
        PermissionTier.extended => 'Extended',
        PermissionTier.admin => 'Admin',
      };

  static String _tierDescription(PermissionTier tier) => switch (tier) {
        PermissionTier.readOnly =>
          'Allows viewing system status, media state, and screen stream.',
        PermissionTier.standard =>
          'Allows sending keyboard and mouse input, synchronizing clipboard, '
              'controlling media, viewing this screen, and transferring files.',
        PermissionTier.extended =>
          'Allows launching applications and running pre-registered commands.',
        PermissionTier.admin =>
          'Allows controlling power (shutdown, restart, sleep, lock) and managing paired devices.',
      };

  @override
  void initState() {
    super.initState();
    _selectedTier = switch (widget.currentTier) {
      PermissionTier.readOnly => PermissionTier.standard,
      PermissionTier.standard => PermissionTier.extended,
      PermissionTier.extended => PermissionTier.admin,
      PermissionTier.admin => PermissionTier.admin,
    };
  }

  @override
  void dispose() {
    _justificationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final client = ref.read(clientProvider).valueOrNull;
    if (client == null || !client.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connect to ${widget.peer.name} to request permission elevation.',
          ),
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSending = true);
    final rawJustification = _justificationController.text.trim();
    final justification = rawJustification.isEmpty ? null : rawJustification;

    try {
      await client.session?.send(
        PermissionRequest(
          tier: _selectedTier,
          justification: justification,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Permission request sent to ${widget.peer.name}.'),
        ),
      );
    } on TransportError {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send permission request.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Text('Permissions · ${widget.peer.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Current Permission Tier',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _tierTitle(widget.currentTier),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _tierDescription(widget.currentTier),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Request Higher Tier',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PermissionTier>(
              initialValue: _selectedTier,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: PermissionTier.values
                  .map(
                    (tier) => DropdownMenuItem<PermissionTier>(
                      value: tier,
                      child: Text(_tierTitle(tier)),
                    ),
                  )
                  .toList(),
              onChanged: (tier) {
                if (tier != null) {
                  setState(() => _selectedTier = tier);
                }
              },
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(50),
                border: Border.all(color: colorScheme.primary.withAlpha(80)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'What ${_tierTitle(_selectedTier)} allows:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tierDescription(_selectedTier),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _justificationController,
              decoration: const InputDecoration(
                labelText: 'Reason / Justification (optional)',
                hintText: 'e.g. Need to transfer files',
                border: OutlineInputBorder(),
              ),
              maxLength: 256,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSending ? null : _submit,
          child: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Request Elevation'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. TOUCHPAD
// ---------------------------------------------------------------------------

class _TouchpadSection extends ConsumerWidget {
  const _TouchpadSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pointerSettings = ref.watch(pointerSettingsProvider);
    final notifier = ref.read(pointerSettingsProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: Icons.touch_app,
              title: 'Touchpad',
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Pointer sensitivity',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${pointerSettings.sensitivity.toStringAsFixed(1)}x',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              value: pointerSettings.sensitivity.clamp(0.5, 3.5),
              min: 0.5,
              max: 3.5,
              divisions: 30,
              label: '${pointerSettings.sensitivity.toStringAsFixed(1)}x',
              onChanged: (value) => notifier.setSensitivity(value),
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Natural scrolling'),
              subtitle: const Text('Content direction matches finger movement'),
              value: pointerSettings.naturalScrolling,
              onChanged: (val) => notifier.setNaturalScrolling(val),
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tap to click'),
              subtitle: const Text(
                'One finger left-clicks, two fingers right-click',
              ),
              value: pointerSettings.tapToClick,
              onChanged: (val) => notifier.setTapToClick(val),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. CLIPBOARD
// ---------------------------------------------------------------------------

class _ClipboardSection extends ConsumerWidget {
  const _ClipboardSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final clipboardSettings = ref.watch(clipboardSettingsProvider);
    final notifier = ref.read(clipboardSettingsProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: Icons.content_paste,
              title: 'Clipboard',
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sync from computer'),
              subtitle: const Text(
                'Automatically receive clipboard copied on your computer',
              ),
              value: clipboardSettings.syncFromDesktop,
              onChanged: (val) => notifier.setSyncFromDesktop(val),
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sync to computer'),
              subtitle: const Text(
                'Send phone clipboard when opening app or pressing Send',
              ),
              value: clipboardSettings.syncToDesktop,
              onChanged: (val) => notifier.setSyncToDesktop(val),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Why is phone-to-computer manual on iOS?\n'
                      'Reading the pasteboard on iOS shows a system “pasted from” '
                      'banner every time an app reads your clipboard. To prevent '
                      'constant banner alerts, Remote Link does not poll continuously '
                      '— it only reads the clipboard when you switch to the app '
                      'or press the Send button.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. DIAGNOSTICS
// ---------------------------------------------------------------------------

class _DiagnosticsSection extends ConsumerStatefulWidget {
  const _DiagnosticsSection();

  @override
  ConsumerState<_DiagnosticsSection> createState() =>
      _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends ConsumerState<_DiagnosticsSection> {
  LogLevel? _selectedLevel;

  String _formatRoute(
    DiscoveryBackend? discovery,
    ConnectionTarget? target,
    bool isConnected,
  ) {
    if (!isConnected || target == null) {
      return 'Not connected';
    }

    if (discovery is CompositeDiscoveryBackend) {
      bool inBonjour = false;
      bool inUdp = false;
      for (final backend in discovery.backends) {
        final found = backend.current.any((d) =>
            (target.deviceId != null && d.id == target.deviceId) ||
            d.address == target.host);
        if (found) {
          if (backend is BonjourDiscoveryBackend) {
            inBonjour = true;
          } else {
            inUdp = true;
          }
        }
      }
      if (inBonjour && inUdp) return 'Bonjour & UDP beacon';
      if (inBonjour) return 'Bonjour (mDNS / DNS-SD)';
      if (inUdp) return 'UDP beacon (Multicast)';
    } else if (discovery is BonjourDiscoveryBackend) {
      if (discovery.current.any((d) =>
          (target.deviceId != null && d.id == target.deviceId) ||
          d.address == target.host)) {
        return 'Bonjour (mDNS / DNS-SD)';
      }
    } else if (discovery != null) {
      if (discovery.current.any((d) =>
          (target.deviceId != null && d.id == target.deviceId) ||
          d.address == target.host)) {
        return 'UDP beacon (Multicast)';
      }
    }

    return 'Manual address / Stored';
  }

  void _exportLogs(BuildContext context, List<LogRecord> records) {
    final filtered = _selectedLevel == null
        ? records
        : records
            .where((r) => r.level.severity >= _selectedLevel!.severity)
            .toList();

    final buffer = StringBuffer()
      ..writeln('=== Remote Link Mobile Diagnostics Logs ===')
      ..writeln('Generated: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('Total records: ${filtered.length}')
      ..writeln();

    for (final record in filtered) {
      buffer.writeln(record.toString());
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Copied ${filtered.length} log records to clipboard'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final client = ref.watch(clientProvider).valueOrNull;
    final clientState = ref.watch(clientStateProvider).valueOrNull ??
        client?.state ??
        ClientState.idle;
    final quality = ref.watch(connectionQualityProvider).valueOrNull;
    final discovery = ref.watch(discoveryProvider).valueOrNull;
    final memorySink = ref.watch(memoryLogSinkProvider);

    final isConnected = clientState == ClientState.connected;
    final rttText = isConnected && quality != null
        ? '${quality.roundTripMillis.toStringAsFixed(0)} ms'
        : isConnected
            ? 'Measuring…'
            : 'Not connected';

    final discoveryRoute = _formatRoute(discovery, client?.target, isConnected);

    final stateLabel = switch (clientState) {
      ClientState.connected => 'Connected',
      ClientState.connecting => 'Connecting…',
      ClientState.reconnecting => 'Reconnecting…',
      ClientState.pairing => 'Pairing…',
      ClientState.failed => 'Connection failed',
      ClientState.idle => 'Idle (Not connected)',
    };

    final stateColor = switch (clientState) {
      ClientState.connected => colorScheme.primary,
      ClientState.connecting ||
      ClientState.reconnecting =>
        colorScheme.tertiary,
      ClientState.failed => colorScheme.error,
      _ => colorScheme.onSurfaceVariant,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: Icons.analytics_outlined,
              title: 'Diagnostics',
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            _DiagnosticRow(
              label: 'Connection state',
              value: stateLabel,
              valueColor: stateColor,
            ),
            const SizedBox(height: 8),
            _DiagnosticRow(
              label: 'Round-trip time',
              value: rttText,
            ),
            const SizedBox(height: 8),
            _DiagnosticRow(
              label: 'Discovery route',
              value: discoveryRoute,
            ),
            const Divider(height: 24),
            Row(
              children: <Widget>[
                Text(
                  'Log filter:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<LogLevel?>(
                  value: _selectedLevel,
                  underline: const SizedBox.shrink(),
                  onChanged: (level) => setState(() => _selectedLevel = level),
                  items: const <DropdownMenuItem<LogLevel?>>[
                    DropdownMenuItem<LogLevel?>(
                      value: null,
                      child: Text('All Levels'),
                    ),
                    DropdownMenuItem<LogLevel?>(
                      value: LogLevel.debug,
                      child: Text('Debug (≥ debug)'),
                    ),
                    DropdownMenuItem<LogLevel?>(
                      value: LogLevel.info,
                      child: Text('Info (≥ info)'),
                    ),
                    DropdownMenuItem<LogLevel?>(
                      value: LogLevel.warn,
                      child: Text('Warn (≥ warn)'),
                    ),
                    DropdownMenuItem<LogLevel?>(
                      value: LogLevel.error,
                      child: Text('Error (≥ error)'),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => _exportLogs(context, memorySink.records),
                  icon: const Icon(Icons.copy_all, size: 16),
                  label: const Text('Export Logs'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${memorySink.records.length} log records stored in memory',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 6. ABOUT
// ---------------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: Icons.info_outline,
              title: 'About',
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const BrandMark(size: 40),
              title: const Text(kProductName),
              subtitle: const Text('Version $kAppVersion'),
              trailing: OutlinedButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: kProductName,
                  applicationVersion: kAppVersion,
                ),
                child: const Text('Licenses'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HELPER WIDGETS
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
