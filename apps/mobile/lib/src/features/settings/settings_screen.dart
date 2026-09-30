import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/app_icons.dart';
import '../../app/brand.dart';
import '../../app/l10n.dart';
import '../../app/providers.dart';
import '../clipboard/clipboard_history_controller.dart';
import '../devices/bonjour_discovery.dart';
import '../devices/link_service.dart';
import '../devices/remember_prompt.dart';
import '../host/host_providers.dart';
import '../host/phone_host_service.dart';
import '../watch/watch_bridge.dart';

/// Settings screen for configuring device identity, managing paired computers,
/// adjusting touchpad and clipboard preferences, inspecting diagnostics, and
/// viewing app licenses.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: const <Widget>[
          _ThisPhoneSection(),
          SizedBox(height: 12),
          _AppearanceSection(),
          SizedBox(height: 12),
          _TouchpadSection(),
          SizedBox(height: 12),
          _ReceivingSection(),
          SizedBox(height: 12),
          _PairedComputersSection(),
          SizedBox(height: 12),
          _ClipboardSection(),
          SizedBox(height: 12),
          _BackgroundSection(),
          SizedBox(height: 12),
          _AppleWatchSection(),
          SizedBox(height: 12),
          _DiagnosticsSection(),
          SizedBox(height: 12),
          _AboutSection(),
          SizedBox(height: 16),
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: AppIcons.monitorSmartphone,
              title: context.l10n.sectionThisPhone,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.deviceName),
              subtitle: Text(
                phoneName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: IconButton(
                icon: AppIcon(
                  AppIcons.edit,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: context.l10n.renameThisPhone,
                onPressed: () => _promptRenamePhone(context, ref, phoneName),
              ),
            ),
            const Divider(height: 12),
            identityAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (err, _) => Text(
                context.l10n.couldNotLoadIdentity(err.toString()),
                style: TextStyle(color: colorScheme.error),
              ),
              data: (identity) {
                final fingerprint = _formatFingerprint(identity.publicKey);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.l10n.deviceId,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: SelectableText(
                        identity.id.value,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.publicKeyFingerprint,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: SelectableText(
                        fingerprint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
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
        title: Text(context.l10n.renamePhoneDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.phoneName,
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
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(context.l10n.save),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// 2. APPEARANCE
// ---------------------------------------------------------------------------

/// Light, dark, or whatever the phone says.
///
/// A [SegmentedButton] rather than a switch, because there are three states and
/// the third one — follow the system — is not the absence of the other two.
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: AppIcons.settings,
              title: context.l10n.sectionAppearance,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 10),
            // Full width so the three labels have room at a large text size;
            // a segmented button sized to its content wraps 'System' onto two
            // lines before the phone runs out of width.
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    icon: const AppIcon(AppIcons.settings, size: 18),
                    label: Text(context.l10n.themeModeSystem),
                    tooltip: context.l10n.themeModeFollowSystem,
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    icon: const AppIcon(AppIcons.settings, size: 18),
                    label: Text(context.l10n.themeModeLight),
                    tooltip: context.l10n.themeModeAlwaysLight,
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    icon: const AppIcon(AppIcons.settings, size: 18),
                    label: Text(context.l10n.themeModeDark),
                    tooltip: context.l10n.themeModeAlwaysDark,
                  ),
                ],
                selected: <ThemeMode>{mode},
                onSelectionChanged: (selection) =>
                    notifier.setThemeMode(selection.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. RECEIVING
// ---------------------------------------------------------------------------

/// Whether other devices can find this phone and send to it.
///
/// The one switch in this app that turns a feature off rather than on, and it
/// is here because the feature has a cost that is not obvious from using it:
/// while it is on, this phone publishes its name on the Wi-Fi and holds a
/// listening socket. Nothing can arrive unasked — an unknown device still has
/// to be confirmed by six digits, and a known one still has to have its
/// transfer accepted — but being *listed* is itself something a person may not
/// want on a network they do not trust, and that is not a decision this app
/// gets to make for them.
class _ReceivingSection extends ConsumerWidget {
  const _ReceivingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final wanted = ref.watch(receivingProvider);
    final live = ref.watch(receivingLiveProvider);
    final name = ref.watch(deviceNameProvider);
    final connected =
        ref.watch(inboundLinksProvider).valueOrNull ?? const <InboundLink>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: AppIcons.receive,
              title: context.l10n.sectionReceiving,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: wanted,
              onChanged: (enabled) =>
                  ref.read(receivingProvider.notifier).setReceiving(enabled),
              title: Text(context.l10n.letNearbyDevicesSendTitle),
              subtitle: Text(
                wanted
                    // The state, not the setting. The two differ when the
                    // socket could not bind or has not come up yet, and a line
                    // that reported the preference would tell someone they are
                    // findable at the exact moment they are not.
                    ? live
                        ? context.l10n.receivingVisibleWifi(name)
                        : context.l10n.receivingStarting
                    : context.l10n.receivingHidden,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: ref.watch(askBeforeConnectingProvider),
              onChanged: (enabled) => ref
                  .read(askBeforeConnectingProvider.notifier)
                  .set(enabled: enabled),
              title: Text(context.l10n.askBeforeConnectingTitle),
              subtitle: Text(
                ref.watch(askBeforeConnectingProvider)
                    ? context.l10n.waitBeforeConnectingSubtitle
                    : context.l10n.connectAutomaticallySubtitle,
              ),
            ),
            if (connected.isNotEmpty) ...<Widget>[
              const Divider(height: 16),
              Text(
                context.l10n.connectedNow(connected.length),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              for (final link in connected)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: <Widget>[
                      AppIcon(
                        AppIcons.monitorSmartphone,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          link.name,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. PAIRED DEVICES
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: AppIcons.monitorSmartphone,
              // Not "Computers" any more: a paired phone lands in the same
              // trust store and is revoked from the same list.
              title: context.l10n.pairedDevicesTitle,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 10),
            peersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (err, _) => Text(
                context.l10n.couldNotLoadPairedComputers(err.toString()),
                style: TextStyle(color: colorScheme.error),
              ),
              data: (peers) {
                if (peers.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      context.l10n.noPairedComputersExplanation,
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
                      if (i > 0) const Divider(height: 12),
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
      PlatformKind.macos => AppIcons.monitorSmartphone,
      PlatformKind.windows => AppIcons.monitorSmartphone,
      PlatformKind.linux => AppIcons.monitorSmartphone,
      _ => AppIcons.monitorSmartphone,
    };

    // Where this computer was last reached. Kept in the row because it is the
    // only thing that tells two identically named machines apart, and the only
    // hint available when a paired computer has moved to a different network.
    final addressText = peer.lastAddress != null
        ? context.l10n.lastSeen(peer.lastAddress!)
        : context.l10n.noAddressRecorded;
    final peerName = peer.name;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AppIcon(platformIcon, color: colorScheme.primary, size: 28),
      title: Text(
        peerName,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        addressText,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const AppIcon(AppIcons.protection),
            tooltip: context.l10n.permissionsFor(peerName),
            onPressed: () => _requestPermission(context, ref, peer),
          ),
          IconButton(
            icon: AppIcon(
              AppIcons.edit,
              color: colorScheme.onSurfaceVariant,
            ),
            tooltip: context.l10n.renameNamed(peerName),
            onPressed: () => _renameComputer(context, ref, peer),
          ),
          // The way out of a remembered connection, and the only one short of
          // forgetting the device entirely. Turning it off does not un-pair
          // anything: the device goes back to being asked about, which is
          // where it was before either end agreed to anything.
          IconButton(
            icon: AppIcon(
              AppIcons.protection,
              color: peer.autoAdmit
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            tooltip: peer.autoAdmit
                ? context.l10n.rememberAutoConnectTooltip(peerName)
                : context.l10n.rememberAskFirstTooltip(peerName),
            onPressed: () => ref
                .read(rememberPromptProvider.notifier)
                .setRemembered(peer.id, remember: !peer.autoAdmit),
          ),
          IconButton(
            icon: AppIcon(AppIcons.delete, color: colorScheme.error),
            tooltip: context.l10n.forgetNamed(peerName),
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

    // This is a local alias for the computer, not this phone's display name.
    // The desktop would interpret DeviceRename as a rename of the phone.
    final trustStore = await ref.read(trustStoreProvider.future);
    await trustStore.upsert(peer.copyWith(name: newName));
    await persistTrustStore(
      trustStore,
      await ref.read(identityStoreProvider.future),
    );
    ref.invalidate(trustedPeersProvider);
  }

  Future<void> _confirmForgetComputer(
    BuildContext context,
    WidgetRef ref,
    TrustedPeer peer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.forgetNamedQuestion(peer.name)),
        content: Text(context.l10n.forgetComputerConfirmation),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.forgetDevice),
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
        SnackBar(content: Text(context.l10n.forgotNamed(peer.name))),
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
        _error = context.l10n.invalidDeviceName;
      });
      return;
    }
    Navigator.of(context).pop(sanitised);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.l10n.renameComputerTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.computerName,
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
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(context.l10n.save),
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

  static String _tierTitle(BuildContext context, PermissionTier tier) =>
      switch (tier) {
        PermissionTier.readOnly => context.l10n.tierReadOnlyTitle,
        PermissionTier.standard => context.l10n.tierStandardTitle,
        PermissionTier.extended => context.l10n.tierExtendedTitle,
        PermissionTier.admin => context.l10n.tierAdminTitle,
      };

  static String _tierDescription(BuildContext context, PermissionTier tier) =>
      switch (tier) {
        PermissionTier.readOnly => context.l10n.tierReadOnlyDesc,
        PermissionTier.standard => context.l10n.tierStandardDesc,
        PermissionTier.extended => context.l10n.tierExtendedDesc,
        PermissionTier.admin => context.l10n.tierAdminDesc,
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
            context.l10n.connectToRequestElevation(widget.peer.name),
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
          content: Text(context.l10n.permissionRequestSent(widget.peer.name)),
        ),
      );
    } on TransportError {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.permissionRequestFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Text(context.l10n.permissionsNamed(widget.peer.name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.currentPermissionTier,
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
                    _tierTitle(context, widget.currentTier),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _tierDescription(context, widget.currentTier),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.requestHigherTier,
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
                      child: Text(_tierTitle(context, tier)),
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
                    context.l10n
                        .whatTierAllows(_tierTitle(context, _selectedTier)),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tierDescription(context, _selectedTier),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _justificationController,
              decoration: InputDecoration(
                labelText: context.l10n.reasonJustificationOptional,
                hintText: context.l10n.reasonHint,
                border: const OutlineInputBorder(),
              ),
              maxLength: 256,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _isSending ? null : _submit,
          child: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.requestElevation),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. TOUCHPAD
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: AppIcons.handTap,
              title: context.l10n.sectionTouchpad,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Expanded(
                  child: Text(
                    context.l10n.pointerSensitivity,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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
            const Divider(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.naturalScrolling),
              subtitle: Text(context.l10n.naturalScrollingMatches),
              value: pointerSettings.naturalScrolling,
              onChanged: (val) => notifier.setNaturalScrolling(val),
            ),
            const Divider(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.tapToClick),
              subtitle: Text(
                context.l10n.tapToClickSubtitle,
              ),
              value: pointerSettings.tapToClick,
              onChanged: (val) => notifier.setTapToClick(val),
            ),
            const Divider(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.hapticFeedback),
              subtitle: Text(
                context.l10n.hapticFeedbackDetail,
              ),
              value: ref.watch(hapticsProvider),
              onChanged: (val) =>
                  ref.read(hapticsProvider.notifier).setEnabled(val),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. CLIPBOARD
// ---------------------------------------------------------------------------

class _ClipboardSection extends ConsumerWidget {
  const _ClipboardSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final clipboardSettings = ref.watch(clipboardSettingsProvider);
    final notifier = ref.read(clipboardSettingsProvider.notifier);
    final history = ref.watch(clipboardHistoryControllerProvider);
    final historyController =
        ref.read(clipboardHistoryControllerProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: AppIcons.clipboard,
              title: context.l10n.sectionClipboard,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.syncFromDesktop),
              subtitle: Text(
                context.l10n.syncFromDesktopDetail,
              ),
              value: clipboardSettings.syncFromDesktop,
              onChanged: (val) => notifier.setSyncFromDesktop(val),
            ),
            const Divider(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.syncToDesktop),
              subtitle: Text(
                context.l10n.syncToDesktopDetail,
              ),
              value: clipboardSettings.syncToDesktop,
              onChanged: (val) => notifier.setSyncToDesktop(val),
            ),
            const Divider(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.keepHistoryOnThisPhone),
              subtitle: Text(
                history.isPersistent
                    ? context.l10n.historyPersistentSubtitle
                    : context.l10n.historyMemoryOnlySubtitle,
              ),
              value: history.isPersistent,
              onChanged: (enabled) async {
                final applied = await historyController.setPersistenceEnabled(
                  enabled: enabled,
                );
                if (!context.mounted || applied) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.l10n.secureStorageUnavailable,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppIcon(
                    AppIcons.settings,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${context.l10n.whyPhoneOpenTitle}\n'
                      '${context.l10n.whyPhoneOpenSubtitle}',
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
// 6. BACKGROUND
// ---------------------------------------------------------------------------

class _BackgroundSection extends ConsumerWidget {
  const _BackgroundSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final service = ref.watch(linkServiceProvider);
    final enabled = ref.watch(backgroundLinkEnabledProvider);

    // Nothing here applies to a platform with no service to run. iOS grants no
    // persistent background networking to an app of this kind, so offering the
    // switch there would be offering a setting that does nothing.
    if (!service.isSupported) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: AppIcons.settings,
              title: context.l10n.sectionBackground,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.stayConnectedBackground),
              subtitle: Text(
                context.l10n.stayConnectedBackgroundSubtitle,
              ),
              value: enabled,
              onChanged: (value) =>
                  ref.read(backgroundLinkEnabledProvider.notifier).set(value),
            ),
            const Divider(height: 12),
            const _BackgroundClipboardTile(),
            const Divider(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppIcon(
                AppIcons.settings,
                color: colorScheme.onSurfaceVariant,
              ),
              title: Text(context.l10n.keepsStoppingQuestion),
              subtitle: Text(
                context.l10n.keepsStoppingSubtitle,
              ),
              trailing: const AppIcon(AppIcons.settings),
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => const _BatteryGuidanceDialog(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turns on reading the clipboard while another app is on screen.
///
/// The only feature in this app that asks for an accessibility service, and it
/// asks because Android leaves no other way: `getPrimaryClip` returns null to
/// an app without window focus, so copying in a browser cannot reach the
/// computer through any permission, service or entitlement. Off unless the
/// user turns it on, and everything else works without it.
class _BackgroundClipboardTile extends ConsumerStatefulWidget {
  const _BackgroundClipboardTile();

  @override
  ConsumerState<_BackgroundClipboardTile> createState() =>
      _BackgroundClipboardTileState();
}

class _BackgroundClipboardTileState
    extends ConsumerState<_BackgroundClipboardTile>
    with WidgetsBindingObserver {
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The switch is thrown on a system screen this app cannot see, so the only
    // moment its state can be trusted is on the way back from there.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final enabled =
        await ref.read(linkServiceProvider).backgroundClipboardEnabled();
    if (!mounted) return;
    setState(() => _enabled = enabled);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AppIcon(
        _enabled ? AppIcons.settings : AppIcons.clipboard,
        color: _enabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(context.l10n.copyInAnyApp),
      subtitle: Text(
        _enabled
            ? context.l10n.backgroundClipboardOn
            : context.l10n.backgroundClipboardOff,
      ),
      trailing: const AppIcon(AppIcons.settings),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => _BackgroundClipboardDialog(enabled: _enabled),
      ),
    );
  }
}

/// Explains what enabling the service means before sending the user to do it.
///
/// Written plainly and without persuasion. An accessibility service is a large
/// thing to grant, the system screen says so in stronger words than these, and
/// a user who reads this and decides against it has decided correctly for
/// them — the app works without it.
class _BackgroundClipboardDialog extends ConsumerWidget {
  const _BackgroundClipboardDialog({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Text(context.l10n.backgroundClipboardTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.accessibilityDialogPara1,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.accessibilityDialogPara2,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.accessibilityDialogPara3,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.notNow),
        ),
        FilledButton(
          onPressed: () async {
            final opened =
                await ref.read(linkServiceProvider).openAccessibilitySettings();
            if (!context.mounted) return;
            Navigator.of(context).pop();
            if (opened) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.couldNotOpenAccessibility),
              ),
            );
          },
          child:
              Text(enabled ? context.l10n.openSettings : context.l10n.turnItOn),
        ),
      ],
    );
  }
}

/// What to do when the phone's own battery manager closes the app anyway.
///
/// Written as instructions rather than an apology, because on the phones where
/// this matters the user genuinely can fix it and nothing in the app can. The
/// manufacturer screens are named rather than linked: Xiaomi's Autostart and
/// Huawei's protected-apps lists have no public intent, and a button that
/// silently does nothing would be worse than a sentence that says where to look.
class _BatteryGuidanceDialog extends ConsumerWidget {
  const _BatteryGuidanceDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Text(context.l10n.batteryGuidanceTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.batteryGuidancePara1,
            ),
            const SizedBox(height: 16),
            Text(context.l10n.batteryGuidanceAnyPhone,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(context.l10n.batteryGuidanceAnyPhoneDesc),
            const SizedBox(height: 16),
            Text(
              context.l10n.batteryGuidanceXiaomi,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.batteryGuidanceXiaomiDesc,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.batteryGuidanceOther,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.batteryGuidanceOtherDesc,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.closeButton),
        ),
        FilledButton(
          onPressed: () async {
            final opened =
                await ref.read(linkServiceProvider).openBatterySettings();
            if (!context.mounted) return;
            Navigator.of(context).pop();
            if (opened) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.noBatterySettingsScreen,
                ),
              ),
            );
          },
          child: Text(context.l10n.openBatterySettings),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 7. APPLE WATCH
// ---------------------------------------------------------------------------

/// Whether there is a watch, whether it has the app, and whether it is in
/// range — reported separately, because each sends the user somewhere else.
///
/// Hidden entirely on a phone that cannot have one. A permanently empty section
/// explaining that Android has no Apple Watch is noise on every Android
/// install, and there is nothing the user could do about it.
class _AppleWatchSection extends ConsumerWidget {
  const _AppleWatchSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final availability = ref.watch(watchAvailabilityProvider).valueOrNull ??
        const WatchAvailability();

    if (!availability.supported) return const SizedBox.shrink();

    final (icon, headline, detail) = switch (availability) {
      WatchAvailability(paired: false) => (
          AppIcons.settings,
          context.l10n.noWatchPaired,
          context.l10n.noWatchPairedDesc,
        ),
      WatchAvailability(installed: false) => (
          AppIcons.settings,
          context.l10n.watchNotInstalled,
          context.l10n.watchNotInstalledDesc,
        ),
      WatchAvailability(reachable: false) => (
          AppIcons.settings,
          context.l10n.watchOutOfRange,
          context.l10n.watchOutOfRangeDesc,
        ),
      _ => (
          AppIcons.settings,
          context.l10n.watchReady,
          context.l10n.watchReadyDesc,
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: AppIcons.settings,
              title: context.l10n.appleWatchTitle,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppIcon(icon, color: colorScheme.primary),
              title: Text(headline),
              subtitle: Text(detail),
              trailing: IconButton(
                tooltip: context.l10n.checkAgain,
                icon: const AppIcon(AppIcons.settings),
                onPressed: () => ref.invalidate(watchAvailabilityProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. DIAGNOSTICS
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
    BuildContext context,
    DiscoveryBackend? discovery,
    ConnectionTarget? target,
    bool isConnected,
  ) {
    if (!isConnected || target == null) {
      return context.l10n.notConnected;
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
      if (inBonjour && inUdp) return context.l10n.routeBonjourUdp;
      if (inBonjour) return context.l10n.routeBonjour;
      if (inUdp) return context.l10n.routeUdp;
    } else if (discovery is BonjourDiscoveryBackend) {
      if (discovery.current.any((d) =>
          (target.deviceId != null && d.id == target.deviceId) ||
          d.address == target.host)) {
        return context.l10n.routeBonjour;
      }
    } else if (discovery != null) {
      if (discovery.current.any((d) =>
          (target.deviceId != null && d.id == target.deviceId) ||
          d.address == target.host)) {
        return context.l10n.routeUdp;
      }
    }

    return context.l10n.routeManual;
  }

  void _exportLogs(
    BuildContext context,
    List<LogRecord> records, [
    FileLogSink? fileSink,
    CrashReport? lastCrashReport,
  ]) {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';

    final localName = ref.read(deviceNameProvider);
    final trustedPeers = ref.read(trustedPeersProvider).valueOrNull ?? const [];
    final client = ref.read(clientProvider).valueOrNull;

    final peerNames = <String>{
      if (localName.isNotEmpty) localName,
      for (final p in trustedPeers)
        if (p.name.isNotEmpty) p.name,
      if (client?.target?.displayName != null &&
          client!.target!.displayName!.isNotEmpty)
        client.target!.displayName!,
    };

    final redactor = LogRedactor(
      homeDirectories: [if (home.isNotEmpty) home],
      knownPeerNames: peerNames,
    );

    final text = buildLogExport(
      fileSink: fileSink,
      memoryRecords: records,
      lastCrashReport: lastCrashReport,
      redactor: redactor,
      filterLevel: _selectedLevel,
      header: '=== Remote Link Mobile Diagnostics Logs ===\n'
          'Generated: ${DateTime.now().toUtc().toIso8601String()}',
    );

    Clipboard.setData(ClipboardData(text: text));

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.l10n.logsCopiedToClipboard),
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
    final fileSink = ref.watch(fileLogSinkProvider);
    final crashHandler = ref.watch(crashHandlerProvider);

    final isConnected = clientState == ClientState.connected;
    final rttText = isConnected && quality != null
        ? '${quality.roundTripMillis.toStringAsFixed(0)} ms'
        : isConnected
            ? context.l10n.measuring
            : context.l10n.notConnected;

    final discoveryRoute =
        _formatRoute(context, discovery, client?.target, isConnected);

    final stateLabel = switch (clientState) {
      ClientState.connected => context.l10n.stateConnected,
      ClientState.connecting => context.l10n.stateConnecting,
      ClientState.reconnecting => context.l10n.stateReconnecting,
      ClientState.pairing => context.l10n.statePairing,
      ClientState.awaitingApproval => context.l10n.stateAwaitingApproval,
      ClientState.failed => context.l10n.stateFailed,
      ClientState.idle => context.l10n.stateIdle,
    };

    final stateColor = switch (clientState) {
      ClientState.connected => colorScheme.primary,
      ClientState.connecting ||
      ClientState.reconnecting ||
      ClientState.awaitingApproval =>
        colorScheme.tertiary,
      ClientState.failed => colorScheme.error,
      _ => colorScheme.onSurfaceVariant,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: AppIcons.analytics,
              title: context.l10n.sectionDiagnostics,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 10),
            _DiagnosticRow(
              label: context.l10n.connectionStateLabel,
              value: stateLabel,
              valueColor: stateColor,
            ),
            const SizedBox(height: 6),
            _DiagnosticRow(
              label: context.l10n.roundTripTimeLabel,
              value: rttText,
            ),
            const SizedBox(height: 6),
            _DiagnosticRow(
              label: context.l10n.discoveryRouteLabel,
              value: discoveryRoute,
            ),
            const Divider(height: 14),
            // Wrapped rather than a Row with a Spacer: the filter label, the
            // level names and "Export Logs" together need more width than a
            // phone has once the card's padding is taken out, and a Row answers
            // that by painting the overflow stripes over the button. Wrapping
            // puts the button on its own line instead.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  context.l10n.logFilter,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                DropdownButton<LogLevel?>(
                  value: _selectedLevel,
                  underline: const SizedBox.shrink(),
                  onChanged: (level) => setState(() => _selectedLevel = level),
                  items: <DropdownMenuItem<LogLevel?>>[
                    DropdownMenuItem<LogLevel?>(
                      value: null,
                      child: Text(context.l10n.allLevels),
                    ),
                    const DropdownMenuItem<LogLevel?>(
                      value: LogLevel.debug,
                      child: Text('Debug (≥ debug)'),
                    ),
                    const DropdownMenuItem<LogLevel?>(
                      value: LogLevel.info,
                      child: Text('Info (≥ info)'),
                    ),
                    const DropdownMenuItem<LogLevel?>(
                      value: LogLevel.warn,
                      child: Text('Warn (≥ warn)'),
                    ),
                    const DropdownMenuItem<LogLevel?>(
                      value: LogLevel.error,
                      child: Text('Error (≥ error)'),
                    ),
                  ],
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _exportLogs(
                    context,
                    memorySink.records,
                    fileSink,
                    crashHandler.lastReport,
                  ),
                  icon: const AppIcon(AppIcons.clipboard, size: 16),
                  label: Text(context.l10n.exportLogs),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.logRecordsStored(memorySink.records.length),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Flexible and right-aligned rather than a bare Text: a discovery route
        // reads `mDNS · 192.168.1.50:47811`, which is longer than the space
        // left beside its label on a phone, and a Row answers that by painting
        // overflow stripes over it.
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 9. ABOUT
// ---------------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              icon: AppIcons.settings,
              title: context.l10n.sectionAbout,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const BrandMark(size: 40),
              title: const Text(kProductName),
              subtitle: Text(context.l10n.version(kAppVersion)),
              trailing: OutlinedButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: kProductName,
                  applicationVersion: kAppVersion,
                ),
                child: Text(context.l10n.licensesButton),
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

  final AppIconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        AppIcon(icon, size: 20, color: color),
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
