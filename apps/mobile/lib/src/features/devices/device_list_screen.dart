import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import '../control/control_screen.dart';
import '../pairing/pairing_screen.dart';
import '../settings/settings_screen.dart';
import 'auto_connect.dart';

/// One row in the list, from either discovery or the trust store.
///
/// The two sources are merged rather than shown separately because the user
/// does not care how a computer was found — only whether they can reach it. A
/// paired computer that discovery cannot currently see is still perfectly
/// reachable at its last known address, and hiding it would make the app look
/// broken on exactly the networks where discovery fails.
class _Entry {
  const _Entry({
    this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.isPaired,
    required this.isLive,
    this.platform = PlatformKind.unknown,
    this.publicKey,
  });

  final DeviceId? id;
  final String name;
  final String host;
  final int port;

  /// In the trust store, so the handshake verifies against a stored key.
  final bool isPaired;

  /// Currently announcing itself, so the address is known-good.
  final bool isLive;

  final PlatformKind platform;

  /// Present only when paired; turns trust-on-first-use into strict
  /// verification.
  final Uint8List? publicKey;
}

/// Lists computers and connects to one.
///
/// The app's first screen, and its job is to have as little on it as possible:
/// open RemoteLink, see your computer, tap it, be in control. Manual entry
/// exists as a fallback, not as the path — it is one tap away, not in the way.
class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key});

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  @override
  void initState() {
    super.initState();
    // Started here rather than in a provider so it runs exactly once per app
    // launch, tied to this screen appearing. A provider would re-run whenever
    // its dependencies changed, which for discovery is every couple of seconds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(autoConnectProvider.notifier).attempt());
    });
  }

  @override
  Widget build(BuildContext context) {
    // Navigating from a listener rather than from build: build can run many
    // times, and pushing a route from it would stack duplicate touchpads.
    ref.listen(autoConnectProvider, (previous, next) {
      if (next != AutoConnectStage.connected) return;
      if (!mounted) return;
      unawaited(
        Navigator.of(context)
            .push(
              MaterialPageRoute<void>(builder: (_) => const ControlScreen()),
            )
            // Returning from the touchpad means the user chose to leave, so
            // stop auto-connecting or they would be bounced straight back.
            .then((_) => ref.read(autoConnectProvider.notifier).cancel()),
      );
    });

    final stage = ref.watch(autoConnectProvider);
    if (stage == AutoConnectStage.deciding ||
        stage == AutoConnectStage.connecting) {
      return _Reconnecting(
        name: ref.watch(autoConnectTargetProvider).valueOrNull?.displayName,
        onCancel: () => ref.read(autoConnectProvider.notifier).cancel(),
      );
    }

    final discovered = ref.watch(discoveredDevicesProvider).valueOrNull ??
        const <DiscoveredDevice>[];
    final paired =
        ref.watch(trustedPeersProvider).valueOrNull ?? const <TrustedPeer>[];
    final entries = _merge(discovered, paired);
    final clientState = ref.watch(clientStateProvider).valueOrNull;
    final client = ref.watch(clientProvider).valueOrNull;
    final revokedPeerId = clientState == ClientState.failed &&
            client?.failureCode == ProtocolErrorCode.revoked
        ? client?.target?.deviceId
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Computers'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Search again',
            onPressed: () async {
              final backend = await ref.read(discoveryProvider.future);
              await backend.refresh();
            },
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _promptForAddress(context),
        icon: const Icon(Icons.keyboard),
        label: const Text('Connect by address'),
      ),
      body: entries.isEmpty
          ? _Searching(
              discoveryWorks:
                  ref.watch(discoveryOperationalProvider).valueOrNull ?? true,
            )
          : RefreshIndicator(
              onRefresh: () async {
                final backend = await ref.read(discoveryProvider.future);
                await backend.refresh();
              },
              child: ListView.builder(
                // Leaves room for the FAB so the last row is never covered.
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final wasRevoked = entry.id == revokedPeerId;
                  return _DeviceTile(
                    entry: entry,
                    wasRevoked: wasRevoked,
                    onTap: wasRevoked ? null : () => _connect(context, entry),
                    onPairAgain:
                        wasRevoked ? () => _pairAgain(context, entry) : null,
                    onRename: entry.isPaired && entry.id != null
                        ? () => _renameComputer(context, entry)
                        : null,
                  );
                },
              ),
            ),
    );
  }

  /// Combines live beacons with stored pairings, preferring the live address.
  static List<_Entry> _merge(
    List<DiscoveredDevice> discovered,
    List<TrustedPeer> paired,
  ) {
    final byId = <String, TrustedPeer>{
      for (final peer in paired) peer.id.value: peer,
    };
    final entries = <_Entry>[];
    final seen = <String>{};

    for (final device in discovered) {
      final peer = byId[device.id.value];
      seen.add(device.id.value);
      entries.add(
        _Entry(
          id: device.id,
          name: peer?.name ?? device.name,
          // The live address wins over the stored one: a computer that moved to
          // a new DHCP lease is announcing where it actually is now.
          host: device.address,
          port: device.port,
          isPaired: peer != null,
          isLive: true,
          platform: device.beacon.platform,
          publicKey: peer?.publicKey,
        ),
      );
    }

    for (final peer in paired) {
      if (seen.contains(peer.id.value)) continue;
      final address = peer.lastAddress;
      if (address == null) continue;
      entries.add(
        _Entry(
          id: peer.id,
          name: peer.name,
          host: address,
          port: kDefaultServicePort,
          isPaired: true,
          isLive: false,
          platform: peer.platform,
          publicKey: peer.publicKey,
        ),
      );
    }

    entries.sort((a, b) {
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      if (a.isPaired != b.isPaired) return a.isPaired ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<void> _promptForAddress(BuildContext context) async {
    final entry = await showDialog<_Entry>(
      context: context,
      builder: (context) => const _ManualAddressDialog(),
    );
    if (entry == null || !context.mounted) return;
    await _connect(context, entry);
  }

  Future<void> _connect(
    BuildContext context,
    _Entry entry, {
    bool freshPairing = false,
  }) async {
    final client = await ref.read(clientProvider.future);
    if (!context.mounted) return;

    // Passing the stored key turns the handshake from trust-on-first-use into
    // strict verification, so a substituted server is rejected rather than
    // prompting to re-pair — which is exactly the dialog an attacker who took
    // over the address would want the user to see.
    await client.connect(
      ConnectionTarget(
        host: entry.host,
        port: entry.port,
        deviceId: entry.id,
        serverPublicKey: freshPairing ? null : entry.publicKey,
        displayName: entry.name,
      ),
    );

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => entry.isPaired && !freshPairing
            ? const ControlScreen()
            : PairingScreen(
                deviceName: entry.name,
                address: entry.host,
                platform: entry.platform,
              ),
      ),
    );
  }

  Future<void> _pairAgain(BuildContext context, _Entry entry) async {
    final peerId = entry.id;
    if (peerId == null) return;

    final client = await ref.read(clientProvider.future);
    await client.disconnect();

    final trustStore = await ref.read(trustStoreProvider.future);
    await trustStore.forget(peerId);
    await persistTrustStore(
      trustStore,
      await ref.read(identityStoreProvider.future),
    );
    ref.invalidate(trustedPeersProvider);

    if (!context.mounted) return;
    await _connect(context, entry, freshPairing: true);
  }

  Future<void> _renameComputer(BuildContext context, _Entry entry) async {
    final peerId = entry.id;
    if (peerId == null) return;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _RenameComputerDialog(initialName: entry.name),
    );
    if (newName == null || !context.mounted) return;

    // 1. Persist new name in mobile's trust store.
    final trustStore = await ref.read(trustStoreProvider.future);
    final peer = await trustStore.findById(peerId);
    if (peer != null) {
      await trustStore.upsert(peer.copyWith(name: newName));
      await persistTrustStore(
        trustStore,
        await ref.read(identityStoreProvider.future),
      );
      ref.invalidate(trustedPeersProvider);
    }

    // 2. If connected to this peer, send DeviceRename message to the desktop.
    final client = ref.read(clientProvider).valueOrNull;
    if (client != null && client.session?.isEstablished == true) {
      if (client.session?.peerId == peerId ||
          client.target?.deviceId == peerId) {
        try {
          await client.session?.send(DeviceRename(newName));
        } on TransportError {
          // Connection in teardown, ignore.
        }
      }
    }
  }
}

/// Asks for a host and port.
///
/// The only way in on a network that blocks multicast, or on an iPhone without
/// the multicast entitlement Apple grants by application. Not a debug affordance
/// — it is the documented fallback, so it is built to be used.
class _ManualAddressDialog extends StatefulWidget {
  const _ManualAddressDialog();

  @override
  State<_ManualAddressDialog> createState() => _ManualAddressDialogState();
}

class _ManualAddressDialogState extends State<_ManualAddressDialog> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port =
      TextEditingController(text: '$kDefaultServicePort');
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());

    if (host.isEmpty) {
      setState(() => _error = 'Enter the address shown on your computer.');
      return;
    }
    if (port == null || port <= 0 || port > 65535) {
      setState(() => _error = 'Port must be between 1 and 65535.');
      return;
    }

    Navigator.of(context).pop(
      _Entry(
        name: host,
        host: host,
        port: port,
        isPaired: false,
        isLive: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Connect by address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'RemoteLink on your computer shows its address under '
              '“Discoverable on this network”.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _host,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              // A hostname or IP is never a sentence; autocapitalising it turns
              // a working address into a failed connection.
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(
                labelText: 'Address',
                hintText: '192.168.1.42',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Connect')),
        ],
      );
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.entry,
    required this.wasRevoked,
    required this.onTap,
    required this.onPairAgain,
    this.onRename,
  });

  final _Entry entry;
  final bool wasRevoked;
  final VoidCallback? onTap;
  final VoidCallback? onPairAgain;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        switch (entry.platform) {
          PlatformKind.macos => Icons.laptop_mac,
          PlatformKind.windows => Icons.laptop_windows,
          _ => Icons.computer,
        },
        size: 32,
        // Dimmed when the computer is paired but not currently announcing: the
        // address may be stale, and the tap may fail. Better to show it looking
        // uncertain than to hide it or pretend it is online.
        color: entry.isLive
            ? null
            : scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      title: Text(entry.name),
      subtitle: Text(
        wasRevoked
            ? 'This computer removed your access'
            : switch ((entry.isPaired, entry.isLive)) {
                (true, true) => 'Paired · ${entry.host}',
                (true, false) => 'Paired · not seen right now · ${entry.host}',
                (false, true) => 'Tap to pair · ${entry.host}',
                (false, false) => entry.host,
              },
      ),
      trailing: wasRevoked
          ? TextButton(
              onPressed: onPairAgain,
              child: const Text('Pair again'),
            )
          : entry.isPaired
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (onRename != null)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Rename computer',
                        onPressed: onRename,
                      ),
                    Icon(Icons.verified_user, color: scheme.primary),
                  ],
                )
              : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
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

/// Shown while reconnecting to the last used computer.
///
/// Always cancellable. An automatic action that cannot be interrupted is worse
/// than no automatic action: if the guess is wrong, or the computer is asleep,
/// the user is stuck watching a spinner instead of picking a different machine.
class _Reconnecting extends StatelessWidget {
  const _Reconnecting({required this.name, required this.onCancel});

  final String? name;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  name == null ? 'Reconnecting' : 'Reconnecting to $name',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Choose a different computer'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Searching extends StatelessWidget {
  const _Searching({required this.discoveryWorks});

  /// False once the platform has actually refused the discovery traffic.
  ///
  /// The two states get different copy on purpose. "Still looking" invites
  /// patience; "this device cannot search" tells the user to stop waiting and
  /// use the button. Showing a spinner forever in the second case is the
  /// failure mode this flag exists to prevent.
  final bool discoveryWorks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      // A scrollable, so pull-to-refresh still works with an empty list.
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 64),
        if (discoveryWorks)
          const Center(child: CircularProgressIndicator())
        else
          Icon(
            Icons.wifi_find_outlined,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
        const SizedBox(height: 24),
        Text(
          discoveryWorks
              ? 'Looking for computers'
              : 'This device can’t search automatically',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          discoveryWorks
              ? 'Make sure RemoteLink is running on your computer and both '
                  'devices are on the same Wi-Fi network.'
              : 'iPhones need a special Apple permission to search the local '
                  'network, and some Wi-Fi networks block it entirely.\n\n'
                  'Tap “Connect by address” and enter the address shown on '
                  'your computer. Everything else works exactly the same.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
