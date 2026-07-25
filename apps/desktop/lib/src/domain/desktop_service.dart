import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

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
}) {
  var capabilities = const Capabilities(
    Capabilities.mediaControl |
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
  })  : _clock = clock,
        _input = NativeBackends.createInput(),
        _clipboardBackend = NativeBackends.createClipboard();

  final DeviceIdentity identity;
  final TrustStore trustStore;
  final String deviceName;
  final String appVersion;
  final int servicePort;

  final Clock _clock;
  final InputBackend _input;
  final ClipboardBackend _clipboardBackend;
  final Log _log = Log.scoped('desktop.service');

  late final PairingCoordinator _pairing = PairingCoordinator(
    identity: identity,
    clock: _clock,
  );

  late final ClipboardSyncService clipboard = ClipboardSyncService(
    clipboard: _clipboardBackend,
    localDeviceId: identity.id,
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
  );

  RemoteLinkServer? _server;
  UdpDiscoveryServer? _beacon;

  final Map<String, ConnectedDevice> _devices = <String, ConnectedDevice>{};
  final Map<String, StreamSubscription<Message>> _messageSubscriptions =
      <String, StreamSubscription<Message>>{};

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

  int get boundPort => _server?.boundPort ?? servicePort;

  /// Whether new devices may pair right now.
  bool acceptsNewPairings = true;

  /// Starts listening and announcing.
  Future<void> start() async {
    if (_server != null) return;

    final capabilities = buildCapabilities(
      inputAvailable: _input.isAvailable,
      clipboardAvailable: _clipboardBackend.isAvailable,
    );

    final server = RemoteLinkServer(
      identity: identity,
      capabilities: capabilities,
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

    // The beacon reads live state on every announcement rather than holding a
    // snapshot, so the session count and pairing availability a phone sees are
    // always current without anything having to remember to push updates.
    final beacon = UdpDiscoveryServer(
      describe: () => Beacon(
        kind: BeaconKind.announce,
        deviceId: identity.id,
        name: deviceName,
        platform: NativeBackends.currentPlatform,
        servicePort: server.boundPort,
        protocolVersion: kProtocolVersion,
        publicKeyFingerprint:
            Uint8List.sublistView(identity.publicKey, 0, 8),
        capabilities: capabilities,
        acceptsNewPairings: acceptsNewPairings,
        activeSessions: server.sessionCount,
      ),
    );
    await beacon.start();
    _beacon = beacon;

    _log.info(
      'desktop service started',
      fields: <String, Object?>{
        'port': server.boundPort,
        'device': identity.id.value,
        'input': _input.isAvailable,
      },
    );
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
    final snapshot = await clipboard.snapshot();
    if (snapshot != null) await session.session.send(snapshot);
  }

  Future<void> _onMessage(ServerSession session, Message message) async {
    final device = _devices[session.peerId.value];
    if (device == null) return;

    switch (message) {
      case DeviceInfoMessage():
        _devices[session.peerId.value] = ConnectedDevice(
          serverSession: session,
          tier: device.tier,
          name: message.info.name,
        );
        _publishDevices();

      case ClipboardRequest():
        final snapshot = await clipboard.snapshot();
        if (snapshot != null) await session.session.send(snapshot);

      default:
        _dispatcher.dispatch(message, device.tier);
    }
  }

  Future<void> _onEnded(ServerSession session) async {
    await _messageSubscriptions.remove(session.peerId.value)?.cancel();
    _devices.remove(session.peerId.value);
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
      fields: <String, Object?>{'peer': request.peerId.value, 'tier': tier.name},
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
    final server = _server;
    if (server == null) return;

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
    final (executable, arguments) = switch (
        (NativeBackends.currentPlatform, command.action)) {
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

  void _onMediaCommand(MediaCommand command) {
    // Media keys are synthesised as a fallback until the OS media-session
    // integration lands. Consumer-control HID usages live on a different usage
    // page than the keyboard, so they do not go through the standard key map.
    _log.debug(() => 'media command ${command.action.name}');
  }

  void _onVolumeCommand(VolumeCommand command) {
    _log.debug(() => 'volume command ${command.mode.name}');
  }

  void _publishDevices() {
    if (!_deviceChanges.isClosed) _deviceChanges.add(devices);
  }

  Future<void> stop() async {
    await _acceptedSubscription?.cancel();
    await _endedSubscription?.cancel();
    await _clipboardSubscription?.cancel();

    for (final subscription in _messageSubscriptions.values) {
      await subscription.cancel();
    }
    _messageSubscriptions.clear();

    await _beacon?.stop();
    await _server?.stop();
    await clipboard.dispose();
    await _pairing.dispose();

    _input.dispose();
    _clipboardBackend.dispose();

    _devices.clear();
    await _deviceChanges.close();
    await _pairingRequests.close();

    _log.info('desktop service stopped');
  }
}
