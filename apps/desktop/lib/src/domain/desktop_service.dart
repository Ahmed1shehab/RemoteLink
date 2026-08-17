import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'bonjour_advertiser.dart';
import 'clipboard_sync.dart';
import 'command_dispatcher.dart';
import 'file_transfer_store.dart';
import 'transfer_model.dart';

/// Everything the desktop advertises it can do.
///
/// Assembled at run time rather than hard-coded, because two of these depend on
/// permissions the user may not have granted. A phone that never sees
/// `Capabilities.mouse` never shows a touchpad, which is far better than
/// showing one that silently does nothing.
Capabilities buildCapabilities({
  required bool inputAvailable,
  required bool clipboardAvailable,
  required bool mediaAvailable,
  bool gesturesAvailable = false,
  bool brightnessAvailable = false,
}) {
  var capabilities = const Capabilities(
    Capabilities.powerControl |
        Capabilities.launchApps |
        Capabilities.compression |
        Capabilities.sessionResumption,
  );
  if (inputAvailable) {
    capabilities = capabilities
        .plus(Capabilities.mouse)
        .plus(Capabilities.keyboard)
        .plus(Capabilities.presentation);
  }
  if (clipboardAvailable) {
    capabilities = capabilities.plus(Capabilities.clipboardText);
  }
  if (mediaAvailable) {
    // Advertised only when a real backend exists, so a Windows build — where
    // the WinRT media session is not yet bound — does not offer a media tab
    // whose buttons would do nothing.
    capabilities = capabilities
        .plus(Capabilities.mediaControl)
        .plus(Capabilities.mediaMetadata);
  }
  if (gesturesAvailable) {
    // Advertised only when native synthetic gestures exist (macOS). Windows
    // approximates gestures via keyboard shortcuts and does not claim native
    // gesture support.
    capabilities = capabilities.plus(Capabilities.gestures);
  }
  if (brightnessAvailable) {
    // Advertised only when a working brightness backend is detected.
    capabilities = capabilities.plus(Capabilities.brightness);
  }
  return capabilities;
}

/// A live connection as the desktop UI sees it.
final class ConnectedDevice {
  ConnectedDevice({
    required this.serverSession,
    required this.tier,
    required this.name,
  });

  final ServerSession serverSession;
  final PermissionTier tier;
  final String name;

  DeviceId get id => serverSession.peerId;
  String get address => serverSession.address;
  bool get awaitingPairing => serverSession.awaitingPairing;
  ConnectionQuality get quality => serverSession.session.currentQuality;
}

/// A pairing request waiting on the user.
final class PendingPairing {
  PendingPairing({
    required this.session,
    required this.shortAuthenticationString,
    required this.peerId,
    required this.peerName,
    required this.platform,
    required this.requestedAt,
  });

  final ServerSession session;

  /// Six digits the user compares against the phone's screen.
  final String shortAuthenticationString;

  final DeviceId peerId;
  final String peerName;
  final PlatformKind platform;
  final DateTime requestedAt;
}

/// Orchestrates the desktop side: listener, discovery beacon, input, clipboard.
///
/// Deliberately free of Flutter imports. The service is the whole product; the
/// UI is a window onto it that the user closes most of the time. Keeping the
/// dependency in that direction means the service can be driven from a test or
/// a headless build without an engine.
final class DesktopService {
  DesktopService({
    required this.identity,
    required this.trustStore,
    required this.deviceName,
    required this.appVersion,
    required Clock clock,
    this.servicePort = kDefaultServicePort,
    InputBackend? input,
    ClipboardBackend? clipboardBackend,
    MediaBackend? media,
    BrightnessBackend? brightness,
    SystemInfoBackend? systemInfo,
    NetworkAdapterBackend? networkAdapters,
    this.incomingTransferStore,
  })  : _clock = clock,
        _input = input ?? NativeBackends.createInput(),
        _clipboardBackend =
            clipboardBackend ?? NativeBackends.createClipboard(),
        _media = media ?? NativeBackends.createMedia(),
        _brightness = brightness ?? NativeBackends.createBrightness(),
        _systemInfo = systemInfo ?? NativeBackends.createSystemInfo(),
        _networkAdapters =
            networkAdapters ?? NativeBackends.createNetworkAdapters();

  final DeviceIdentity identity;
  final TrustStore trustStore;
  final String deviceName;
  final String appVersion;
  final int servicePort;
  final IncomingTransferStore? incomingTransferStore;

  final Clock _clock;
  final InputBackend _input;
  final ClipboardBackend _clipboardBackend;
  final MediaBackend _media;
  final BrightnessBackend _brightness;
  final SystemInfoBackend _systemInfo;
  final NetworkAdapterBackend _networkAdapters;
  final Log _log = Log.scoped('desktop.service');

  late final PairingCoordinator _pairing = PairingCoordinator(
    identity: identity,
    clock: _clock,
  );

  late final ClipboardSyncService clipboard = ClipboardSyncService(
    clipboard: _clipboardBackend,
    localDeviceId: identity.id,
    clock: _clock,
  );

  late final CommandDispatcher _dispatcher = CommandDispatcher(
    input: _input,
    platform: NativeBackends.currentPlatform,
    onClipboardUpdate: _onRemoteClipboard,
    onPowerCommand: _onPowerCommand,
    onLaunchApplication: _onLaunchApplication,
    onOpenUrl: _onOpenUrl,
    onRunCommand: _onRunCommand,
    onMediaCommand: _onMediaCommand,
    onVolumeCommand: _onVolumeCommand,
    onBrightnessCommand: _onBrightnessCommand,
    onDeviceRename: _onDeviceRename,
    onFileTransferMessage: _onFileTransferMessage,
  );

  RemoteLinkServer? _server;
  UdpDiscoveryServer? _beacon;
  BonjourAdvertiser? _bonjour;

  final Map<String, ConnectedDevice> _devices = <String, ConnectedDevice>{};
  final Map<String, StreamSubscription<Message>> _messageSubscriptions =
      <String, StreamSubscription<Message>>{};
  final Map<String, FileTransferReceiver> _transferReceivers =
      <String, FileTransferReceiver>{};
  DeviceId? _activeSessionPeerId;

  final Map<String, TransferRecord> _transfers = <String, TransferRecord>{};
  final Map<String, Map<String, OutgoingFile>> _outgoingSources =
      <String, Map<String, OutgoingFile>>{};
  final Map<String, FileOffer> _outgoingOffers = <String, FileOffer>{};
  final Map<String, DeviceId> _outgoingPeerIds = <String, DeviceId>{};
  final Map<String, Completer<void>> _activeSendCompleters =
      <String, Completer<void>>{};
  final Map<String, TransferSpeedTracker> _speedTrackers =
      <String, TransferSpeedTracker>{};
  final Set<String> _knownPeersWithTransfers = <String>{};

  final StreamController<List<ConnectedDevice>> _deviceChanges =
      StreamController<List<ConnectedDevice>>.broadcast();
  final StreamController<PendingPairing> _pairingRequests =
      StreamController<PendingPairing>.broadcast();
  final StreamController<PendingIncomingTransfer> _incomingTransferRequests =
      StreamController<PendingIncomingTransfer>.broadcast();
  final StreamController<List<TransferRecord>> _transferChanges =
      StreamController<List<TransferRecord>>.broadcast();

  StreamSubscription<ServerSession>? _acceptedSubscription;
  StreamSubscription<ServerSession>? _endedSubscription;
  StreamSubscription<ClipboardUpdate>? _clipboardSubscription;

  /// Connected devices, updated as they come and go.
  Stream<List<ConnectedDevice>> get deviceChanges => _deviceChanges.stream;

  /// Pairing requests awaiting the user's confirmation.
  Stream<PendingPairing> get pairingRequests => _pairingRequests.stream;

  /// Incoming transfer requests awaiting explicit user approval.
  Stream<PendingIncomingTransfer> get incomingTransferRequests =>
      _incomingTransferRequests.stream;

  /// Transfer changes for real-time progress and status updates.
  Stream<List<TransferRecord>> get transferChanges => _transferChanges.stream;

  List<TransferRecord> get transfers => _transfers.values.toList();

  List<ConnectedDevice> get devices => _devices.values.toList();

  bool get isRunning => _server?.isRunning ?? false;

  bool get inputAvailable => _input.isAvailable;

  String? get inputUnavailableReason => _input.unavailableReason;

  bool get clipboardAvailable => _clipboardBackend.isAvailable;

  String? get clipboardUnavailableReason => _clipboardBackend.isAvailable
      ? null
      : (_clipboardBackend is UnsupportedClipboardBackend
          ? 'Clipboard sync is not supported on ${NativeBackends.currentPlatform.name}'
          : 'Clipboard backend unavailable');

  bool get mediaAvailable => _media.isAvailable;

  String? get mediaUnavailableReason => _media.isAvailable
      ? null
      : (_media is UnsupportedMediaBackend
          ? 'Media control is not supported on ${NativeBackends.currentPlatform.name}'
          : 'Media backend unavailable');

  bool get brightnessAvailable => _brightness.isAvailable;

  String? get brightnessUnavailableReason => _brightness.unavailableReason;

  int get commandAppliedCount => _dispatcher.appliedCount;

  int get commandDeniedCount => _dispatcher.deniedCount;

  int get commandUnsupportedCount => _dispatcher.unsupportedCount;

  /// Capabilities computed from the backends' *current* state.
  ///
  /// Recomputed on every read rather than cached at startup, because on macOS
  /// Accessibility permission can be granted while the service is running.
  Capabilities get currentCapabilities => buildCapabilities(
        inputAvailable: _input.isAvailable,
        clipboardAvailable: _clipboardBackend.isAvailable,
        mediaAvailable: _media.isAvailable,
        gesturesAvailable: _input.isAvailable && _input is MacosInputBackend,
        brightnessAvailable: _brightness.isAvailable,
      );

  /// The desk's monitor layout, or `null` when the host cannot report one.
  ///
  /// Null rather than an empty topology on a backend that enumerates nothing:
  /// an empty list is a positive claim that there are no screens, and a phone
  /// that believed it would hide the touchpad on a machine whose only problem
  /// is a missing Accessibility grant.
  ScreenTopology? get currentTopology {
    final monitors = _input.monitors;
    if (monitors.isEmpty) return null;
    return ScreenTopology(<MonitorDescriptor>[
      for (final monitor in monitors)
        MonitorDescriptor(
          id: monitor.id,
          x: monitor.bounds.x,
          y: monitor.bounds.y,
          width: monitor.bounds.width,
          height: monitor.bounds.height,
          scaleFactor: monitor.scaleFactor,
          isPrimary: monitor.isPrimary,
          name: monitor.name,
        ),
    ]);
  }

  /// Emits whenever input availability flips.
  ///
  /// Drives the desktop's permission banner. `AXIsProcessTrusted` offers no
  /// notification, so this is polled — but the call is a cheap framework
  /// lookup, and a two-second poll costs nothing measurable while turning a
  /// permanently stuck error banner into one that clears itself the moment the
  /// user grants access.
  Stream<bool> get inputAvailabilityChanges => _inputAvailability.stream;

  final StreamController<bool> _inputAvailability =
      StreamController<bool>.broadcast();

  Timer? _permissionWatch;
  bool? _lastInputAvailable;

  int get boundPort => _server?.boundPort ?? servicePort;

  /// LAN addresses a phone can dial, most likely first.
  ///
  /// The status card used to show only the `.local` hostname, which is useless
  /// for the one case where the user needs to read an address off the screen:
  /// typing it into a phone that cannot discover automatically. Resolving
  /// `.local` needs mDNS, which is precisely what is unavailable in that
  /// situation.
  List<String> get localAddresses => _localAddresses;

  List<String> _localAddresses = const <String>[];

  /// Hardware address of the adapter this computer is reachable on, if known.
  ///
  /// Advertised to paired phones so they can wake this machine once it sleeps.
  /// Null until [start] has enumerated interfaces, and on any host where the
  /// reachable address belongs to no adapter with a hardware address.
  MacAddress? get localMacAddress => _localMacAddress;

  MacAddress? _localMacAddress;

  Future<void> _refreshLocalAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final addresses = <String>[
        for (final interface in interfaces)
          for (final address in interface.addresses) address.address,
      ]..sort((a, b) {
          // Private ranges first: a Docker or VPN adapter often sorts ahead
          // alphabetically while being unreachable from the phone.
          bool isHomeLan(String ip) =>
              ip.startsWith('192.168.') || ip.startsWith('10.');
          if (isHomeLan(a) != isHomeLan(b)) return isHomeLan(a) ? -1 : 1;
          return a.compareTo(b);
        });
      _localAddresses = addresses;
      await selectLocalMacAddress(addresses);
    } on OSError catch (e) {
      _log.warn('could not enumerate network interfaces', error: e);
    }
  }

  /// Chooses which of this machine's hardware addresses to advertise.
  ///
  /// A computer has several. A MacBook on Ethernet has a Wi-Fi MAC that is
  /// switched off, a Thunderbolt bridge, and an `awdl0`; a Windows desktop adds
  /// a Hyper-V switch and whatever the VPN client installed. Picking the wrong
  /// one is invisible from here and permanent on the phone: the stored address
  /// is well-formed, the packet is sent, and nothing ever wakes.
  ///
  /// So the choice is made by matching, not by guessing at names — the adapter
  /// selected is the one carrying the address the service is actually answering
  /// on, which is the same address the phone connected to.
  /// [reachableAddresses] arrives already sorted with the most plausible LAN
  /// address first, so the first match is the right one.
  ///
  /// Takes the addresses as an argument, and is public, for the same reason
  /// [telemetryTick] is: reaching this through [start] would mean binding a TCP
  /// listener, a UDP beacon, and a Bonjour advertiser to observe one field, and
  /// letting it read whatever interfaces the test machine happens to have would
  /// make the assertion depend on the network the tests run on.
  Future<void> selectLocalMacAddress(List<String> reachableAddresses) async {
    if (!_networkAdapters.isAvailable) return;

    try {
      final adapters = await _networkAdapters.adapters();
      for (final address in reachableAddresses) {
        final adapter = adapterCarrying(adapters, address);
        final mac = adapter?.macAddress;
        // A multicast or all-zero address identifies no machine, so it is
        // dropped here rather than advertised and broadcast to for nothing.
        if (mac == null || !mac.isWakeable) continue;
        _localMacAddress = mac;
        _log.info(
          'advertising a hardware address for wake-on-lan',
          fields: <String, Object?>{
            'interface': adapter?.name,
            'address': address,
          },
        );
        return;
      }
      _log.debug(
        () => 'no adapter matched a reachable address; '
            'wake-on-lan will not be offered',
      );
    } on Object catch (e) {
      // Enumeration reaches the platform through FFI, and a failure there must
      // not take down a service whose actual job — listening for phones — does
      // not depend on it at all.
      _log.warn('could not read hardware addresses', error: e);
    }
  }

  /// Whether new devices may pair right now.
  bool acceptsNewPairings = true;

  /// Starts listening and announcing.
  Future<void> start() async {
    if (_server != null) return;

    final server = RemoteLinkServer(
      identity: identity,
      capabilities: currentCapabilities,
      trustStore: trustStore,
      clock: _clock,
      port: servicePort,
    );
    await server.start();
    _server = server;

    _acceptedSubscription =
        server.accepted.listen((session) => unawaited(_onAccepted(session)));
    _endedSubscription =
        server.ended.listen((session) => unawaited(_onEnded(session)));

    clipboard.start();
    _clipboardSubscription = clipboard.outbound.listen(
      (update) => unawaited(_broadcastClipboard(update)),
    );

    // Both advertisers read live state on every announcement rather than
    // holding a snapshot, so the session count, pairing availability, and
    // capabilities a phone sees are always current without anything having to
    // remember to push updates.
    final beacon = UdpDiscoveryServer(describe: _describeBeacon);
    await beacon.start();
    _beacon = beacon;

    // Bonjour runs in addition to the UDP beacon, not instead of it. An iPhone
    // cannot receive the UDP beacon at all without Apple's multicast
    // entitlement, and Bonjour is explicitly exempt from that requirement.
    final bonjour = BonjourAdvertiser(describe: _describeBeacon);
    await bonjour.start();
    _bonjour = bonjour;

    _startPermissionWatch();
    _startMediaWatch();
    _startSystemWatch();
    await _refreshLocalAddresses();

    _log.info(
      'desktop service started',
      fields: <String, Object?>{
        'port': server.boundPort,
        'device': identity.id.value,
        'input': _input.isAvailable,
      },
    );
  }

  /// This computer's identity, sent to a phone once the session is usable.
  ///
  /// The platform field is not cosmetic. The phone renders a keyboard with
  /// Command or Windows keys, and resolves nothing itself — so without being
  /// told which OS it is driving, it would have to guess, and a keyboard with
  /// the wrong modifier key is worse than no keyboard.
  /// The hardware address is included for a narrower reason: it is the only
  /// thing that still works once this computer is asleep. Everything else here
  /// is useless to a phone facing a machine that has stopped answering.
  DeviceInfo describeSelf() => DeviceInfo(
        id: identity.id,
        name: deviceName,
        platform: NativeBackends.currentPlatform,
        role: PeerRole.server,
        appVersion: appVersion,
        macAddress: _localMacAddress,
      );

  /// This computer as it appears to a phone, built fresh on every call.
  ///
  /// Shared by the UDP beacon and the Bonjour advertisement so the two can
  /// never drift — a client that finds this computer either way builds the same
  /// [Beacon] and nothing downstream cares which route found it.
  Beacon _describeBeacon() => Beacon(
        kind: BeaconKind.announce,
        deviceId: identity.id,
        name: deviceName,
        platform: NativeBackends.currentPlatform,
        servicePort: boundPort,
        protocolVersion: kProtocolVersion,
        publicKeyFingerprint: Uint8List.sublistView(identity.publicKey, 0, 8),
        // Live, not a captured snapshot. Granting Accessibility mid-session
        // must start advertising mouse and keyboard on the next announcement,
        // otherwise the phone keeps hiding its touchpad until a restart.
        capabilities: currentCapabilities,
        acceptsNewPairings: acceptsNewPairings,
        activeSessions: _server?.sessionCount ?? 0,
      );

  /// Watches for Accessibility permission being granted or revoked.
  ///
  /// There is no notification API for this, so it is polled. The check is a
  /// cheap framework call and the interval is generous; the alternative is a
  /// permission banner that never clears and a beacon that keeps advertising
  /// stale capabilities until the app is restarted.
  void _startPermissionWatch() {
    _lastInputAvailable = _input.isAvailable;
    _inputAvailability.add(_lastInputAvailable!);

    _permissionWatch = Timer.periodic(const Duration(seconds: 2), (_) {
      final available = _input.isAvailable;
      if (available == _lastInputAvailable) return;
      _lastInputAvailable = available;

      // New sessions must be offered the updated capability set. Existing
      // sessions negotiated theirs at handshake time and keep it until they
      // reconnect — renegotiating mid-session is not something the protocol
      // supports, and pretending otherwise would be worse than the wait.
      _server?.capabilities = currentCapabilities;

      // The UDP beacon picks this up on its next tick for free, but a DNS-SD
      // TXT record is only read at resolve time, so it has to be republished.
      unawaited(_bonjour?.refresh() ?? Future<void>.value());

      _log.info(
        'input availability changed',
        fields: <String, Object?>{'available': available},
      );
      if (!_inputAvailability.isClosed) _inputAvailability.add(available);
    });
  }

  Future<void> _onAccepted(ServerSession session) async {
    final peer = await trustStore.findByPublicKey(
      session.handshake.peerStaticPublicKey,
    );

    final tier = peer == null
        ? PermissionTier.readOnly
        : PermissionTier.fromWire(peer.permissionTier);

    _devices[session.peerId.value] = ConnectedDevice(
      serverSession: session,
      tier: tier,
      name: peer?.name ?? session.peerId.short,
    );
    _publishDevices();

    final store = incomingTransferStore;
    if (store != null) {
      _transferReceivers[session.peerId.value] = FileTransferReceiver(
        exporterSecret: session.session.exporterSecret,
        store: store,
        storageNamespace: session.peerId.value,
      );
    }

    _messageSubscriptions[session.peerId.value] = session.session.messages
        .listen((message) => unawaited(_onMessage(session, message)));

    if (session.awaitingPairing) {
      if (!acceptsNewPairings) {
        await session.session.close(reason: CloseReason.userRequested);
        return;
      }

      final rejection = _pairing.checkRateLimit(session.peerId);
      if (rejection != null) {
        _log.warn(
          'pairing refused by rate limit',
          fields: <String, Object?>{'peer': session.peerId.value},
        );
        await session.session.close(reason: CloseReason.userRequested);
        return;
      }

      _pairing.begin(
        handshake: session.handshake,
        method: PairingMethod.numericComparison,
        peerName: session.peerId.short,
      );

      if (!_pairingRequests.isClosed) {
        _pairingRequests.add(
          PendingPairing(
            session: session,
            shortAuthenticationString:
                session.handshake.shortAuthenticationString,
            peerId: session.peerId,
            peerName: session.peerId.short,
            platform: PlatformKind.unknown,
            requestedAt: _clock.now(),
          ),
        );
      }
      return;
    }

    // A trusted device gets its tier and the current clipboard immediately, so
    // the first paste after connecting already has the right content rather
    // than waiting for the next copy.
    await session.session.send(PermissionGrant(tier: tier));
    await session.session.send(DeviceInfoMessage(describeSelf()));

    // Before the first tap, not on request. A phone that has to ask for the
    // layout would spend its first absolute move addressing the whole virtual
    // desktop, which is exactly the mis-aimed tap this feature removes.
    final topology = currentTopology;
    if (topology != null) await session.session.send(topology);

    final snapshot = await clipboard.snapshot();
    if (snapshot != null) await session.session.send(snapshot);
  }

  Future<void> _onMessage(ServerSession session, Message message) async {
    final device = _devices[session.peerId.value];
    if (device == null) return;

    switch (message) {
      case DeviceInfoMessage():
        final sanitised = sanitiseDeviceName(message.info.name);
        final effectiveName = sanitised ?? device.name;
        _devices[session.peerId.value] = ConnectedDevice(
          serverSession: session,
          tier: device.tier,
          name: effectiveName,
        );
        _publishDevices();

      case ClipboardRequest():
        final snapshot = await clipboard.snapshot();
        if (snapshot != null) await session.session.send(snapshot);

      case DeviceRename():
        _activeSessionPeerId = session.peerId;
        try {
          _dispatcher.dispatch(message, device.tier);
        } finally {
          _activeSessionPeerId = null;
        }

      default:
        _activeSessionPeerId = session.peerId;
        try {
          final applied = _dispatcher.dispatch(message, device.tier);
          if (!applied && message is FileOffer) {
            await session.session.send(
              FileAbort(
                transferId: message.transferId,
                reason: FileAbortReason.declined,
              ),
            );
          }
        } finally {
          _activeSessionPeerId = null;
        }
    }
  }

  Future<void> _onEnded(ServerSession session) async {
    await _messageSubscriptions.remove(session.peerId.value)?.cancel();
    _devices.remove(session.peerId.value);
    await _transferReceivers.remove(session.peerId.value)?.dispose();
    _publishDevices();

    // Releasing held input is not optional. Without it a session that dropped
    // mid-drag leaves the mouse button down, or a session that dropped with
    // Shift held leaves it latched — states the user cannot fix from the phone.
    _dispatcher.onSessionEnded();

    _log.info(
      'session ended',
      fields: <String, Object?>{'peer': session.peerId.value},
    );
  }

  /// Approves a pending pairing request.
  ///
  /// Called only after the user has confirmed the six digits match. The trust
  /// record is built from the handshake result, never from anything the peer
  /// claimed, so a device cannot register a key it does not hold.
  Future<void> approvePairing(
    PendingPairing request, {
    PermissionTier tier = PermissionTier.standard,
    String? name,
  }) async {
    final peer = _pairing.accept(
      handshake: request.session.handshake,
      peerName: name ?? request.peerName,
      platform: request.platform,
      permissionTier: tier.wireValue,
      lastAddress: request.session.address,
    );
    await trustStore.upsert(peer);

    request.session.session.completePairing();
    await request.session.session.send(PermissionGrant(tier: tier));

    // Also sent here, not only on the already-trusted path. A phone that paired
    // by typing an address has no beacon and therefore no idea what it just
    // connected to — it would render a Windows keyboard against a Mac until the
    // next reconnect.
    await request.session.session.send(DeviceInfoMessage(describeSelf()));

    final topology = currentTopology;
    if (topology != null) await request.session.session.send(topology);

    _devices[request.peerId.value] = ConnectedDevice(
      serverSession: request.session,
      tier: tier,
      name: peer.name,
    );
    _publishDevices();

    final snapshot = await clipboard.snapshot();
    if (snapshot != null) await request.session.session.send(snapshot);

    _log.info(
      'paired',
      fields: <String, Object?>{
        'peer': request.peerId.value,
        'tier': tier.name
      },
    );
  }

  /// Declines a pending pairing request.
  Future<void> declinePairing(PendingPairing request) async {
    _pairing.reject(
      peerId: request.peerId,
      reason: PairRejectReason.declined,
    );
    await request.session.session.close(reason: CloseReason.userRequested);
  }

  /// Revokes a device and drops it immediately.
  Future<void> revoke(DeviceId peerId) async {
    await _server?.revokePeer(peerId);
    _devices.remove(peerId.value);
    _publishDevices();
  }

  /// Changes a connected device's permission tier and tells it.
  Future<void> setTier(DeviceId peerId, PermissionTier tier) async {
    final device = _devices[peerId.value];
    if (device == null) return;

    final peer = await trustStore.findById(peerId);
    if (peer != null) {
      await trustStore.upsert(peer.copyWith(permissionTier: tier.wireValue));
    }

    _devices[peerId.value] = ConnectedDevice(
      serverSession: device.serverSession,
      tier: tier,
      name: device.name,
    );
    _publishDevices();

    await device.serverSession.session.send(PermissionGrant(tier: tier));
  }

  /// Renames a paired device locally from the desktop UI.
  ///
  /// Sanitises the input, persists it to the trust store, and updates the
  /// connected device list. Returns `true` if valid and applied, `false` if rejected.
  Future<bool> renameDevice(DeviceId peerId, String rawName) async {
    final sanitised = sanitiseDeviceName(rawName);
    if (sanitised == null) return false;

    await _renamePeer(peerId, sanitised);
    return true;
  }

  void _onDeviceRename(DeviceRename command) {
    final peerId = _activeSessionPeerId;
    if (peerId == null) return;
    unawaited(_renamePeer(peerId, command.name));
  }

  void _onFileTransferMessage(Message message) {
    final peerId = _activeSessionPeerId;
    if (peerId == null) return;
    unawaited(_handleFileTransferMessage(peerId, message));
  }

  void _publishTransfers() {
    if (!_transferChanges.isClosed) {
      _transferChanges.add(_transfers.values.toList());
    }
  }

  Future<void> _handleFileTransferMessage(
    DeviceId peerId,
    Message message,
  ) async {
    final device = _devices[peerId.value];
    final receiver = _transferReceivers[peerId.value];
    if (device == null || receiver == null) {
      if (message is FileOffer && device != null) {
        await device.serverSession.session.send(
          FileAbort(
            transferId: message.transferId,
            reason: FileAbortReason.ioError,
          ),
        );
      }
      return;
    }

    try {
      switch (message) {
        case FileOffer():
          if (!device.tier.canTransferFiles) {
            await device.serverSession.session.send(
              FileAbort(
                transferId: message.transferId,
                reason: FileAbortReason.declined,
              ),
            );
            return;
          }

          final isFirst = !_knownPeersWithTransfers.contains(peerId.value);
          final destinationPath = incomingTransferStore is FileTransferStore
              ? (incomingTransferStore as FileTransferStore).destination.path
              : '';

          final request = PendingIncomingTransfer(
            transferId: message.transferId,
            peerId: peerId,
            peerName: device.name,
            offer: message,
            isFirstTransferFromDevice: isFirst,
            destinationPath: destinationPath,
          );

          final record = TransferRecord(
            transferId: message.transferId,
            peerId: peerId,
            peerName: device.name,
            direction: TransferDirection.incoming,
            status: TransferStatus.prompting,
            files: <TransferFileProgress>[
              for (final f in message.files)
                TransferFileProgress(
                  fileId: f.fileId,
                  fileName: f.fileName,
                  totalBytes: f.size,
                  transferredBytes: 0,
                ),
            ],
            totalBytes: message.files.fold(0, (sum, f) => sum + f.size),
            transferredBytes: 0,
            createdAt: DateTime.now(),
          );

          _speedTrackers[message.transferId] = TransferSpeedTracker();
          _transfers[message.transferId] = record;
          _publishTransfers();

          _incomingTransferRequests.add(request);

        case FileAccept():
          final sources = _outgoingSources[message.transferId];
          final offer = _outgoingOffers[message.transferId];
          if (sources != null && offer != null) {
            final sender = FileTransferSender(
              exporterSecret: device.serverSession.session.exporterSecret,
            );
            final tracker = _speedTrackers.putIfAbsent(
              message.transferId,
              TransferSpeedTracker.new,
            );
            final sendCompleter = Completer<void>();
            _activeSendCompleters[message.transferId] = sendCompleter;

            final existing = _transfers[message.transferId];
            if (existing != null) {
              _transfers[message.transferId] =
                  existing.copyWith(status: TransferStatus.inProgress);
              _publishTransfers();
            }

            unawaited(
              () async {
                try {
                  await sender.sendAccepted(
                    offer: offer,
                    accept: message,
                    sources: sources,
                    sendChunk: (chunk) async {
                      if (sendCompleter.isCompleted) {
                        throw StateError('Transfer cancelled');
                      }
                      await device.serverSession.session.send(chunk);
                      final rec = _transfers[message.transferId];
                      if (rec != null) {
                        final fileIdx = rec.files
                            .indexWhere((f) => f.fileId == chunk.fileId);
                        if (fileIdx != -1) {
                          final f = rec.files[fileIdx];
                          final newBytes = (chunk.offset + chunk.bytes.length)
                              .clamp(0, f.totalBytes);
                          final updatedF =
                              f.copyWith(transferredBytes: newBytes);
                          final uFiles =
                              List<TransferFileProgress>.from(rec.files);
                          uFiles[fileIdx] = updatedF;
                          final totalTr = uFiles.fold(
                              0, (sum, item) => sum + item.transferredBytes);

                          tracker.record(totalTr);
                          final speed = tracker.calculateSpeed();
                          final eta = tracker.calculateEta(
                              rec.totalBytes, totalTr, speed);

                          _transfers[message.transferId] = rec.copyWith(
                            files: uFiles,
                            transferredBytes: totalTr,
                            speedBytesPerSecond: speed,
                            eta: eta,
                            status: TransferStatus.inProgress,
                          );
                          _publishTransfers();
                        }
                      }
                    },
                    sendComplete: (complete) async {
                      if (sendCompleter.isCompleted) {
                        throw StateError('Transfer cancelled');
                      }
                      await device.serverSession.session.send(complete);
                      final rec = _transfers[message.transferId];
                      if (rec != null) {
                        final fileIdx = rec.files
                            .indexWhere((f) => f.fileId == complete.fileId);
                        if (fileIdx != -1) {
                          final uFiles =
                              List<TransferFileProgress>.from(rec.files);
                          uFiles[fileIdx] = uFiles[fileIdx].copyWith(
                            transferredBytes: uFiles[fileIdx].totalBytes,
                            isComplete: true,
                          );
                          final allDone = uFiles.every((f) => f.isComplete);
                          final totalTr = uFiles.fold(
                              0, (sum, item) => sum + item.transferredBytes);

                          _transfers[message.transferId] = rec.copyWith(
                            files: uFiles,
                            transferredBytes: totalTr,
                            status: allDone
                                ? TransferStatus.completed
                                : TransferStatus.inProgress,
                            completedAt: allDone ? DateTime.now() : null,
                          );
                          _publishTransfers();
                        }
                      }
                    },
                  );
                  if (!sendCompleter.isCompleted) {
                    sendCompleter.complete();
                  }
                  final rec = _transfers[message.transferId];
                  if (rec != null) {
                    _transfers[message.transferId] = rec.copyWith(
                      status: TransferStatus.completed,
                      transferredBytes: rec.totalBytes,
                      completedAt: DateTime.now(),
                    );
                    _publishTransfers();
                  }
                } catch (e) {
                  if (!sendCompleter.isCompleted) {
                    sendCompleter.completeError(e);
                  }
                  final rec = _transfers[message.transferId];
                  if (rec != null) {
                    _transfers[message.transferId] = rec.copyWith(
                      status: TransferStatus.failed,
                      errorMessage: e.toString(),
                      completedAt: DateTime.now(),
                    );
                    _publishTransfers();
                  }
                } finally {
                  _activeSendCompleters.remove(message.transferId);
                }
              }(),
            );
          }

        case FileChunk():
          final result =
              await receiver.receiveChunk(message, tier: device.tier);
          if (result == ChunkDisposition.refused) {
            await device.serverSession.session.send(
              FileAbort(
                transferId: message.transferId,
                fileId: message.fileId,
                reason: FileAbortReason.declined,
              ),
            );
            return;
          }
          if (result == ChunkDisposition.corrupt) {
            await device.serverSession.session.send(
              FileAbort(
                transferId: message.transferId,
                fileId: message.fileId,
                reason: FileAbortReason.hashMismatch,
              ),
            );
            return;
          }

          final record = _transfers[message.transferId];
          if (record != null) {
            final tracker = _speedTrackers.putIfAbsent(
              message.transferId,
              TransferSpeedTracker.new,
            );
            final fileIdx =
                record.files.indexWhere((f) => f.fileId == message.fileId);
            if (fileIdx != -1) {
              final file = record.files[fileIdx];
              final newBytes = (message.offset + message.bytes.length)
                  .clamp(0, file.totalBytes);
              final updatedFile = file.copyWith(transferredBytes: newBytes);
              final uFiles = List<TransferFileProgress>.from(record.files);
              uFiles[fileIdx] = updatedFile;
              final totalTr =
                  uFiles.fold(0, (sum, f) => sum + f.transferredBytes);

              tracker.record(totalTr);
              final speed = tracker.calculateSpeed();
              final eta =
                  tracker.calculateEta(record.totalBytes, totalTr, speed);

              _transfers[message.transferId] = record.copyWith(
                files: uFiles,
                transferredBytes: totalTr,
                speedBytesPerSecond: speed,
                eta: eta,
                status: TransferStatus.inProgress,
              );
              _publishTransfers();
            }
          }

        case FileComplete():
          final result = await receiver.complete(message, tier: device.tier);
          if (result == CompletionDisposition.hashMismatch ||
              result == CompletionDisposition.incomplete) {
            await device.serverSession.session.send(
              FileAbort(
                transferId: message.transferId,
                fileId: message.fileId,
                reason: result == CompletionDisposition.hashMismatch
                    ? FileAbortReason.hashMismatch
                    : FileAbortReason.ioError,
              ),
            );
            final record = _transfers[message.transferId];
            if (record != null) {
              _transfers[message.transferId] = record.copyWith(
                status: TransferStatus.failed,
                errorMessage: 'Integrity verification failed',
                completedAt: DateTime.now(),
              );
              _publishTransfers();
            }
            return;
          }

          final record = _transfers[message.transferId];
          if (record != null) {
            final fileIdx =
                record.files.indexWhere((f) => f.fileId == message.fileId);
            if (fileIdx != -1) {
              final uFiles = List<TransferFileProgress>.from(record.files);
              uFiles[fileIdx] = uFiles[fileIdx].copyWith(
                transferredBytes: uFiles[fileIdx].totalBytes,
                isComplete: true,
              );
              final allDone = uFiles.every((f) => f.isComplete);
              final totalTr =
                  uFiles.fold(0, (sum, f) => sum + f.transferredBytes);

              _transfers[message.transferId] = record.copyWith(
                files: uFiles,
                transferredBytes: totalTr,
                status: allDone
                    ? TransferStatus.completed
                    : TransferStatus.inProgress,
                completedAt: allDone ? DateTime.now() : null,
              );
              _publishTransfers();
            }
          }

        case FileAbort():
          await receiver.abort(message, tier: device.tier);
          final completer = _activeSendCompleters.remove(message.transferId);
          if (completer != null && !completer.isCompleted) {
            completer
                .completeError(StateError('Transfer aborted by remote peer'));
          }

          final isDeclined = message.reason == FileAbortReason.declined;
          final record = _transfers[message.transferId];
          if (record != null) {
            _transfers[message.transferId] = record.copyWith(
              status: isDeclined
                  ? TransferStatus.declined
                  : TransferStatus.cancelled,
              errorMessage: message.reason.name,
              completedAt: DateTime.now(),
            );
            _publishTransfers();
          }

        default:
          break;
      }
    } on Object catch (error, stackTrace) {
      _log.error(
        'incoming file transfer failed',
        error: error,
        stackTrace: stackTrace,
      );
      final transferId = switch (message) {
        FileOffer(:final transferId) ||
        FileAccept(:final transferId) ||
        FileChunk(:final transferId) ||
        FileComplete(:final transferId) ||
        FileAbort(:final transferId) =>
          transferId,
        _ => null,
      };
      if (transferId != null && device.serverSession.session.isEstablished) {
        try {
          await device.serverSession.session.send(
            FileAbort(
              transferId: transferId,
              reason: FileAbortReason.ioError,
            ),
          );
        } on TransportError {
          // The session is already closing; the partial remains resumable.
        }
      }
    }
  }

  /// Approves a pending incoming file transfer.
  Future<void> approveIncomingTransfer(PendingIncomingTransfer request) async {
    final device = _devices[request.peerId.value];
    final receiver = _transferReceivers[request.peerId.value];
    if (device == null || receiver == null) {
      final record = _transfers[request.transferId];
      if (record != null) {
        _transfers[request.transferId] = record.copyWith(
          status: TransferStatus.failed,
          errorMessage: 'Device disconnected',
          completedAt: DateTime.now(),
        );
        _publishTransfers();
      }
      return;
    }

    _knownPeersWithTransfers.add(request.peerId.value);

    final decision =
        await receiver.acceptOffer(request.offer, tier: device.tier);
    await device.serverSession.session.send(decision.accept);
    if (decision.abort case final abort?) {
      await device.serverSession.session.send(abort);
    }

    final record = _transfers[request.transferId];
    if (record != null) {
      _transfers[request.transferId] = record.copyWith(
        status: TransferStatus.inProgress,
      );
      _publishTransfers();
    }
  }

  /// Declines a pending incoming file transfer.
  Future<void> declineIncomingTransfer(PendingIncomingTransfer request) async {
    final device = _devices[request.peerId.value];
    if (device != null && device.serverSession.session.isEstablished) {
      try {
        await device.serverSession.session.send(
          FileAbort(
            transferId: request.transferId,
            reason: FileAbortReason.declined,
          ),
        );
      } catch (_) {}
    }

    final record = _transfers[request.transferId];
    if (record != null) {
      _transfers[request.transferId] = record.copyWith(
        status: TransferStatus.declined,
        completedAt: DateTime.now(),
      );
      _publishTransfers();
    }
  }

  /// Sends a list of files to [targetPeerId].
  Future<String> sendFiles(DeviceId targetPeerId, List<File> files) async {
    final device = _devices[targetPeerId.value];
    if (device == null || !device.serverSession.session.isEstablished) {
      throw StateError('Cannot send files: device not connected');
    }

    if (files.isEmpty) {
      throw ArgumentError('files list must not be empty');
    }

    final transferId = 't-${DateTime.now().microsecondsSinceEpoch}';
    final offeredFiles = <OfferedFile>[];
    final sources = <String, OutgoingFile>{};

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final fileId = 'file-${i + 1}';
      final rawName = file.uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => 'file_${i + 1}.dat',
      );
      final fileName = sanitiseFileName(rawName);
      final length = file.lengthSync();
      final stat = file.statSync();

      offeredFiles.add(
        OfferedFile(
          fileId: fileId,
          fileName: fileName,
          size: length,
          fileType: 'application/octet-stream',
          modifiedAt: stat.modified.toUtc(),
        ),
      );
      sources[fileId] = FileBackedOutgoingFile(file, length);
    }

    final offer = FileOffer(
      transferId: transferId,
      files: offeredFiles,
    );

    _outgoingSources[transferId] = sources;
    _outgoingOffers[transferId] = offer;
    _outgoingPeerIds[transferId] = targetPeerId;
    _speedTrackers[transferId] = TransferSpeedTracker();

    final record = TransferRecord(
      transferId: transferId,
      peerId: targetPeerId,
      peerName: device.name,
      direction: TransferDirection.outgoing,
      status: TransferStatus.offered,
      files: <TransferFileProgress>[
        for (final f in offeredFiles)
          TransferFileProgress(
            fileId: f.fileId,
            fileName: f.fileName,
            totalBytes: f.size,
            transferredBytes: 0,
          ),
      ],
      totalBytes: offeredFiles.fold(0, (sum, f) => sum + f.size),
      transferredBytes: 0,
      createdAt: DateTime.now(),
    );

    _transfers[transferId] = record;
    _publishTransfers();

    await device.serverSession.session.send(offer);
    return transferId;
  }

  /// Sends a plain text snippet or URL as a generated file transfer.
  Future<String> sendText(
    DeviceId targetPeerId,
    String text, {
    String? fileName,
  }) async {
    final device = _devices[targetPeerId.value];
    if (device == null || !device.serverSession.session.isEstablished) {
      throw StateError('Cannot send text: device not connected');
    }

    final bytes = Uint8List.fromList(utf8.encode(text));
    final rawName = fileName != null && fileName.trim().isNotEmpty
        ? fileName.trim()
        : generateTextSnippetFileName();
    final cleanName = sanitiseFileName(rawName);

    final transferId =
        't-${DateTime.now().microsecondsSinceEpoch}-${bytes.length}';
    const fileId = 'text-1';

    final sha256 = await Primitives.sha256(bytes);
    final offeredFile = OfferedFile(
      fileId: fileId,
      fileName: cleanName,
      size: bytes.length,
      fileType: 'text/plain',
      sha256: sha256,
      modifiedAt: DateTime.now().toUtc(),
    );

    final offer = FileOffer(
      transferId: transferId,
      files: <OfferedFile>[offeredFile],
    );

    final sources = <String, OutgoingFile>{
      fileId: MemoryOutgoingFile(bytes),
    };

    _outgoingSources[transferId] = sources;
    _outgoingOffers[transferId] = offer;
    _outgoingPeerIds[transferId] = targetPeerId;
    _speedTrackers[transferId] = TransferSpeedTracker();

    final record = TransferRecord(
      transferId: transferId,
      peerId: targetPeerId,
      peerName: device.name,
      direction: TransferDirection.outgoing,
      status: TransferStatus.offered,
      files: <TransferFileProgress>[
        TransferFileProgress(
          fileId: fileId,
          fileName: cleanName,
          totalBytes: bytes.length,
          transferredBytes: 0,
        ),
      ],
      totalBytes: bytes.length,
      transferredBytes: 0,
      createdAt: DateTime.now(),
    );

    _transfers[transferId] = record;
    _publishTransfers();

    await device.serverSession.session.send(offer);
    return transferId;
  }

  /// Cancels an in-progress transfer and sends FileAbort.
  Future<void> cancelTransfer(String transferId) async {
    final record = _transfers[transferId];
    if (record != null) {
      final device = _devices[record.peerId.value];
      if (device != null && device.serverSession.session.isEstablished) {
        try {
          await device.serverSession.session.send(
            FileAbort(
              transferId: transferId,
              reason: FileAbortReason.cancelled,
            ),
          );
        } catch (_) {}
      }

      final completer = _activeSendCompleters.remove(transferId);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(StateError('Transfer cancelled by user'));
      }

      _transfers[transferId] = record.copyWith(
        status: TransferStatus.cancelled,
        completedAt: DateTime.now(),
      );
      _publishTransfers();
    }
  }

  /// Retries a failed or cancelled transfer.
  Future<void> retryTransfer(String transferId) async {
    final offer = _outgoingOffers[transferId];
    final sources = _outgoingSources[transferId];
    final peerId = _outgoingPeerIds[transferId];
    final record = _transfers[transferId];

    if (offer == null || sources == null || peerId == null || record == null) {
      throw StateError('Cannot retry transfer: original offer not found');
    }

    final device = _devices[peerId.value];
    if (device == null || !device.serverSession.session.isEstablished) {
      throw StateError('Cannot retry: device not connected');
    }

    _transfers[transferId] = record.copyWith(
      status: TransferStatus.offered,
      errorMessage: null,
    );
    _publishTransfers();

    await device.serverSession.session.send(offer);
  }

  Future<void> _renamePeer(DeviceId peerId, String newName) async {
    final peer = await trustStore.findById(peerId);
    if (peer != null) {
      await trustStore.upsert(peer.copyWith(name: newName));
    }

    final device = _devices[peerId.value];
    if (device != null) {
      _devices[peerId.value] = ConnectedDevice(
        serverSession: device.serverSession,
        tier: device.tier,
        name: newName,
      );
      _publishDevices();
    }

    _log.info(
      'peer renamed',
      fields: <String, Object?>{
        'peer': peerId.value,
        'name': newName,
      },
    );
  }

  /// The QR payload for the pairing sheet.
  ///
  /// Includes the full static public key, which is what makes QR pairing
  /// stronger than digit comparison: the phone learns the real key over an
  /// optical channel no network attacker can reach, closing the
  /// machine-in-the-middle window entirely instead of merely making it visible.
  PairingPayload pairingPayload({required String host}) => PairingPayload(
        deviceId: identity.id,
        publicKey: identity.publicKey,
        name: deviceName,
        host: host,
        port: boundPort,
        token: Uint8List(0),
      );

  Future<void> _broadcastClipboard(ClipboardUpdate update) async {
    for (final device in _devices.values) {
      if (!device.tier.canSyncClipboard) continue;
      if (!device.serverSession.session.isEstablished) continue;
      try {
        await device.serverSession.session.send(update);
      } on TransportError {
        // Session is tearing down; its watcher handles cleanup.
      }
    }
  }

  Future<void> _onRemoteClipboardAsync(ClipboardUpdate update) async {
    if (!clipboard.remoteWins(update)) return;
    await clipboard.applyRemote(update);
  }

  void _onRemoteClipboard(ClipboardUpdate update) =>
      unawaited(_onRemoteClipboardAsync(update));

  void _onPowerCommand(PowerCommand command) =>
      unawaited(_runPowerCommand(command));

  Future<void> _runPowerCommand(PowerCommand command) async {
    // Power commands are executed through the OS's own tooling rather than a
    // native API, because the platform utilities already handle the parts that
    // matter: warning about unsaved work, notifying other applications, and
    // respecting group policy.
    final (executable, arguments) =
        switch ((NativeBackends.currentPlatform, command.action)) {
      (PlatformKind.windows, PowerAction.shutdown) => (
          'shutdown',
          <String>['/s', '/t', '${command.delaySeconds}'],
        ),
      (PlatformKind.windows, PowerAction.restart) => (
          'shutdown',
          <String>['/r', '/t', '${command.delaySeconds}'],
        ),
      (PlatformKind.windows, PowerAction.logOut) => (
          'shutdown',
          <String>['/l'],
        ),
      (PlatformKind.windows, PowerAction.lock) => (
          'rundll32.exe',
          <String>['user32.dll,LockWorkStation'],
        ),
      (PlatformKind.macos, PowerAction.shutdown) => (
          'osascript',
          <String>['-e', 'tell app "System Events" to shut down'],
        ),
      (PlatformKind.macos, PowerAction.restart) => (
          'osascript',
          <String>['-e', 'tell app "System Events" to restart'],
        ),
      (PlatformKind.macos, PowerAction.sleep) => (
          'pmset',
          <String>['sleepnow'],
        ),
      (PlatformKind.macos, PowerAction.lock) => (
          'osascript',
          <String>[
            '-e',
            'tell app "System Events" to keystroke "q" using '
                '{command down, control down}',
          ],
        ),
      (PlatformKind.macos, PowerAction.logOut) => (
          'osascript',
          <String>['-e', 'tell app "System Events" to log out'],
        ),
      _ => (null, const <String>[]),
    };

    if (executable == null) {
      _log.warn(
        'power action not supported on this platform',
        fields: <String, Object?>{'action': command.action.name},
      );
      return;
    }

    _log.info(
      'running power command',
      fields: <String, Object?>{'action': command.action.name},
    );
    try {
      await Process.run(executable, arguments);
    } on ProcessException catch (e) {
      _log.error('power command failed', error: e);
    }
  }

  void _onLaunchApplication(LaunchApplication command) =>
      unawaited(_runLaunch(command));

  Future<void> _runLaunch(LaunchApplication command) async {
    // Arguments are dropped unless the session holds the admin tier, which the
    // dispatcher has already checked. Even so the identifier is passed as a
    // separate argv entry and never concatenated into a shell string — the
    // difference between launching an app and evaluating arbitrary shell.
    final (executable, arguments) = switch (NativeBackends.currentPlatform) {
      PlatformKind.macos => ('open', <String>['-a', command.identifier]),
      PlatformKind.windows => (
          'cmd',
          <String>['/c', 'start', '', command.identifier],
        ),
      _ => (null, const <String>[]),
    };
    if (executable == null) return;

    try {
      await Process.run(executable, arguments);
    } on ProcessException catch (e) {
      _log.error('launch failed', error: e);
    }
  }

  void _onOpenUrl(OpenUrl command) => unawaited(_runOpenUrl(command));

  Future<void> _runOpenUrl(OpenUrl command) async {
    final uri = Uri.tryParse(command.url);

    // Without this check the message would be a general-purpose launcher rather
    // than a browser command: `file:` opens documents, and custom schemes can
    // start arbitrary registered applications.
    const allowedSchemes = <String>{'http', 'https', 'mailto'};
    if (uri == null || !allowedSchemes.contains(uri.scheme.toLowerCase())) {
      _log.warn(
        'refusing to open a URL with a disallowed scheme',
        fields: <String, Object?>{'scheme': uri?.scheme},
      );
      return;
    }

    final executable =
        NativeBackends.currentPlatform == PlatformKind.macos ? 'open' : 'start';
    try {
      if (executable == 'open') {
        await Process.run('open', <String>[uri.toString()]);
      } else {
        await Process.run('cmd', <String>['/c', 'start', '', uri.toString()]);
      }
    } on ProcessException catch (e) {
      _log.error('open url failed', error: e);
    }
  }

  void _onRunCommand(RunCommand command) {
    // Registered commands resolve against desktop-side configuration that this
    // milestone does not yet persist. Refusing until it exists is the correct
    // default: an unresolved command id must never fall through to a shell.
    _log.warn(
      'custom command requested but no command registry is configured',
      fields: <String, Object?>{'commandId': command.commandId},
    );
  }

  void _onMediaCommand(MediaCommand command) =>
      unawaited(_runMediaCommand(command));

  Future<void> _runMediaCommand(MediaCommand command) async {
    if (!_media.isAvailable) return;
    await _media.command(command.action, seekSeconds: command.seekSeconds);
    // Push the new state straight away rather than waiting for the poll: the
    // user pressed a button and expects the phone to agree within a frame, not
    // within a poll interval.
    unawaited(_publishMediaState());
  }

  void _onVolumeCommand(VolumeCommand command) =>
      unawaited(_runVolumeCommand(command));

  Future<void> _runVolumeCommand(VolumeCommand command) async {
    if (!_media.isAvailable) return;

    switch (command.mode) {
      case VolumeMode.absolute:
        await _media.setVolume(command.value);
      case VolumeMode.relative:
        // Read-modify-write rather than tracking a local value: the user may
        // have moved the slider on the computer since we last looked, and a
        // stale base would make the phone's volume jump.
        final current = await _media.volume();
        await _media.setVolume(current.level + command.value);
      case VolumeMode.toggleMute:
        final current = await _media.volume();
        await _media.setMuted(muted: !current.muted);
      case VolumeMode.setMute:
        await _media.setMuted(muted: command.value > 0);
    }
    unawaited(_publishMediaState());
  }

  void _onBrightnessCommand(BrightnessCommand command) =>
      unawaited(_runBrightnessCommand(command));

  Future<void> _runBrightnessCommand(BrightnessCommand command) async {
    if (!_brightness.isAvailable) return;
    try {
      if (command.relative) {
        final current = await _brightness.level();
        await _brightness.setLevel((current + command.value).clamp(0.0, 1.0));
      } else {
        await _brightness.setLevel(command.value.clamp(0.0, 1.0));
      }
    } catch (e, stack) {
      _log.error('failed to set brightness', error: e, stackTrace: stack);
    }
  }

  /// Sends the current media state to every session that can use it.
  Future<void> _publishMediaState() async {
    if (_devices.isEmpty || !_media.isAvailable) return;

    final volume = await _media.volume();
    final playing = await _media.nowPlaying();

    final state = MediaState(
      isPlaying: playing?.isPlaying ?? false,
      title: playing?.title ?? '',
      artist: playing?.artist ?? '',
      album: playing?.album ?? '',
      positionSeconds: playing?.positionSeconds ?? 0,
      durationSeconds: playing?.durationSeconds ?? 0,
      volume: volume.level,
      isMuted: volume.muted,
      sourceApplication: playing?.source,
    );

    for (final device in _devices.values) {
      if (!device.serverSession.session.isEstablished) continue;
      try {
        await device.serverSession.session.send(state);
      } on TransportError {
        // Tearing down; its watcher will clean up.
      }
    }
  }

  /// Publishes host telemetry to all connected sessions.
  Future<void> _publishSystemStatus() async {
    if (_devices.isEmpty) return;

    final volume = await _media.volume();
    final metrics = await _systemInfo.metrics();

    final status = SystemStatus(
      volume: volume.level,
      isMuted: volume.muted,
      uptimeSeconds: metrics.uptimeSeconds ?? 0,
      batteryPercent: metrics.batteryPercent,
      isCharging: metrics.isCharging,
      cpuPercent: metrics.cpuPercent,
      memoryPercent: metrics.memoryPercent,
    );

    for (final device in _devices.values) {
      if (!device.serverSession.session.isEstablished) continue;
      try {
        await device.serverSession.session.send(status);
      } on TransportError {
        // Tearing down; its watcher will clean up.
      }
    }
  }

  /// Polls media state while at least one phone is connected.
  ///
  /// Polling only when someone is watching matters: this shells out to
  /// AppleScript, and doing that every two seconds forever on a laptop with no
  /// phone attached would be a battery cost for nobody's benefit.
  void _startMediaWatch() {
    _mediaWatch = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_devices.isEmpty) return;
      unawaited(_publishMediaState());
    });
  }

  Timer? _mediaWatch;

  /// Polls system status (battery, load, uptime) while at least one phone is
  /// connected.
  ///
  /// ZERO work when no device is connected, matching [_startMediaWatch].
  void _startSystemWatch() {
    _systemWatch = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(telemetryTick()),
    );
  }

  /// One iteration of the system-status watcher.
  ///
  /// Named and visible rather than inlined into the timer callback so the
  /// "no work when nobody is watching" guarantee can be tested by calling it
  /// directly. Reaching it through [start] instead would mean binding a TCP
  /// listener, a UDP multicast beacon, and a Bonjour advertiser — fixed ports
  /// that collide the moment two test runs overlap — and then waiting out a
  /// real five-second timer to observe a single boolean.
  ///
  /// This is the same code path the timer drives; the test is not asserting
  /// against a parallel implementation.
  Future<void> telemetryTick() async {
    if (_devices.isEmpty) return;
    await _publishSystemStatus();
  }

  Timer? _systemWatch;

  void _publishDevices() {
    if (!_deviceChanges.isClosed) _deviceChanges.add(devices);
  }

  /// Opens the macOS Accessibility settings pane directly.
  ///
  /// Worth the four lines: the alternative is a banner that names a four-level
  /// settings path and leaves the user to find it, which is exactly the point
  /// where someone decides the app is broken and quits.
  Future<void> openAccessibilitySettings() async {
    if (NativeBackends.currentPlatform != PlatformKind.macos) return;
    try {
      await Process.run('open', <String>[
        'x-apple.systempreferences:com.apple.preference.security'
            '?Privacy_Accessibility',
      ]);
    } on ProcessException catch (e) {
      _log.warn('could not open settings', error: e);
    }
  }

  Future<void> stop() async {
    _permissionWatch?.cancel();
    _permissionWatch = null;
    _mediaWatch?.cancel();
    _mediaWatch = null;
    _systemWatch?.cancel();
    _systemWatch = null;
    await _inputAvailability.close();

    await _acceptedSubscription?.cancel();
    await _endedSubscription?.cancel();
    await _clipboardSubscription?.cancel();

    for (final subscription in _messageSubscriptions.values) {
      await subscription.cancel();
    }
    _messageSubscriptions.clear();

    await _bonjour?.stop();
    await _beacon?.stop();
    await _server?.stop();
    await clipboard.dispose();
    await _pairing.dispose();

    _input.dispose();
    _clipboardBackend.dispose();
    _media.dispose();
    _brightness.dispose();
    _systemInfo.dispose();
    _networkAdapters.dispose();

    _devices.clear();
    await _deviceChanges.close();
    await _pairingRequests.close();
    await _incomingTransferRequests.close();
    await _transferChanges.close();

    _log.info('desktop service stopped');
  }
}
