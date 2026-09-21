import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/app_icons.dart';
import '../../app/brand.dart';
import '../../app/providers.dart';
import '../control/control_screen.dart';
import '../host/host_providers.dart';
import '../host/phone_host_service.dart';
import '../pairing/pairing_screen.dart';
import '../pairing/qr_scanner_screen.dart';
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

  /// Where to dial, or null when this computer has been paired with but never
  /// reached at a remembered address.
  ///
  /// Nullable rather than absent from the list. A paired computer with no
  /// address used to be dropped entirely, so the one thing the user was sure
  /// they had set up was the one thing the screen would not show them — and on
  /// a network where discovery finds nothing, that left the list permanently
  /// empty. Showing the row and sending the tap to the scanner is strictly
  /// better than pretending the pairing does not exist.
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
/// open RemoteLink, see your computer, tap it, be in control. There are two
/// ways in and no third: tap a computer the phone found, or scan the code the
/// computer is showing. Typing an address and sending a wake-up packet used to
/// sit here too, and both were removed — the first because scanning carries
/// the address *and* the key, and the second because it could not report
/// whether it had done anything, so it read as a broken button.
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
    final scheme = Theme.of(context).colorScheme;
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
    final connectedPeers = ref.watch(peerLinksProvider);
    final connectedIds = ref.watch(connectedDeviceIdsProvider);
    final entries = _merge(
      discovered,
      paired,
      connectedPeers: connectedPeers,
      connectedIds: connectedIds,
    );
    final clientState = ref.watch(clientStateProvider).valueOrNull;
    final client = ref.watch(clientProvider).valueOrNull;
    final connectedId = ref.watch(connectedDeviceIdProvider);
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
        // "Devices", not "Computers". The list has never been only computers
        // since a phone could advertise itself, and a heading that says
        // otherwise is the app telling the user the phone they can see in the
        // list is not really there.
        title: const Text('Devices'),
        actions: <Widget>[
          IconButton(
            icon: const AppIcon(AppIcons.filter),
            tooltip: 'Search again',
            onPressed: () async {
              _beginSearchWindow();
              final backend = await ref.read(discoveryProvider.future);
              await backend.refresh();
            },
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
      ),
      // The one action on this screen, because tapping a row is the other one
      // and there is no third. It is also the only route that works on a
      // network where discovery is blocked, which is why it is a button on the
      // screen rather than an item in a menu.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _scanCode(context),
        icon: const AppIcon(AppIcons.qrCode),
        label: const Text('Scan code'),
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
              onScanCode: () => _scanCode(context),
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
                  final isConnected =
                      entry.id != null && connectedIds.contains(entry.id);
                  return _DeviceTile(
                    entry: entry,
                    wasRevoked: wasRevoked,
                    isConnected: isConnected,
                    onTap: wasRevoked
                        ? null
                        : isConnected
                            ? () => _resume(context)
                            : () => _connect(
                                  context,
                                  entry,
                                  replacing: connectedId != null,
                                ),
                    onPairAgain:
                        wasRevoked ? () => _pairAgain(context, entry) : null,
                    onDisconnect: isConnected
                        ? () => _disconnect(peerId: entry.id)
                        : null,
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
    List<TrustedPeer> paired, {
    List<PeerLink> connectedPeers = const <PeerLink>[],
    Set<DeviceId> connectedIds = const <DeviceId>{},
  }) {
    final byId = <String, TrustedPeer>{
      for (final peer in paired) peer.id.value: peer,
    };
    final discById = <String, DiscoveredDevice>{
      for (final device in discovered) device.id.value: device,
    };
    final entries = <_Entry>[];
    final seen = <String>{};

    // 1. Any device currently connected (inbound or outbound) is always shown and is live.
    for (final peer in connectedPeers) {
      if (seen.contains(peer.id.value)) continue;
      final storedPeer = byId[peer.id.value];
      final disc = discById[peer.id.value];
      final effectiveName = peer.name.isNotEmpty && peer.name != peer.id.short
          ? peer.name
          : (storedPeer?.name ?? peer.name);
      final effectivePlatform = peer.platform != PlatformKind.unknown
          ? peer.platform
          : (storedPeer?.platform ??
              disc?.beacon.platform ??
              PlatformKind.unknown);

      seen.add(peer.id.value);
      entries.add(
        _Entry(
          id: peer.id,
          name: effectiveName,
          host: disc?.address ?? storedPeer?.lastAddress ?? 'Connected device',
          port: disc?.port ??
              (peer.isHandheld ? kPhoneHostPort : kDefaultServicePort),
          isPaired: storedPeer != null,
          isLive: true,
          platform: effectivePlatform,
          publicKey: storedPeer?.publicKey,
        ),
      );
    }

    // 2. Discovered devices.
    for (final device in discovered) {
      if (seen.contains(device.id.value)) continue;
      final peer = byId[device.id.value];
      seen.add(device.id.value);
      entries.add(
        _Entry(
          id: device.id,
          name: peer?.name ?? device.name,
          host: device.address,
          port: device.port,
          isPaired: peer != null,
          isLive: true,
          platform: device.beacon.platform,
          publicKey: peer?.publicKey,
        ),
      );
    }

    // 3. Paired devices that are neither currently connected nor discovered.
    for (final peer in paired) {
      if (seen.contains(peer.id.value)) continue;
      final address = peer.lastAddress;
      entries.add(
        _Entry(
          id: peer.id,
          name: peer.name,
          host: address,
          port: peer.platform == PlatformKind.android ||
                  peer.platform == PlatformKind.ios
              ? kPhoneHostPort
              : kDefaultServicePort,
          isPaired: true,
          isLive: false,
          platform: peer.platform,
          publicKey: peer.publicKey,
        ),
      );
    }

    entries.sort((a, b) {
      final aConnected = a.id != null && connectedIds.contains(a.id);
      final bConnected = b.id != null && connectedIds.contains(b.id);
      if (aConnected != bConnected) return aConnected ? -1 : 1;
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      if (a.isPaired != b.isPaired) return a.isPaired ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// Opens the camera, and connects to whatever computer the code names.
  ///
  /// The scanned key is passed as the expected server key, which is the entire
  /// reason this path exists: the handshake then either authenticates against
  /// the key the camera read or fails outright, with no window in which an
  /// attacker on the network could substitute their own. That is strictly
  /// stronger than the six digits, and it is why a scan never falls back to
  /// them — see [PairingScreen.viaScannedCode].
  ///
  /// It also happens to carry the address, which is what makes it the answer
  /// on a network where discovery finds nothing.
  Future<void> _scanCode(BuildContext context) async {
    final payload = await Navigator.of(context).push<PairingPayload>(
      MaterialPageRoute<PairingPayload>(
        builder: (_) => const QrScannerScreen(),
      ),
    );
    if (payload == null || !context.mounted) return;

    // Switching computers is still worth asking about, exactly as it is when
    // tapping a row: a scan is a deliberate act, but it is not a decision to
    // drop a transfer that is halfway through.
    final connectedId = ref.read(connectedDeviceIdProvider);
    if (connectedId != null && connectedId != payload.deviceId) {
      if (!await _confirmSwitch(context, payload.name)) return;
      if (!context.mounted) return;
      await _disconnect();
      if (!context.mounted) return;
    }

    final client = await ref.read(clientProvider.future);
    if (!context.mounted) return;

    await client.connect(
      ConnectionTarget(
        host: payload.host,
        port: payload.port,
        deviceId: payload.deviceId,
        serverPublicKey: payload.publicKey,
        displayName: payload.name,
      ),
    );

    unawaited(_rememberAddress(payload.deviceId, payload.host));

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PairingScreen(
          deviceName: payload.name,
          address: payload.host,
          viaScannedCode: true,
        ),
      ),
    );
  }

  /// Goes back to the computer already connected, without reconnecting.
  ///
  /// Tapping the connected row used to run the full [_connect] path, which
  /// dials a socket that is already up. The client replaces the session, the
  /// desktop logs a replaced connection, and the user watches a working link go
  /// down and come back for no reason.
  Future<void> _resume(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ControlScreen()),
    );
  }

  /// Drops the current session and stays on the list.
  ///
  /// The app could reach a connected state and offer no way out of it short of
  /// force-quitting: auto-connect reconnects on launch, and leaving the
  /// touchpad only cancels auto-connect for that one attempt.
  Future<void> _disconnect({DeviceId? peerId}) async {
    // Cancelled first. Without this the supervisor treats the close as a drop
    // and dials straight back in, so the button appears to do nothing.
    ref.read(autoConnectProvider.notifier).cancel();
    final client = await ref.read(clientProvider.future);
    if (peerId == null || client.session?.peerId == peerId) {
      await client.disconnect();
    }
    if (peerId != null) {
      final host = ref.read(phoneHostServiceProvider).valueOrNull;
      if (host != null) {
        await host.disconnectPeer(peerId);
      }
    }
  }

  /// Asks before replacing a live connection with a different computer.
  ///
  /// The transport holds one session at a time, so connecting elsewhere ends
  /// the current one. That is worth a sentence rather than a surprise: the
  /// phone may be mid-transfer, and the person tapping may simply have meant to
  /// look at the other computer's row.
  Future<bool> _confirmSwitch(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch computers?'),
        content: Text(
          'This phone talks to one computer at a time, so connecting to $name '
          'will disconnect the one you are on. Anything still transferring '
          'will stop.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Switch to $name'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _connect(
    BuildContext context,
    _Entry entry, {
    bool freshPairing = false,
    bool replacing = false,
  }) async {
    // A paired computer we have no address for. The code on its screen is the
    // only thing that can supply one, so the tap goes there rather than
    // failing — the alternative was hiding the row, which taught the user
    // nothing at all.
    final host = entry.host;
    if (host == null) {
      await _scanCode(context);
      return;
    }

    if (replacing) {
      if (!await _confirmSwitch(context, entry.name)) return;
      if (!context.mounted) return;
      await _disconnect();
      if (!context.mounted) return;
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

/// The "this is the one you are on" marker.
///
/// Worth calling out rather than leaving to a colour: with several paired
/// computers in the list, which one is live is the single most useful fact on
/// the screen, and it was not represented at all — every row looked equally
/// available, so tapping the wrong one silently replaced a working session.
class _ConnectedSubtitle extends StatelessWidget {
  const _ConnectedSubtitle();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF22A06B),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          'Connected',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
        Flexible(
          child: Text(
            ' · tap for the controls',
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.entry,
    required this.wasRevoked,
    required this.onTap,
    required this.onPairAgain,
    this.isConnected = false,
    this.onDisconnect,
    this.onRename,
  });

  final _Entry entry;
  final bool wasRevoked;

  /// Whether this is the computer the phone is talking to right now.
  final bool isConnected;

  final VoidCallback? onTap;
  final VoidCallback? onPairAgain;

  /// Present only on the connected row.
  final VoidCallback? onDisconnect;

  final VoidCallback? onRename;

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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: (entry.isLive ? scheme.primary : scheme.onSurfaceVariant)
                .withValues(alpha: isConnected ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(15),
          ),
          child: AppIcon(
            switch (entry.platform) {
              PlatformKind.macos => AppIcons.monitorSmartphone,
              PlatformKind.windows => AppIcons.monitorSmartphone,
              _ => AppIcons.monitorSmartphone,
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
            size: 28,
            color: scheme.onSurfaceVariant,
          ),
        ),
        // The badge sits on the second line rather than beside the name.
        // Sharing the title row with it cost about a third of the width, and
        // computer names are long — a Mac is called `Ahmeds-MacBook-Air.local`
        // out of the box, so the row that mattered most was the one whose name
        // was clipped to `Ahmeds-…`.
        title: Text(entry.name, overflow: TextOverflow.ellipsis),
        subtitle: isConnected
            ? const _ConnectedSubtitle()
            : Text(
                wasRevoked
                    ? 'This computer removed your access'
                    : switch ((entry.isPaired, entry.isLive)) {
                        _ when entry.host == null =>
                          'Paired · tap to scan its code',
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
            : isConnected
                ? TextButton(
                    onPressed: onDisconnect,
                    child: const Text('Disconnect'),
                  )
                : entry.isPaired
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (onRename != null)
                            IconButton(
                              icon: AppIcon(
                                AppIcons.edit,
                                color: scheme.onSurfaceVariant,
                              ),
                              tooltip: 'Rename computer',
                              onPressed: onRename,
                            ),
                          // Both of these repeat what the subtitle already says —
                          // "Paired · 192.168.1.4", or that the row is tappable.
                          // Excluded rather than labelled: the fix for an unlabelled
                          // icon is not always a label.
                          ExcludeSemantics(
                            child: AppIcon(
                              AppIcons.qrCode,
                              size: 18,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      )
                    : const ExcludeSemantics(
                        child: AppIcon(AppIcons.qrCode, size: 18),
                      ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
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
    required this.onScanCode,
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

  /// The way in when searching cannot work, offered right here rather than
  /// left to the button at the bottom of the screen. This is the moment the
  /// user needs it, and a paragraph pointing at a control somewhere else is
  /// how an empty screen becomes a dead end.
  final VoidCallback onScanCode;

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
            child: AppIcon(
              AppIcons.qrCode,
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
                'entirely.\n\nScan the code your computer shows instead — it '
                'carries the address, so searching is not needed. Everything '
                'else works exactly the same.',
            (true, true) => 'Make sure Remote Link is running on your computer '
                'and both devices are on the same Wi-Fi network.',
            // Said plainly, because after this long the honest answer is that
            // searching is not going to work here and the user needs the other
            // route. Leaving the spinner up implies waiting will help.
            (true, false) =>
              'Check that Remote Link is running on your computer and that both '
                  'devices are on the same Wi-Fi.\n\nSome networks — guest '
                  'Wi-Fi in particular — block the traffic that finds '
                  'computers automatically. If yours does, click '
                  '\u201cPair a phone\u201d on the computer and scan the code '
                  'it shows. It is remembered afterwards.',
          },
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!searching) ...<Widget>[
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: onScanCode,
              icon: const AppIcon(AppIcons.qrCode),
              label: const Text('Scan code'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: onSearchAgain,
              icon: const AppIcon(AppIcons.settings),
              label: const Text('Search again'),
            ),
          ),
        ],
      ],
    );
  }
}
