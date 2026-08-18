import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
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
  bool screenCaptureAvailable = false,
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
  if (screenCaptureAvailable) {
    // Advertised only when screen recording permission is granted and a
    // working screen capture backend is available.
    capabilities = capabilities.plus(Capabilities.screenCapture);
  }
  return capabilities;
}

/// Why this computer cannot drive [device]'s phone, or `null` if it can.
///
/// The reverse of screen sharing, and it does not work — from either end. The
/// phone cannot be captured (see `PhoneControlBackend` for the per-platform
/// reasons) and this computer has nothing to display a phone's frames in, so
/// [buildCapabilities] does not claim the bit either. The negotiated set is the
/// intersection of both sides, so one missing side is enough and checking it
/// covers both.
///
/// That coupling is deliberate: whoever builds the viewer has to add the
/// capability in [buildCapabilities] to switch this on, so there is no way to
/// reach an enabled control with nothing behind it.
///
/// A reason rather than a boolean because the user asked for this feature and
/// deserves to know why it is greyed out. "Not available" with no explanation
/// reads as a bug, and on an iPhone this is not a bug and will not be fixed.
String? phoneControlBlockedReason(ConnectedDevice device) {
  if (!device.serverSession.handshake.capabilities
      .has(Capabilities.phoneControl)) {
    return 'Controlling a phone from this computer is not available. iPhones '
        'offer no way to allow it at all, Android needs a service this build '
        'does not include, and there is no viewer here yet.';
  }
  if (!device.tier.canViewScreen) {
    return 'Raise this device above read-only to control it.';
  }
  return null;
}

/// How often the pointer is sampled while a screen stream is running.
///
/// 60 Hz, which is fast enough that the drawn cursor tracks the real one rather
/// than trailing it. Affordable only because the pointer travels on its own:
/// the read costs about ten microseconds and the message is 34 bytes, so this
/// is 0.6 ms of CPU and 16 kbps. The same rate carried on frames would be
/// 102 Mbps, which is why the cursor used to move at five to ten frames a
/// second whatever the capture rate said.
const Duration kCursorPollInterval = Duration(milliseconds: 16);

/// A live connection as the desktop UI sees it.
final class ConnectedDevice {
  ConnectedDevice({
    required this.serverSession,
    required this.tier,
    required this.name,
    this.clipboardSyncEnabled = true,
  });

  final ServerSession serverSession;
  final PermissionTier tier;
  final String name;
  final bool clipboardSyncEnabled;

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

/// A permission elevation request waiting on the user.
final class PendingPermissionRequest {
  PendingPermissionRequest({
    required this.session,
    required this.peerId,
    required this.peerName,
    required this.requestedTier,
    required this.currentTier,
    this.justification,
    required this.requestedAt,
  });

  final ServerSession session;
  final DeviceId peerId;
  final String peerName;
  final PermissionTier requestedTier;
  final PermissionTier currentTier;
  final String? justification;
  final DateTime requestedAt;
}

/// Throttles permission elevation requests to one per device per minute.
final class PermissionRateLimiter {
  PermissionRateLimiter({
    required Clock clock,
    this.window = const Duration(minutes: 1),
  }) : _clock = clock;

  final Clock _clock;
  final Duration window;
  final Map<String, DateTime> _lastRequests = <String, DateTime>{};

  /// Whether [peerKey] may request permission elevation now.
  bool isAllowed(String peerKey) {
    final last = _lastRequests[peerKey];
    if (last == null) return true;
    final elapsed = _clock.now().difference(last);
    return elapsed >= window;
  }

  /// Records an allowed request timestamp.
  void recordRequest(String peerKey) {
    _lastRequests[peerKey] = _clock.now();
  }

  /// Clears request record for [peerKey].
  void reset(String peerKey) {
    _lastRequests.remove(peerKey);
  }
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
    ScreenCaptureBackend? screenCapture,
    ClipboardHistory? clipboardHistory,
    this.incomingTransferStore,
    this.peerClipboardSettingsFile,
  })  : _clipboardHistory = clipboardHistory,
        _clock = clock,
        _input = input ?? NativeBackends.createInput(),
        _clipboardBackend =
            clipboardBackend ?? NativeBackends.createClipboard(),
        _media = media ?? NativeBackends.createMedia(),
        _brightness = brightness ?? NativeBackends.createBrightness(),
        _systemInfo = systemInfo ?? NativeBackends.createSystemInfo(),
        _networkAdapters =
            networkAdapters ?? NativeBackends.createNetworkAdapters(),
        _screenCapture = screenCapture ?? NativeBackends.createScreenCapture();

  final DeviceIdentity identity;
  final TrustStore trustStore;
  final String deviceName;
  final String appVersion;
  final int servicePort;
  final IncomingTransferStore? incomingTransferStore;
  final File? peerClipboardSettingsFile;

  /// Supplied by the app so the history survives a service restart; `null` in
  /// a headless run, where [ClipboardSyncService] makes its own.
  final ClipboardHistory? _clipboardHistory;

  final Clock _clock;
  final InputBackend _input;
  final ClipboardBackend _clipboardBackend;
  final MediaBackend _media;
  final BrightnessBackend _brightness;
  final SystemInfoBackend _systemInfo;
  final NetworkAdapterBackend _networkAdapters;
  final ScreenCaptureBackend _screenCapture;
  final Log _log = Log.scoped('desktop.service');

  late final PairingCoordinator _pairing = PairingCoordinator(
    identity: identity,
    clock: _clock,
  );

  late final PermissionRateLimiter _permissionRateLimiter =
      PermissionRateLimiter(clock: _clock);

  late final ClipboardSyncService clipboard = ClipboardSyncService(
    clipboard: _clipboardBackend,
    localDeviceId: identity.id,
    clock: _clock,
    history: _clipboardHistory,
  );

  late final CommandDispatcher _dispatcher = CommandDispatcher(
    input: _input,
    platform: NativeBackends.currentPlatform,
    onClipboardUpdate: _onRemoteClipboard,
    onClipboardSyncToggle: _onClipboardSyncToggle,
    onPowerCommand: _onPowerCommand,
    onLaunchApplication: _onLaunchApplication,
    onOpenUrl: _onOpenUrl,
    onRunCommand: _onRunCommand,
    onMediaCommand: _onMediaCommand,
    onVolumeCommand: _onVolumeCommand,
    onBrightnessCommand: _onBrightnessCommand,
    onDeviceRename: _onDeviceRename,
    onFileTransferMessage: _onFileTransferMessage,
    onPermissionRequest: _onPermissionRequest,
    onScreenStreamStart: _onScreenStreamStart,
    onScreenStreamStop: _onScreenStreamStop,
    onScreenConfigure: _onScreenConfigure,
  );

  RemoteLinkServer? _server;
  UdpDiscoveryServer? _beacon;
  BonjourAdvertiser? _bonjour;

  final Map<String, ConnectedDevice> _devices = <String, ConnectedDevice>{};
  final Map<String, _ActiveScreenStream> _screenStreams =
      <String, _ActiveScreenStream>{};
  final Map<String, int> _grantExpiryGenerations = <String, int>{};
  final Map<String, PeerClipboardConfig> _peerClipboardSettings =
      <String, PeerClipboardConfig>{};
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
  final StreamController<PendingPermissionRequest> _permissionRequests =
      StreamController<PendingPermissionRequest>.broadcast();
  final StreamController<PendingIncomingTransfer> _incomingTransferRequests =
      StreamController<PendingIncomingTransfer>.broadcast();
  final StreamController<List<TransferRecord>> _transferChanges =
      StreamController<List<TransferRecord>>.broadcast();
  final StreamController<List<String>> _screenViewerChanges =
      StreamController<List<String>>.broadcast();

  StreamSubscription<ServerSession>? _acceptedSubscription;
  StreamSubscription<ServerSession>? _endedSubscription;
  StreamSubscription<ClipboardUpdate>? _clipboardSubscription;

  /// Connected devices, updated as they come and go.
  Stream<List<ConnectedDevice>> get deviceChanges => _deviceChanges.stream;

  /// Pairing requests awaiting the user's confirmation.
  Stream<PendingPairing> get pairingRequests => _pairingRequests.stream;

  /// Permission elevation requests awaiting user approval.
  Stream<PendingPermissionRequest> get permissionRequests =>
      _permissionRequests.stream;

  /// Incoming transfer requests awaiting explicit user approval.
  Stream<PendingIncomingTransfer> get incomingTransferRequests =>
      _incomingTransferRequests.stream;

  /// Transfer changes for real-time progress and status updates.
  Stream<List<TransferRecord>> get transferChanges => _transferChanges.stream;

  /// Names of the devices currently receiving this screen, as it changes.
  ///
  /// Exists so the window can say so. A machine that is streaming its screen
  /// and shows no sign of it is indistinguishable from one that is not, and
  /// the difference is the whole of the user's ability to notice. Every other
  /// sensitive action here interrupts the user for consent; screen streaming
  /// is granted once at the tier and then runs silently, so an always-visible
  /// indicator is the thing standing in for that prompt.
  Stream<List<String>> get screenViewerChanges => _screenViewerChanges.stream;

  /// Names of the devices currently receiving this screen.
  List<String> get screenViewers => <String>[
        for (final peerKey in _screenStreams.keys)
          _devices[peerKey]?.name ?? peerKey,
      ];

  void _publishScreenViewers() {
    if (_screenViewerChanges.isClosed) return;
    _screenViewerChanges.add(screenViewers);
  }

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

  bool get screenCaptureAvailable => _screenCapture.isAvailable;

  String? get screenCaptureUnavailableReason =>
      _screenCapture.unavailableReason;

  int get commandAppliedCount => _dispatcher.appliedCount;

  int get commandDeniedCount => _dispatcher.deniedCount;

  int get commandUnsupportedCount => _dispatcher.unsupportedCount;

  /// Capabilities computed from the backends' *current* state.
  ///
  /// Recomputed on every read rather than cached at startup, because on macOS
  /// Accessibility and Screen Recording permissions can be granted while the
  /// service is running.
  Capabilities get currentCapabilities => buildCapabilities(
        inputAvailable: _input.isAvailable,
        clipboardAvailable: _clipboardBackend.isAvailable,
        mediaAvailable: _media.isAvailable,
        gesturesAvailable: _input.isAvailable && _input is MacosInputBackend,
        brightnessAvailable: _brightness.isAvailable,
        screenCaptureAvailable: _screenCapture.isAvailable,
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

  /// Emits whenever Screen Recording permission flips.
  ///
  /// Its own stream rather than a flag on the input one: the two are separate
  /// grants in separate panes of System Settings, and a user who has given one
  /// has said nothing about the other. Polled on the same timer.
  Stream<bool> get screenCaptureAvailabilityChanges =>
      _screenCaptureAvailability.stream;

  final StreamController<bool> _screenCaptureAvailability =
      StreamController<bool>.broadcast();

  Timer? _permissionWatch;
  bool? _lastInputAvailable;
  bool? _lastScreenCaptureAvailable;

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
    await _loadPeerClipboardSettings();
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
    _lastScreenCaptureAvailable = _screenCapture.isAvailable;
    _inputAvailability.add(_lastInputAvailable!);

    _permissionWatch = Timer.periodic(const Duration(seconds: 2), (_) {
      final inputAvailable = _input.isAvailable;
      final captureAvailable = _screenCapture.isAvailable;
      if (inputAvailable == _lastInputAvailable &&
          captureAvailable == _lastScreenCaptureAvailable) {
        return;
      }
      final inputChanged = inputAvailable != _lastInputAvailable;
      final captureChanged = captureAvailable != _lastScreenCaptureAvailable;
      _lastInputAvailable = inputAvailable;
      _lastScreenCaptureAvailable = captureAvailable;

      // New sessions must be offered the updated capability set. Existing
      // sessions negotiated theirs at handshake time and keep it until they
      // reconnect — renegotiating mid-session is not something the protocol
      // supports, and pretending otherwise would be worse than the wait.
      _server?.capabilities = currentCapabilities;

      // The UDP beacon picks this up on its next tick for free, but a DNS-SD
      // TXT record is only read at resolve time, so it has to be republished.
      unawaited(_bonjour?.refresh() ?? Future<void>.value());
      _log.info(
        'input or capture availability changed',
        fields: <String, Object?>{
          'input': inputAvailable,
          'screenCapture': captureAvailable,
        },
      );
      if (inputChanged && !_inputAvailability.isClosed) {
        _inputAvailability.add(inputAvailable);
      }
      if (captureChanged && !_screenCaptureAvailability.isClosed) {
        _screenCaptureAvailability.add(captureAvailable);
      }
    });
  }

  @visibleForTesting
  Future<void> registerSessionForTesting(ServerSession session) =>
      _onAccepted(session);

  Future<void> _onAccepted(ServerSession session) async {
    final peer = await trustStore.findByPublicKey(
      session.handshake.peerStaticPublicKey,
    );

    final tier = peer == null
        ? PermissionTier.readOnly
        : PermissionTier.fromWire(peer.permissionTier);

    final savedConfig = _peerClipboardSettings[session.peerId.value];
    if (savedConfig != null) {
      clipboard.setPeerConfig(session.peerId, savedConfig);
    }
    final isClipboardEnabled = clipboard.isPeerEnabled(session.peerId);

    _devices[session.peerId.value] = ConnectedDevice(
      serverSession: session,
      tier: tier,
      name: peer?.name ?? session.peerId.short,
      clipboardSyncEnabled: isClipboardEnabled,
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

    final snapshot = await clipboard.snapshot(peerId: session.peerId);
    if (snapshot != null) await session.session.send(snapshot);
  }

  @visibleForTesting
  Future<void> handleMessageForTesting(
    ServerSession session,
    Message message,
  ) =>
      _onMessage(session, message);

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
          clipboardSyncEnabled: device.clipboardSyncEnabled,
        );
        _publishDevices();

      case ClipboardRequest():
        final snapshot = await clipboard.snapshot(peerId: session.peerId);
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
    _grantExpiryGenerations[session.peerId.value] =
        (_grantExpiryGenerations[session.peerId.value] ?? 0) + 1;
    await _messageSubscriptions.remove(session.peerId.value)?.cancel();
    _stopScreenStream(session.peerId.value);
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
      clipboardSyncEnabled: clipboard.isPeerEnabled(request.peerId),
    );
    _publishDevices();

    final snapshot = await clipboard.snapshot(peerId: request.peerId);
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
    clipboard.removePeer(peerId);
    _peerClipboardSettings.remove(peerId.value);
    unawaited(_persistPeerClipboardSettings());
    await _server?.revokePeer(peerId);
    _devices.remove(peerId.value);
    _publishDevices();
  }

  /// Changes a connected device's permission tier and tells it.
  Future<void> setTier(
    DeviceId peerId,
    PermissionTier tier, {
    int? expiresInSeconds,
  }) async {
    final device = _devices[peerId.value];
    if (device == null) return;

    _grantExpiryGenerations[peerId.value] =
        (_grantExpiryGenerations[peerId.value] ?? 0) + 1;

    if (expiresInSeconds == null) {
      final peer = await trustStore.findById(peerId);
      if (peer != null) {
        await trustStore.upsert(peer.copyWith(permissionTier: tier.wireValue));
      }
    }

    _devices[peerId.value] = ConnectedDevice(
      serverSession: device.serverSession,
      tier: tier,
      name: device.name,
      clipboardSyncEnabled: device.clipboardSyncEnabled,
    );
    _publishDevices();

    await device.serverSession.session.send(
      PermissionGrant(tier: tier, expiresInSeconds: expiresInSeconds),
    );

    if (expiresInSeconds != null && expiresInSeconds > 0) {
      _scheduleGrantExpiry(device.serverSession, peerId, expiresInSeconds);
    }

    _log.info(
      'permission tier set',
      fields: <String, Object?>{
        'peer': peerId.value,
        'tier': tier.name,
        'expiresInSeconds': expiresInSeconds,
      },
    );
  }

  void _scheduleGrantExpiry(
    ServerSession session,
    DeviceId peerId,
    int expiresInSeconds,
  ) {
    final generation = _grantExpiryGenerations[peerId.value] ?? 0;

    unawaited(() async {
      await _clock.delay(Duration(seconds: expiresInSeconds));

      if (_grantExpiryGenerations[peerId.value] != generation) return;
      final device = _devices[peerId.value];
      if (device == null || device.serverSession != session) return;
      if (!device.serverSession.session.isEstablished) return;

      _log.info(
        'temporary permission grant expired; reverting to readOnly',
        fields: <String, Object?>{'peer': peerId.value},
      );

      _devices[peerId.value] = ConnectedDevice(
        serverSession: device.serverSession,
        tier: PermissionTier.readOnly,
        name: device.name,
        clipboardSyncEnabled: device.clipboardSyncEnabled,
      );
      _publishDevices();

      try {
        await device.serverSession.session.send(
          const PermissionGrant(tier: PermissionTier.readOnly),
        );
      } on TransportError {
        // Session is tearing down; its watcher handles cleanup.
      }
    }());
  }

  void _onPermissionRequest(PermissionRequest request) {
    final peerId = _activeSessionPeerId;
    if (peerId == null) return;
    unawaited(_handlePermissionRequest(peerId, request));
  }

  Future<void> _handlePermissionRequest(
    DeviceId peerId,
    PermissionRequest request,
  ) async {
    final device = _devices[peerId.value];
    if (device == null) return;

    if (!_permissionRateLimiter.isAllowed(peerId.value)) {
      _log.warn(
        'permission request refused by rate limit',
        fields: <String, Object?>{
          'peer': peerId.value,
          'requestedTier': request.tier.name,
        },
      );
      return;
    }
    _permissionRateLimiter.recordRequest(peerId.value);

    final pending = PendingPermissionRequest(
      session: device.serverSession,
      peerId: peerId,
      peerName: device.name,
      requestedTier: request.tier,
      currentTier: device.tier,
      justification: request.justification,
      requestedAt: _clock.now(),
    );

    if (!_permissionRequests.isClosed) {
      _permissionRequests.add(pending);
    }
  }

  /// Approves a pending permission request.
  Future<void> approvePermissionRequest(
    PendingPermissionRequest request, {
    int? expiresInSeconds,
  }) async {
    await setTier(
      request.peerId,
      request.requestedTier,
      expiresInSeconds: expiresInSeconds,
    );
  }

  /// Declines a pending permission request.
  Future<void> declinePermissionRequest(
    PendingPermissionRequest request,
  ) async {
    _log.info(
      'permission request declined',
      fields: <String, Object?>{
        'peer': request.peerId.value,
        'requestedTier': request.requestedTier.name,
      },
    );
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
      final fileType = mimeTypeForFileName(fileName);

      offeredFiles.add(
        OfferedFile(
          fileId: fileId,
          fileName: fileName,
          size: length,
          fileType: fileType,
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
        clipboardSyncEnabled: device.clipboardSyncEnabled,
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
    final isImage = update.items.any(
      (item) => item.contentType == ClipboardContentType.imagePng,
    );

    for (final device in _devices.values) {
      if (!device.tier.canSyncClipboard) continue;
      if (!clipboard.isPeerEnabled(device.id)) continue;
      if (isImage && !clipboard.allowsImagesForPeer(device.id)) continue;
      if (!device.serverSession.session.isEstablished) continue;
      try {
        await device.serverSession.session.send(update);
      } on TransportError {
        // Session is tearing down; its watcher handles cleanup.
      }
    }
  }

  Future<void> _onRemoteClipboardAsync(
    ClipboardUpdate update, {
    DeviceId? peerId,
  }) async {
    if (!clipboard.remoteWins(update)) return;
    await clipboard.applyRemote(update, peerId: peerId);
  }

  void _onRemoteClipboard(ClipboardUpdate update) =>
      unawaited(_onRemoteClipboardAsync(update, peerId: _activeSessionPeerId));

  void _onClipboardSyncToggle(ClipboardSyncToggle toggle) {
    final peerId = _activeSessionPeerId;
    if (peerId == null) return;
    clipboard.handleToggle(peerId, toggle);
    final config = clipboard.getPeerConfig(peerId);
    _peerClipboardSettings[peerId.value] = config;
    unawaited(_persistPeerClipboardSettings());

    final device = _devices[peerId.value];
    if (device != null) {
      _devices[peerId.value] = ConnectedDevice(
        serverSession: device.serverSession,
        tier: device.tier,
        name: device.name,
        clipboardSyncEnabled: toggle.enabled,
      );
      _publishDevices();
    }
  }

  /// Updates clipboard sync enabled status for [peerId] from the desktop UI.
  Future<void> setPeerClipboardSync(DeviceId peerId, bool enabled) async {
    final currentConfig = clipboard.getPeerConfig(peerId);
    final newConfig = currentConfig.copyWith(enabled: enabled);
    clipboard.setPeerConfig(peerId, newConfig);
    _peerClipboardSettings[peerId.value] = newConfig;
    await _persistPeerClipboardSettings();

    final device = _devices[peerId.value];
    if (device != null) {
      _devices[peerId.value] = ConnectedDevice(
        serverSession: device.serverSession,
        tier: device.tier,
        name: device.name,
        clipboardSyncEnabled: enabled,
      );
      _publishDevices();

      if (device.serverSession.session.isEstablished) {
        try {
          await device.serverSession.session.send(
            ClipboardSyncToggle(
              enabled: enabled,
              allowImages: newConfig.allowImages,
              allowFiles: newConfig.allowFiles,
            ),
          );
        } on TransportError {
          // Session is tearing down; its watcher handles cleanup.
        }
      }
    }
  }

  Future<void> _loadPeerClipboardSettings() async {
    final file = peerClipboardSettingsFile;
    if (file == null || !file.existsSync()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          if (entry.value is Map<String, dynamic>) {
            final config = PeerClipboardConfig.fromJson(
              entry.value as Map<String, dynamic>,
            );
            _peerClipboardSettings[entry.key] = config;
            clipboard.setPeerConfig(DeviceId(entry.key), config);
          }
        }
      }
    } on FormatException catch (e) {
      _log.warn('could not load peer clipboard settings', error: e);
    }
  }

  Future<void> _persistPeerClipboardSettings() async {
    final file = peerClipboardSettingsFile;
    if (file == null) return;
    try {
      final directory = file.parent;
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      final payload = <String, Object?>{
        for (final entry in _peerClipboardSettings.entries)
          entry.key: entry.value.toJson(),
      };
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );
      await temporary.rename(file.path);
    } catch (e) {
      _log.warn('could not persist peer clipboard settings', error: e);
    }
  }

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

  /// Opens the Screen Recording pane, and asks the OS to prompt first.
  ///
  /// A separate grant from Accessibility, in a separate pane, and it fails in
  /// its own particular way: a capture without it does not error, it returns
  /// the desktop wallpaper with every window missing. So there is no point at
  /// which the user finds out by trying.
  ///
  /// `requestPermission` first because macOS only shows its own prompt once per
  /// app, and when it does it is far more direct than a settings pane the user
  /// has to navigate. Opening the pane afterwards covers the case where the
  /// prompt has already been dismissed at some point in the past.
  Future<void> openScreenRecordingSettings() async {
    if (NativeBackends.currentPlatform != PlatformKind.macos) return;
    _screenCapture.requestPermission();
    try {
      await Process.run('open', <String>[
        'x-apple.systempreferences:com.apple.preference.security'
            '?Privacy_ScreenCapture',
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
    await _screenCaptureAvailability.close();

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

    for (final stream in _screenStreams.values) {
      stream.cancel();
    }
    _screenStreams.clear();

    _input.dispose();
    _clipboardBackend.dispose();
    _media.dispose();
    _brightness.dispose();
    _systemInfo.dispose();
    _networkAdapters.dispose();
    _screenCapture.dispose();

    _devices.clear();
    await _deviceChanges.close();
    await _pairingRequests.close();
    await _permissionRequests.close();
    await _incomingTransferRequests.close();
    await _transferChanges.close();
    await _screenViewerChanges.close();

    _log.info('desktop service stopped');
  }

  void _onScreenStreamStart(ScreenStreamStart command) {
    final peerId = _activeSessionPeerId;
    if (peerId == null) return;
    final device = _devices[peerId.value];
    if (device == null) return;

    if (!_screenCapture.isAvailable) {
      _log.warn(
        'screen capture requested but backend is unavailable',
        fields: <String, Object?>{
          'peer': peerId.value,
          'reason': _screenCapture.unavailableReason,
        },
      );
      unawaited(
        device.serverSession.session.send(
          const ScreenStreamStop(reason: ScreenStopReason.unsupportedCodec),
        ),
      );
      return;
    }

    _stopScreenStream(peerId.value);

    final stream = _ActiveScreenStream(
      session: device.serverSession,
      start: command,
      clock: _clock,
    );
    _screenStreams[peerId.value] = stream;

    _startScreenCaptureTimer(stream);
    _publishScreenViewers();
    _log.info(
      'screen streaming started',
      fields: <String, Object?>{
        'peer': peerId.value,
        'fps': stream.targetFps,
        'monitorId': stream.monitorId,
      },
    );
  }

  void _onScreenStreamStop(ScreenStreamStop command) {
    final peerId = _activeSessionPeerId;
    if (peerId == null) return;
    _stopScreenStream(peerId.value);
    _log.info(
      'screen streaming stopped by peer',
      fields: <String, Object?>{
        'peer': peerId.value,
        'reason': command.reason.name,
      },
    );
  }

  void _onScreenConfigure(ScreenConfigure command) {
    final peerId = _activeSessionPeerId;
    if (peerId == null) return;
    final stream = _screenStreams[peerId.value];
    if (stream == null) return;

    final oldFps = stream.targetFps;
    stream.configure(command);
    if (stream.targetFps != oldFps) {
      _startScreenCaptureTimer(stream);
    }
    _log.info(
      'screen stream reconfigured',
      fields: <String, Object?>{
        'peer': peerId.value,
        'fps': stream.targetFps,
        'monitorId': stream.monitorId,
        'max': '${stream.maxWidth}x${stream.maxHeight}',
      },
    );
  }

  /// Schedules the next capture for [stream].
  ///
  /// One-shot and self-rescheduling rather than [Timer.periodic], because the
  /// target frame rate is a ceiling and not a promise. A periodic timer keeps
  /// firing at 30 Hz whether or not the previous frame has reached the phone,
  /// and the ticks it fires while a frame is still in flight do nothing except
  /// count themselves as skipped. Rescheduling from the end of each tick means
  /// the loop runs at the rate the link and the encoder can actually sustain,
  /// and speeds back up on its own when they can.
  void _startScreenCaptureTimer(_ActiveScreenStream stream) {
    stream.cancel();
    _scheduleNextCapture(stream);
    stream.cursorTimer = Timer.periodic(
      kCursorPollInterval,
      (_) => screenCursorTick(stream.session.peerId),
    );
  }

  /// Sends the pointer's position when it has moved.
  ///
  /// Periodic rather than self-rescheduling, unlike the capture loop, because
  /// there is nothing here to fall behind: the read is about ten microseconds
  /// and the message is 34 bytes, so a tick can never overrun its interval the
  /// way a capture can.
  ///
  /// Deliberately *not* awaiting the send. The point of this poll is that a
  /// pointer update never waits on anything, least of all on the screen frames
  /// it used to be trapped inside.
  @visibleForTesting
  void screenCursorTick(DeviceId peerId) {
    final stream = _screenStreams[peerId.value];
    if (stream == null) return;

    final device = _devices[peerId.value];
    if (device == null || !device.serverSession.session.isEstablished) return;

    final position = _screenCapture.cursorPosition(monitorId: stream.monitorId);
    // Most polls land here: a hand resting on a trackpad moves the pointer for
    // a fraction of the time the stream is open, and sending an unchanged
    // position would put the cursor back on the same footing as the frames.
    if (!stream.cursorMoved(position)) return;
    stream.rememberCursor(position);
    stream.cursorUpdates++;

    unawaited(
      device.serverSession.session.send(
        ScreenCursor(
          monitorId: stream.monitorId,
          x: position?.x,
          y: position?.y,
        ),
      ),
    );
  }

  void _scheduleNextCapture(_ActiveScreenStream stream) {
    final interval = stream.captureInterval;
    final elapsed = stream.sinceTickStart;
    // Never zero: a frame that took longer than its budget must still yield to
    // the event loop before the next one, or the capture loop starves
    // everything else on this isolate — including the heartbeat that keeps the
    // session alive.
    final wait = elapsed >= interval ? Duration.zero : interval - elapsed;
    stream.timer = Timer(wait, () {
      unawaited(
        screenCaptureTick(stream.session.peerId).whenComplete(() {
          if (_screenStreams[stream.session.peerId.value] != stream) return;
          _scheduleNextCapture(stream);
        }),
      );
    });
  }

  void _stopScreenStream(String peerKey) {
    final stream = _screenStreams.remove(peerKey);
    if (stream == null) return;
    stream.cancel();
    _publishScreenViewers();
  }

  /// Cuts off [peerId]'s view of this screen from the desktop side.
  ///
  /// The phone asked to start and can ask to stop, but the person whose screen
  /// it is must not have to reach for the phone to end it. Sends a stop so the
  /// viewer closes cleanly rather than freezing on the last frame it received.
  Future<void> stopScreenStreamFor(DeviceId peerId) async {
    if (!_screenStreams.containsKey(peerId.value)) return;
    _stopScreenStream(peerId.value);

    final device = _devices[peerId.value];
    if (device == null || !device.serverSession.session.isEstablished) return;
    try {
      await device.serverSession.session.send(
        const ScreenStreamStop(reason: ScreenStopReason.userClosed),
      );
    } on Object catch (e) {
      // The stream is already stopped locally; a peer that never hears about
      // it just stops receiving frames. Worth a line, not worth a throw.
      _log.warn('could not tell peer the stream ended', error: e);
    }
  }

  /// Stops the automatic capture loop without ending the stream.
  ///
  /// For tests that drive [screenCaptureTick] themselves. The loop reschedules
  /// itself in real time, so with it running the ticks a test issues interleave
  /// with ticks the timer issues, and every frame count the test asserts is
  /// really a count of both — which is how a deduplication test came to pass
  /// against a build with the deduplication removed.
  @visibleForTesting
  void pauseScreenCaptureLoop(DeviceId peerId) =>
      _screenStreams[peerId.value]?.cancel();

  /// Whether a screen capture stream is actively running for [peerId].
  bool isStreamingScreen(DeviceId peerId) =>
      _screenStreams.containsKey(peerId.value);

  /// Total frames skipped for [peerId] due to backpressure.
  int screenStreamSkippedCount(DeviceId peerId) =>
      _screenStreams[peerId.value]?.skippedFrames ?? 0;

  /// Pointer updates actually put on the wire for [peerId].
  ///
  /// Counted before the session's lossy queue, which is the only place the
  /// difference is visible: that queue collapses same-type messages sent in one
  /// turn into the newest, so a poll that sent unconditionally and one that
  /// sends only on movement are indistinguishable from the receiving end.
  @visibleForTesting
  int screenCursorUpdateCount(DeviceId peerId) =>
      _screenStreams[peerId.value]?.cursorUpdates ?? 0;

  /// Total frames not sent for [peerId] because the desk had not changed.
  ///
  /// Counted apart from [screenStreamSkippedCount] deliberately: a skipped
  /// frame means the link could not keep up and is a problem, an unchanged one
  /// means there was nothing to say and is the system working.
  int screenStreamUnchangedCount(DeviceId peerId) =>
      _screenStreams[peerId.value]?.unchangedFrames ?? 0;

  /// Total frames successfully captured and transmitted for [peerId].
  int screenStreamCapturedCount(DeviceId peerId) =>
      _screenStreams[peerId.value]?.capturedFrames ?? 0;

  /// Captures a single frame for [peerId] and transmits it if not congested.
  ///
  /// Backpressure rule:
  /// Capture is polled on a timer according to target FPS. If the previous
  /// frame's capture or network transmission is still in-flight
  /// (`isFrameInFlight == true`), this tick is skipped immediately.
  /// Skipped ticks do not allocate or encode a frame, avoiding backlog buildup
  /// in the network send queue and ensuring that the client receives the freshest
  /// frame as soon as the transport drains.
  Future<void> screenCaptureTick(DeviceId peerId) async {
    final stream = _screenStreams[peerId.value];
    if (stream == null) return;
    final device = _devices[peerId.value];
    if (device == null || !device.serverSession.session.isEstablished) {
      _stopScreenStream(peerId.value);
      return;
    }

    if (stream.isFrameInFlight) {
      stream.skippedFrames++;
      return;
    }

    stream.isFrameInFlight = true;
    stream.markTickStart();
    try {
      final frame = await _screenCapture.captureFrame(
        monitorId: stream.monitorId,
        maxWidth: stream.maxWidth,
        maxHeight: stream.maxHeight,
        quality: stream.quality,
      );
      if (frame == null) return;
      if (!_screenStreams.containsKey(peerId.value)) return;

      // Nothing on the desk has changed since the last frame the phone got.
      // Sending it again costs the same bandwidth as a frame that means
      // something, and a desk is still far more often than it is moving —
      // someone reading, thinking, or looking at a slide. Skipping is worth
      // roughly a megabyte a second of nothing, and the comparison itself is
      // too cheap to measure.
      if (stream.isUnchanged(frame)) {
        stream.unchangedFrames++;
        stream.idleRun++;
        return;
      }
      stream.remember(frame);

      final ptsMicros = _clock.now().microsecondsSinceEpoch;
      final screenFrame = ScreenFrame(
        sequence: stream.sequence++,
        ptsMicros: ptsMicros,
        isKeyframe: true,
        width: frame.width,
        height: frame.height,
        data: frame.data,
        // Still carried, though `ScreenCursor` is what a current phone acts on.
        // A peer built before that message exists reads the pointer only from
        // here, and dropping these fields would leave it aiming blind.
        cursorX: frame.cursorX,
        cursorY: frame.cursorY,
      );
      stream.capturedFrames++;
      // `awaitDrain` is what makes `isFrameInFlight` mean anything. A plain
      // `send` hands the frame to a buffer and returns, so the guard would
      // clear before a byte had left the machine and the next tick would
      // capture regardless — frames piling into the socket faster than the
      // link drains them, each one adding to the delay the viewer sees.
      // Waiting for the drain paces capture to the link instead of the clock.
      await stream.session.session.send(screenFrame, awaitDrain: true);
    } on Object catch (e) {
      _log.warn('screen frame send failed', error: e);
    } finally {
      stream.isFrameInFlight = false;
    }
  }
}

/// Tracks active screen streaming state for a connected peer.
final class _ActiveScreenStream {
  _ActiveScreenStream({
    required this.session,
    required this.start,
    required this.clock,
  })  : monitorId = start.monitorId,
        codec = start.codec,
        targetFps = start.targetFps.clamp(kMinFps, kMaxFps),
        targetBitrateKbps = start.targetBitrateKbps,
        maxWidth = start.maxWidth,
        maxHeight = start.maxHeight;

  final ServerSession session;
  final ScreenStreamStart start;
  final Clock clock;

  int monitorId;
  ScreenCodec codec;
  int targetFps;
  int targetBitrateKbps;
  int maxWidth;
  int maxHeight;

  /// Encoder quality implied by the requested bitrate.
  double get quality => screenJpegQualityForBitrate(targetBitrateKbps);

  int sequence = 0;
  int skippedFrames = 0;
  int capturedFrames = 0;
  int unchangedFrames = 0;
  int cursorUpdates = 0;
  bool isFrameInFlight = false;
  Timer? timer;

  /// Polls the pointer, independently of the capture loop.
  ///
  /// Its own timer rather than a faster capture loop, because the two jobs have
  /// nothing in common: capturing is expensive and worth doing rarely, reading
  /// the pointer is free and worth doing often. Tying them together meant the
  /// cursor could only be as smooth as the screen was cheap to send.
  Timer? cursorTimer;

  /// The last frame actually sent, for telling "nothing changed" from "the
  /// desk moved".
  ///
  /// The encoded bytes rather than a hash of them. A hash would be smaller and
  /// a collision would silently drop a frame that mattered, which shows up as
  /// the screen freezing on a picture that is subtly wrong — the worst kind of
  /// bug to be told about second-hand. A couple of hundred kilobytes per
  /// viewer is not worth that.
  Uint8List? _lastSentData;

  /// The pointer position last sent, so an unmoved pointer sends nothing.
  ///
  /// Sampled far more often than the screen is captured — the read costs about
  /// ten microseconds against thirty milliseconds for a capture — so most polls
  /// find it exactly where it was and send nothing at all.
  double? _lastSentCursorX;
  double? _lastSentCursorY;
  bool _hasSentCursor = false;

  /// How many captures in a row have found nothing new.
  int idleRun = 0;

  /// How long to wait before the next capture.
  ///
  /// Deduplication saves the bandwidth of a still desk but not the work: the
  /// frame is still grabbed, scaled and encoded before anything can tell it is
  /// unchanged, which on this machine is around thirty milliseconds of a core
  /// every time. Held at the full rate that is a core spinning continuously on
  /// a laptop to discover, thirty times a second, that nothing happened.
  ///
  /// So an idle stream polls more slowly, up to [_maxIdleBackoff] times its
  /// normal interval. The cost is latency on the *first* frame after the desk
  /// starts moving again; [remember] resets the run on any change, so the
  /// second frame onwards is back at full speed. Waking up slightly late once
  /// is a far better trade than never sleeping.
  Duration get captureInterval {
    final base = (1000 / targetFps).round();
    final slowdown = 1 + (idleRun ~/ _idleFramesPerStep);
    final capped = slowdown > _maxIdleBackoff ? _maxIdleBackoff : slowdown;
    return Duration(milliseconds: base * capped);
  }

  /// Unchanged captures before the interval lengthens another step.
  static const int _idleFramesPerStep = 15;

  /// Slowest the idle poll may get, as a multiple of the normal interval.
  ///
  /// Four, so a 30 fps stream idles at around 7 Hz. Past that the delay before
  /// the picture starts moving again becomes noticeable as a stutter when the
  /// user begins to work.
  static const int _maxIdleBackoff = 4;

  /// Whether [frame] would tell the phone anything it does not already know.
  ///
  /// The picture only. The cursor used to be part of this comparison, because
  /// it travelled on the frame and comparing only the image would have frozen
  /// the drawn pointer exactly when the user was moving it. The cost was that a
  /// pointer crossing a still desktop re-sent the whole encoded frame — 213,622
  /// bytes to report that an arrow had moved a few pixels, which no home
  /// network carries at any useful rate. The pointer now has [ScreenCursor] to
  /// itself, so a still desk with a moving mouse sends no frames at all.
  bool isUnchanged(CapturedFrame frame) {
    final previous = _lastSentData;
    if (previous == null) return false;
    if (previous.length != frame.data.length) return false;

    for (var i = 0; i < previous.length; i++) {
      if (previous[i] != frame.data[i]) return false;
    }
    return true;
  }

  void remember(CapturedFrame frame) {
    _lastSentData = frame.data;
    idleRun = 0;
  }

  /// Whether [position] is somewhere the phone has not been told about.
  bool cursorMoved(({double x, double y})? position) =>
      !_hasSentCursor ||
      position?.x != _lastSentCursorX ||
      position?.y != _lastSentCursorY;

  void rememberCursor(({double x, double y})? position) {
    _lastSentCursorX = position?.x;
    _lastSentCursorY = position?.y;
    _hasSentCursor = true;
  }

  /// Forgets the last frame, so the next capture is always sent.
  ///
  /// Called when the stream's shape changes. After a reconfigure the phone is
  /// expecting a different size or a different display, and a frame withheld
  /// because it matched the *old* one would leave it showing the previous
  /// monitor until something on that monitor happened to move.
  void forgetLastFrame() {
    _lastSentData = null;
    _lastSentCursorX = null;
    _lastSentCursorY = null;
    _hasSentCursor = false;
    idleRun = 0;
  }

  /// Wall time the current tick began, for pacing the next one.
  ///
  /// Measured from the *start* of the tick rather than its end so that the
  /// frame rate is a rate: a tick that takes 12 ms of a 33 ms budget waits 21,
  /// not 33, and the stream holds 30 fps instead of drifting down to 22.
  DateTime? _tickStartedAt;

  void markTickStart() => _tickStartedAt = clock.now();

  Duration get sinceTickStart {
    final started = _tickStartedAt;
    if (started == null) return Duration.zero;
    final elapsed = clock.now().difference(started);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  void configure(ScreenConfigure update) {
    forgetLastFrame();
    if (update.monitorId != null) monitorId = update.monitorId!;
    if (update.maxWidth != null) maxWidth = update.maxWidth!;
    if (update.maxHeight != null) maxHeight = update.maxHeight!;
    if (update.targetBitrateKbps != null) {
      targetBitrateKbps = update.targetBitrateKbps!;
    }
    if (update.targetFps != null) {
      targetFps = update.targetFps!.clamp(kMinFps, kMaxFps);
    }
  }

  void cancel() {
    timer?.cancel();
    timer = null;
    cursorTimer?.cancel();
    cursorTimer = null;
  }
}
