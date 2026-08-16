import 'dart:async';
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
    SystemInfoBackend? systemInfo,
    this.incomingTransferStore,
  })  : _clock = clock,
        _input = input ?? NativeBackends.createInput(),
        _clipboardBackend =
            clipboardBackend ?? NativeBackends.createClipboard(),
        _media = media ?? NativeBackends.createMedia(),
        _systemInfo = systemInfo ?? NativeBackends.createSystemInfo();

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
  final SystemInfoBackend _systemInfo;
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

  final StreamController<List<ConnectedDevice>> _deviceChanges =
      StreamController<List<ConnectedDevice>>.broadcast();
  final StreamController<PendingPairing> _pairingRequests =
      StreamController<PendingPairing>.broadcast();

  StreamSubscription<ServerSession>? _acceptedSubscription;
  StreamSubscription<ServerSession>? _endedSubscription;
  StreamSubscription<ClipboardUpdate>? _clipboardSubscription;

  /// Connected devices, updated as they come and go.
  Stream<List<ConnectedDevice>> get deviceChanges => _deviceChanges.stream;

  /// Pairing requests awaiting the user's confirmation.
  Stream<PendingPairing> get pairingRequests => _pairingRequests.stream;

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
      );

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
    } on OSError catch (e) {
      _log.warn('could not enumerate network interfaces', error: e);
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
  DeviceInfo describeSelf() => DeviceInfo(
        id: identity.id,
        name: deviceName,
        platform: NativeBackends.currentPlatform,
        role: PeerRole.server,
        appVersion: appVersion,
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
          final decision =
              await receiver.acceptOffer(message, tier: device.tier);
          await device.serverSession.session.send(decision.accept);
          if (decision.abort case final abort?) {
            await device.serverSession.session.send(abort);
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
          }
        case FileAbort():
          await receiver.abort(message, tier: device.tier);
        case FileAccept():
        // Desktop-originated sending is intentionally outside this task.
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
    _systemInfo.dispose();

    _devices.clear();
    await _deviceChanges.close();
    await _pairingRequests.close();

    _log.info('desktop service stopped');
  }
}
