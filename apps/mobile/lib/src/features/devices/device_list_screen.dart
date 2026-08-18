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
import '../control/control_screen.dart';
import '../pairing/pairing_screen.dart';
import '../settings/settings_screen.dart';
import 'auto_connect.dart';
import 'wake_on_lan.dart';

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
    this.macAddress,
  });

  final DeviceId? id;
  final String name;

  /// Where to dial, or null when this computer has been paired with but never
  /// reached at a remembered address.
  ///
  /// Nullable rather than absent from the list. A paired computer with no
  /// address used to be dropped entirely, so the one thing the user was sure
  /// they had set up was the one thing the screen would not show them — and on
  /// a network where discovery finds nothing, that left the list permanently
  /// empty. Showing the row and asking for the address when it is tapped is
  /// strictly better than pretending the pairing does not exist.
  final String? host;
  final int port;

  /// In the trust store, so the handshake verifies against a stored key.
  final bool isPaired;

  /// Currently announcing itself, so the address is known-good.
  final bool isLive;

  final PlatformKind platform;

  /// Present only when paired; turns trust-on-first-use into strict
  /// verification.
  final Uint8List? publicKey;

  /// The computer's hardware address, if it reported one while connected.
  ///
  /// Its only use is Wake-on-LAN, so it is absent for anything this phone has
  /// not paired with and for computers running a build that predates the field.
  final MacAddress? macAddress;

  /// Whether offering to wake this computer could plausibly do something.
  ///
  /// A live computer does not need waking, an unpaired one is not ours to wake,
  /// and without a hardware address there is nothing to address the packet to.
  /// The last of those is the reason this is a getter rather than a bare
  /// `!isLive`: a Wake button that cannot possibly work is worse than no button.
  bool get canWake => isPaired && !isLive && macAddress != null;
}

/// Lists computers and connects to one.
///
/// How long the screen keeps a spinner up before admitting it found nothing.
///
/// Beacons arrive every couple of seconds and Bonjour resolution adds a round
/// trip, so anything shorter would give up while an answer was in flight. Much
/// longer and the spinner stops being feedback and becomes a wait with no end
/// in sight — which is the state that sent a user looking for a bug rather than
/// tapping the button that would have worked.
const Duration kDiscoveryPatience = Duration(seconds: 6);

/// The app's first screen, and its job is to have as little on it as possible:
/// open RemoteLink, see your computer, tap it, be in control. Manual entry
/// exists as a fallback, not as the path — it is one tap away, not in the way.
class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key});

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  /// Whether the search has run long enough to stop claiming it is working.
  ///
  /// Discovery reports itself "operational" whenever the platform API accepted
  /// the request — which is not the same as finding anything, and on the two
  /// networks where this matters most it is exactly wrong. A Wi-Fi network that
  /// filters multicast, or an iPhone whose local-network permission was denied
  /// once and never asked about again, both leave a browse running happily and
  /// silently empty. The screen then spins forever, which tells the user their
  /// setup is fine and they should keep waiting. It is not, and they should not.
  bool _searchExhausted = false;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    // Started here rather than in a provider so it runs exactly once per app
    // launch, tied to this screen appearing. A provider would re-run whenever
    // its dependencies changed, which for discovery is every couple of seconds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(autoConnectProvider.notifier).attempt());
    });
    _beginSearchWindow();
  }

  /// Restarts the "are we still looking?" clock.
  void _beginSearchWindow() {
    _searchTimer?.cancel();
    if (_searchExhausted) setState(() => _searchExhausted = false);
    _searchTimer = Timer(kDiscoveryPatience, () {
      if (mounted) setState(() => _searchExhausted = true);
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
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
    final wakeAddresses = ref.watch(wakeAddressesProvider);
    final entries = _merge(discovered, paired, wakeAddresses);
    final clientState = ref.watch(clientStateProvider).valueOrNull;
    final client = ref.watch(clientProvider).valueOrNull;
    final revokedPeerId = clientState == ClientState.failed &&
            client?.failureCode == ProtocolErrorCode.revoked
        ? client?.target?.deviceId
        : null;

    return Scaffold(
      appBar: AppBar(
        // The mark rather than a back arrow: this is the first screen, so the
        // leading slot is empty, and it is the only place in the phone app that
        // says which app you are in once the launch screen has gone.
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Center(child: BrandMark(size: 28)),
        ),
        title: const Text('Computers'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Search again',
            onPressed: () async {
              _beginSearchWindow();
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
        icon: const Icon(Icons.add_rounded),
        label: const Text('Connect by address'),
      ),
      body: entries.isEmpty
          ? _Searching(
              discoveryWorks:
                  ref.watch(discoveryOperationalProvider).valueOrNull ?? true,
              stillLooking: !_searchExhausted,
              onSearchAgain: () async {
                _beginSearchWindow();
                final backend = await ref.read(discoveryProvider.future);
                await backend.refresh();
              },
            )
          : RefreshIndicator(
              onRefresh: () async {
                final backend = await ref.read(discoveryProvider.future);
                await backend.refresh();
              },
              child: ListView.builder(
                // Leaves room for the FAB so the last row is never covered.
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
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
                    onWake: entry.canWake && !wasRevoked
                        ? () => _wake(context, entry)
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
    Map<String, MacAddress> wakeAddresses,
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
          macAddress: wakeAddresses[device.id.value],
        ),
      );
    }

    for (final peer in paired) {
      if (seen.contains(peer.id.value)) continue;
      final address = peer.lastAddress;
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
          macAddress: wakeAddresses[peer.id.value],
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

  /// Asks for an address, optionally to reach an already-paired computer.
  ///
  /// [forEntry] carries the pairing through, so typing the address of a
  /// computer already in the trust store still verifies against its stored key
  /// rather than dropping back to trust-on-first-use.
  Future<void> _promptForAddress(
    BuildContext context, {
    _Entry? forEntry,
  }) async {
    final typed = await showDialog<_Entry>(
      context: context,
      builder: (context) => _ManualAddressDialog(knownName: forEntry?.name),
    );
    if (typed == null || !context.mounted) return;

    final entry = forEntry == null
        ? typed
        : _Entry(
            id: forEntry.id,
            name: forEntry.name,
            host: typed.host,
            port: typed.port,
            isPaired: forEntry.isPaired,
            isLive: false,
            platform: forEntry.platform,
            publicKey: forEntry.publicKey,
            macAddress: forEntry.macAddress,
          );
    if (!context.mounted) return;
    await _connect(context, entry);
  }

  Future<void> _connect(
    BuildContext context,
    _Entry entry, {
    bool freshPairing = false,
  }) async {
    // A paired computer we have no address for. Asking is the only thing that
    // can help, and it is what the user would have to do anyway — the
    // alternative was hiding the row, which taught them nothing.
    final host = entry.host;
    if (host == null) {
      await _promptForAddress(context, forEntry: entry);
      return;
    }

    final client = await ref.read(clientProvider.future);
    if (!context.mounted) return;

    // Passing the stored key turns the handshake from trust-on-first-use into
    // strict verification, so a substituted server is rejected rather than
    // prompting to re-pair — which is exactly the dialog an attacker who took
    // over the address would want the user to see.
    await client.connect(
      ConnectionTarget(
        host: host,
        port: entry.port,
        deviceId: entry.id,
        serverPublicKey: freshPairing ? null : entry.publicKey,
        displayName: entry.name,
      ),
    );

    // Remember where it answered. Only pairing and the automatic reconnect used
    // to record this, so a computer reached from this list any other way — by
    // typing its address, or after a DHCP lease moved it — left the stored
    // address stale or absent, and the next launch had nothing to dial.
    unawaited(_rememberAddress(entry.id, host));

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => entry.isPaired && !freshPairing
            ? const ControlScreen()
            : PairingScreen(
                deviceName: entry.name,
                address: host,
                platform: entry.platform,
              ),
      ),
    );
  }

  /// Stores the address a computer just answered at, for the next launch.
  Future<void> _rememberAddress(DeviceId? id, String host) async {
    if (id == null) return;
    final store = await ref.read(trustStoreProvider.future);
    final peer = await store.findById(id);
    if (peer == null) return;
    if (peer.lastAddress == host) return;

    await store.upsert(peer.copyWith(lastAddress: host));
    await persistTrustStore(
      store,
      await ref.read(identityStoreProvider.future),
    );
    ref.invalidate(trustedPeersProvider);
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

  /// Sends a Wake-on-LAN magic packet, after telling the user what it needs.
  ///
  /// The confirmation step is not ceremony. Wake-on-LAN depends on three
  /// settings the phone cannot see and cannot check — firmware, driver, and
  /// whether the machine is on Ethernet at all — and it reports nothing back,
  /// so a bare button that fires and shrugs leaves the user with no idea
  /// whether to wait, retry, or go and change a BIOS setting. Saying so before
  /// the packet goes out is the only place the explanation is useful.
  Future<void> _wake(BuildContext context, _Entry entry) async {
    final mac = entry.macAddress;
    if (mac == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _WakeDialog(name: entry.name, mac: mac),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final attempt = await ref
        .read(wakeOnLanSenderProvider)
        .wake(mac, lastKnownAddress: entry.host);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          attempt.anyDelivered
              // Deliberately not "waking up": nothing acknowledges a magic
              // packet, so claiming the computer is waking would be a guess
              // presented as a fact.
              ? 'Wake-up sent to ${entry.name}. Give it up to a minute, then '
                  'search again.'
              : 'This network refused the wake-up broadcast. It cannot be sent '
                  'from a mobile data connection or a guest network.',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
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
  const _ManualAddressDialog({this.knownName});

  /// The computer this address is for, when it is already paired.
  ///
  /// Only changes what the dialog says. Being told "Where is Ahmed's MacBook?"
  /// rather than "Connect by address" is the difference between answering a
  /// question about a machine you own and being asked to configure something.
  final String? knownName;

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
        title: Text(
          widget.knownName == null
              ? 'Connect by address'
              : 'Where is ${widget.knownName}?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Remote Link on your computer shows its address under '
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
    this.onWake,
  });

  final _Entry entry;
  final bool wasRevoked;
  final VoidCallback? onTap;
  final VoidCallback? onPairAgain;
  final VoidCallback? onRename;

  /// Null unless this computer is paired, absent, and has a known hardware
  /// address — the only combination where waking it is a real option.
  final VoidCallback? onWake;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ListTile(
        minTileHeight: 78,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: (entry.isLive ? scheme.primary : scheme.onSurfaceVariant)
                .withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            switch (entry.platform) {
              PlatformKind.macos => Icons.laptop_mac_rounded,
              PlatformKind.windows => Icons.laptop_windows_rounded,
              _ => Icons.computer_rounded,
            },
            // The platform is carried by the glyph alone. `ListTile` merges its
            // children into one node, so this is announced ahead of the name:
            // "Mac, Ahmed's iMac, Paired".
            semanticLabel: switch (entry.platform) {
              PlatformKind.macos => 'Mac',
              PlatformKind.windows => 'Windows PC',
              PlatformKind.linux => 'Linux computer',
              _ => 'Computer',
            },
            size: 25,
            // Dimmed when the computer is paired but not currently announcing: the
            // address may be stale, and the tap may fail. Better to show it looking
            // uncertain than to hide it or pretend it is online.
            color: entry.isLive
                ? null
                : scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        title: Text(entry.name),
        subtitle: Text(
          wasRevoked
              ? 'This computer removed your access'
              : switch ((entry.isPaired, entry.isLive)) {
                  _ when entry.host == null =>
                    'Paired · tap to enter its address',
                  (true, true) => 'Paired · ${entry.host}',
                  (true, false) =>
                    'Paired · not seen right now · ${entry.host}',
                  (false, true) => 'Tap to pair · ${entry.host}',
                  (false, false) => entry.host!,
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
                      if (onWake != null)
                        TextButton(
                          onPressed: onWake,
                          child: const Text('Wake'),
                        ),
                      if (onRename != null)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Rename computer',
                          onPressed: onRename,
                        ),
                      // Both of these repeat what the subtitle already says —
                      // "Paired · 192.168.1.4", or that the row is tappable.
                      // Excluded rather than labelled: the fix for an unlabelled
                      // icon is not always a label.
                      ExcludeSemantics(
                        child:
                            Icon(Icons.verified_rounded, color: scheme.primary),
                      ),
                    ],
                  )
                : const ExcludeSemantics(
                    child: Icon(Icons.chevron_right_rounded),
                  ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}

/// Explains what Wake-on-LAN needs, then sends the packet.
///
/// Every requirement listed here is one the phone cannot detect and the user
/// cannot infer from a failure, because a failed wake looks exactly like a
/// successful one from this side. Stating them up front is what stops "Wake"
/// from being a button that appears broken on the very common setup — a laptop
/// on Wi-Fi — where it can never work.
class _WakeDialog extends StatelessWidget {
  const _WakeDialog({required this.name, required this.mac});

  final String name;
  final MacAddress mac;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Wake $name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Broadcasts a wake-up packet to ${mac.canonical}.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text('This only works if:', style: textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            '•  The computer is connected by Ethernet cable. Most Wi-Fi '
            'adapters cannot be woken this way.\n'
            '•  Wake-on-LAN is enabled in the computer’s BIOS or UEFI '
            'firmware.\n'
            '•  “Wake on Magic Packet” is enabled for its network adapter in '
            'the operating system.\n'
            '•  This phone is on the same Wi-Fi network, not mobile data.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'A sleeping computer cannot confirm it heard the packet, so '
            'Remote Link cannot tell you whether this worked.',
            style: textTheme.bodySmall,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Send wake-up'),
        ),
      ],
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
  const _Searching({
    required this.discoveryWorks,
    required this.stillLooking,
    required this.onSearchAgain,
  });

  /// False once the platform has actually refused the discovery traffic.
  ///
  /// The two states get different copy on purpose. "Still looking" invites
  /// patience; "this device cannot search" tells the user to stop waiting and
  /// use the button. Showing a spinner forever in the second case is the
  /// failure mode this flag exists to prevent.
  final bool discoveryWorks;

  /// Whether the search is still within the window worth waiting out.
  ///
  /// The flag above only catches discovery that *failed loudly*. Discovery that
  /// succeeds and finds nothing — a network filtering multicast, an iPhone
  /// whose local-network permission was denied — looks identical to discovery
  /// that has not finished yet, and the difference is only ever time. Past the
  /// window this stops being a spinner and becomes an answer.
  final bool stillLooking;

  final Future<void> Function() onSearchAgain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final searching = discoveryWorks && stillLooking;

    return ListView(
      // A scrollable, so pull-to-refresh still works with an empty list.
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 64),
        if (searching)
          const Center(child: CircularProgressIndicator())
        else
          ExcludeSemantics(
            child: Icon(
              Icons.wifi_find_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 24),
        Text(
          switch ((discoveryWorks, stillLooking)) {
            (false, _) => 'This device can\u2019t search automatically',
            (true, true) => 'Looking for computers',
            (true, false) => 'No computers found',
          },
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          switch ((discoveryWorks, stillLooking)) {
            (false, _) => 'iPhones need a special Apple permission to search '
                'the local network, and some Wi-Fi networks block it '
                'entirely.\n\nTap \u201cConnect by address\u201d and enter the '
                'address shown on your computer. Everything else works exactly '
                'the same.',
            (true, true) => 'Make sure Remote Link is running on your computer '
                'and both devices are on the same Wi-Fi network.',
            // Said plainly, because after this long the honest answer is that
            // searching is not going to work here and the user needs the other
            // route. Leaving the spinner up implies waiting will help.
            (true, false) =>
              'Check that Remote Link is running on your computer and that both '
                  'devices are on the same Wi-Fi.\n\nSome networks — guest '
                  'Wi-Fi in particular — block the traffic that finds '
                  'computers automatically. If yours does, tap \u201cConnect by '
                  'address\u201d and enter the address shown on your computer. '
                  'It is remembered afterwards.',
          },
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!searching) ...<Widget>[
          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              onPressed: onSearchAgain,
              icon: const Icon(Icons.refresh),
              label: const Text('Search again'),
            ),
          ),
        ],
      ],
    );
  }
}
