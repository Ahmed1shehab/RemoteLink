import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/brand.dart';
import 'phone_advertiser.dart';

/// What this phone offers a device that connects *to* it.
///
/// Much narrower than [kMobileCapabilities], and the difference is the point. A
/// capability bit is a claim about what this end takes part in, and the two
/// ends intersect theirs. As a client the phone says `mouse` to mean "I can
/// send pointer events"; as a host the same bit would mean "you may move my
/// cursor", which is not something a phone can honour and not something anyone
/// asked for. Listing it would make a desktop show controls that go nowhere.
///
/// So the host claims the two things that are symmetrical — a file and a
/// clipboard travel the same in either direction — plus compression, which is
/// a property of the link rather than of a feature.
const Capabilities kPhoneHostCapabilities = Capabilities(
  Capabilities.clipboardText |
      Capabilities.fileTransfer |
      Capabilities.compression,
);

/// The port the phone listens on when it is hosting.
///
/// One above the desktop's. They could share a number — these are different
/// devices — but not always: `flutter run -d macos` on the phone app is the
/// fastest way to test this, and a developer running both halves on one Mac
/// would otherwise hit a collision on every launch. The server falls back to
/// any free port anyway and discovery carries whichever one it bound, so this
/// constant is a preference, not a contract.
const int kPhoneHostPort = 47812;

/// A device that connected to this phone and was let in.
@immutable
final class InboundLink {
  const InboundLink({
    required this.session,
    required this.peerId,
    required this.name,
    required this.platform,
    required this.since,
  });

  final Session session;
  final DeviceId peerId;
  final String name;
  final PlatformKind platform;
  final DateTime since;

  InboundLink withName(String name) => InboundLink(
        session: session,
        peerId: peerId,
        name: name,
        platform: platform,
        since: since,
      );

  InboundLink withPlatform(PlatformKind platform) => InboundLink(
        session: session,
        peerId: peerId,
        name: name,
        platform: platform,
        since: since,
      );
}

/// Someone at the door, waiting for the user to confirm six digits.
@immutable
final class PendingInboundPairing {
  const PendingInboundPairing({
    required this.session,
    required this.peerId,
    required this.shortAuthenticationString,
    required this.requestedAt,
  });

  final ServerSession session;
  final DeviceId peerId;
  final String shortAuthenticationString;
  final DateTime requestedAt;

  /// What to call the device before it has told us its name.
  ///
  /// The short device id, not a guess. The peer *has* sent a name by now in the
  /// ordinary case, but a name arriving from an unpaired stranger is exactly
  /// the string an attacker controls — showing "MacBook Pro" next to a code
  /// the user is about to approve is the confusion the SAS exists to prevent.
  String get provisionalName => peerId.short;
}

/// A device this phone already trusts, waiting to be let in.
///
/// The counterpart to [PendingInboundPairing] for a device that has paired
/// before. There are no digits to compare — the handshake already verified the
/// stored key — so this carries a name instead, and the name comes from the
/// trust store rather than from the connecting device.
@immutable
final class PendingInboundConnection {
  const PendingInboundConnection({
    required this.session,
    required this.peerId,
    required this.peerName,
    required this.platform,
    required this.requestedAt,
  });

  final ServerSession session;
  final DeviceId peerId;
  final String peerName;
  final PlatformKind platform;
  final DateTime requestedAt;
}

/// A connected device this phone could stop asking about.
///
/// Raised once the device is already in, never while it is being held — the
/// question is about future connections, and stacking it on the one in front of
/// the user turns two decisions into one tap.
@immutable
final class PendingInboundRemember {
  const PendingInboundRemember({
    required this.session,
    required this.peerId,
    required this.peerName,
  });

  final ServerSession session;
  final DeviceId peerId;

  /// The stored name, as everywhere else a peer is named on screen.
  final String peerName;
}

/// A message that arrived over an inbound session and is allowed through.
@immutable
final class InboundMessage {
  const InboundMessage(this.session, this.message);

  final Session session;
  final Message message;
}

/// Makes this phone something another device can find and send to.
///
/// The phone has always been a pure client: it dials a computer, and everything
/// it can do is something it asks the computer to perform. Sending a file to
/// another phone breaks that shape, because a transfer needs one end listening
/// and neither phone was ever the one that listens.
///
/// This is that end. It is the same [RemoteLinkServer] the desktop runs, with
/// the same handshake, the same trust store and the same six-digit
/// confirmation — a phone is not a lesser kind of peer and does not get a
/// lesser kind of pairing.
///
/// What it is *not* is a second desktop. See [isAllowedFromPeer]: everything
/// arriving over an inbound session is checked against a list of what a phone
/// can meaningfully be asked to do, and the list has two entries. CONTRIBUTING
/// §4 puts the permission check on the listening side, per message, because the
/// peer is untrusted input however it authenticated. That reasoning does not
/// change when the listener is a phone.
final class PhoneHostService {
  PhoneHostService({
    required this.identity,
    required this.trustStore,
    required Clock clock,
    required String Function() describeName,
    required this.onTrustChanged,
    NetworkAdvertiser? advertiser,
    UdpDiscoveryServer? beacon,
    int port = kPhoneHostPort,
  })  : _clock = clock,
        _describeName = describeName,
        _port = port,
        _advertiser = advertiser,
        _beacon = beacon;

  final DeviceIdentity identity;
  final TrustStore trustStore;

  /// Called after a pairing writes a new peer, so the app can persist the trust
  /// store and refresh anything reading it.
  ///
  /// A callback rather than a store write here: which key the peers are saved
  /// under, and which providers have to be invalidated afterwards, is the app's
  /// business and this class has no opinion on it.
  final Future<void> Function() onTrustChanged;

  final Clock _clock;
  final String Function() _describeName;
  final int _port;

  final Log _log = Log.scoped('mobile.host');

  late final PairingCoordinator _pairing = PairingCoordinator(
    identity: identity,
    clock: _clock,
  );

  NetworkAdvertiser? _advertiser;
  UdpDiscoveryServer? _beacon;
  RemoteLinkServer? _server;

  StreamSubscription<ServerSession>? _acceptedSubscription;
  StreamSubscription<ServerSession>? _endedSubscription;
  final Map<String, StreamSubscription<Message>> _messageSubscriptions =
      <String, StreamSubscription<Message>>{};

  final Map<String, InboundLink> _links = <String, InboundLink>{};
  final Map<String, PendingInboundPairing> _pending =
      <String, PendingInboundPairing>{};
  final Map<String, PendingInboundConnection> _pendingConnections =
      <String, PendingInboundConnection>{};

  /// Remember-this-device agreements in progress, by device id.
  ///
  /// One per live session and gone with it: an agreement that did not settle
  /// before the link dropped is no agreement at all, and the question is put
  /// again the next time both ends are up.
  final Map<String, RememberAgreement> _agreements =
      <String, RememberAgreement>{};

  /// Questions raised and not yet answered, by device id.
  ///
  /// Kept as a list beside the stream because the prompts are drained one at a
  /// time — see `listenForNearbyPrompts` — and a question that arrived while
  /// another sheet was up has to still be there when the loop comes back for
  /// it, rather than having been a stream event nobody was listening to.
  final Map<String, PendingInboundRemember> _pendingRemembers =
      <String, PendingInboundRemember>{};

  /// Devices a person has let in since the app started.
  ///
  /// Not persisted, for the same reason the desktop's is not: "until you close
  /// the app" is a window the user can hold in their head, and a stored answer
  /// is one given by whoever was holding the phone last time.
  final Set<String> _admittedThisRun = <String>{};

  final StreamController<List<InboundLink>> _linkChanges =
      StreamController<List<InboundLink>>.broadcast();
  final StreamController<List<PendingInboundPairing>> _pendingChanges =
      StreamController<List<PendingInboundPairing>>.broadcast();
  final StreamController<List<PendingInboundConnection>>
      _pendingConnectionChanges =
      StreamController<List<PendingInboundConnection>>.broadcast();
  final StreamController<List<PendingInboundRemember>> _rememberRequests =
      StreamController<List<PendingInboundRemember>>.broadcast();
  final StreamController<InboundMessage> _messages =
      StreamController<InboundMessage>.broadcast();

  /// Devices currently connected to this phone.
  List<InboundLink> get links => _links.values.toList(growable: false);

  /// Devices currently connected to this phone, as they come and go.
  Stream<List<InboundLink>> get linkChanges => _linkChanges.stream;

  /// Devices waiting to be let in.
  List<PendingInboundPairing> get pending => _pending.values.toList(
        growable: false,
      );

  /// Devices waiting to be let in, as they arrive and are answered.
  Stream<List<PendingInboundPairing>> get pendingChanges =>
      _pendingChanges.stream;

  /// Trusted devices waiting for someone to allow the connection.
  List<PendingInboundConnection> get pendingConnections =>
      _pendingConnections.values.toList(growable: false);

  /// Trusted devices waiting to be allowed, as they knock and are answered.
  Stream<List<PendingInboundConnection>> get pendingConnectionChanges =>
      _pendingConnectionChanges.stream;

  /// Connected devices this phone could be told to stop asking about.
  List<PendingInboundRemember> get pendingRemembers =>
      _pendingRemembers.values.toList(growable: false);

  /// The same, as they are raised and answered.
  Stream<List<PendingInboundRemember>> get rememberChanges =>
      _rememberRequests.stream;

  /// Allowed messages from connected devices, paired with the session they came
  /// in on so a reply goes back to the sender rather than to whoever happens to
  /// be connected.
  Stream<InboundMessage> get messages => _messages.stream;

  bool get isRunning => _server != null;

  /// The port actually bound, for a beacon to advertise.
  int get boundPort => _server?.boundPort ?? _port;

  /// Whether a device that has never paired may knock.
  ///
  /// Kept as a field the UI can flip rather than a constructor argument: it is
  /// the "who can find me" switch, and it has to be changeable while the host
  /// is up or it is no use.
  bool acceptsNewPairings = true;

  /// Whether a device this phone already trusts is asked about each time it
  /// connects.
  ///
  /// The same promise the desktop makes, and it matters more here rather than
  /// less: a phone is handed around, left on a table, and carried into range of
  /// people its owner has paired with once. Asked once per device per run of
  /// the app — a phone's link drops every time the screen locks, and a prompt
  /// on each of those would be tapped away without being read.
  bool get asksBeforeConnecting => _asksBeforeConnecting;

  set asksBeforeConnecting(bool value) {
    _asksBeforeConnecting = value;
    _server?.asksBeforeAdmitting = value;
  }

  bool _asksBeforeConnecting = true;

  /// Starts listening and announcing.
  ///
  /// Nothing here is fatal to the app. A phone that cannot host is a phone that
  /// works exactly as it did before this feature existed — it can still reach
  /// every computer and every phone that *is* hosting — so a bind failure is
  /// logged and swallowed rather than thrown at a screen that has no useful
  /// thing to say about it.
  Future<void> start() async {
    if (_server != null) return;

    final server = RemoteLinkServer(
      identity: identity,
      capabilities: kPhoneHostCapabilities,
      trustStore: trustStore,
      clock: _clock,
      port: _port,
    )..asksBeforeAdmitting = _asksBeforeConnecting;

    try {
      await server.start();
    } on Object catch (e) {
      _log.warn('could not listen for nearby devices', error: e);
      return;
    }
    _server = server;

    _acceptedSubscription = server.accepted.listen(
      (session) => unawaited(_onAccepted(session)),
      cancelOnError: false,
    );
    _endedSubscription = server.ended.listen(
      (session) => unawaited(_onEnded(session)),
      cancelOnError: false,
    );

    // Bonjour first and unconditionally, because on iOS it is the only route
    // that works without an entitlement Apple grants by written application.
    final advertiser =
        _advertiser ??= PhoneAdvertiser(describe: describeBeacon);
    await advertiser.start();

    // The UDP beacon is a bonus, not a requirement, and on iOS it is expected
    // to fail — the same multicast restriction that stops an iPhone receiving
    // the desktop's beacon stops it sending one. Attempted anyway rather than
    // gated on `Platform.isAndroid`, because the answer is a property of the
    // network and the entitlement rather than of the operating system's name,
    // and one try that fails costs a log line.
    final beacon = _beacon ??= UdpDiscoveryServer(describe: describeBeacon);
    try {
      await beacon.start();
    } on Object catch (e) {
      _beacon = null;
      _log.debug(() => 'no UDP beacon from this phone: $e');
    }

    _log.info(
      'this phone is discoverable',
      fields: <String, Object?>{
        'port': server.boundPort,
        'device': identity.id.value,
      },
    );
  }

  /// Stops listening, announcing, and everything already connected.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server == null) return;

    await _acceptedSubscription?.cancel();
    _acceptedSubscription = null;
    await _endedSubscription?.cancel();
    _endedSubscription = null;
    for (final subscription in _messageSubscriptions.values) {
      await subscription.cancel();
    }
    _messageSubscriptions.clear();

    await _advertiser?.stop();
    await _beacon?.stop();
    await server.stop();

    _links.clear();
    _pending.clear();
    _pendingConnections.clear();
    _publishLinks();
    _publishPending();
    _publishPendingConnections();

    _log.info('this phone is no longer discoverable');
  }

  Future<void> dispose() async {
    await stop();
    await _linkChanges.close();
    await _pendingChanges.close();
    await _pendingConnectionChanges.close();
    await _rememberRequests.close();
    await _messages.close();
  }

  /// This phone as it appears to something browsing the network.
  ///
  /// Built fresh on every call and shared by both advertisers, so the two can
  /// never drift and a rename reaches the next announcement rather than waiting
  /// for a restart.
  @visibleForTesting
  Beacon describeBeacon() => Beacon(
        kind: BeaconKind.announce,
        deviceId: identity.id,
        name: _describeName(),
        platform: NativeBackends.currentPlatform,
        servicePort: boundPort,
        protocolVersion: kProtocolVersion,
        publicKeyFingerprint: Uint8List.sublistView(identity.publicKey, 0, 8),
        capabilities: kPhoneHostCapabilities,
        acceptsNewPairings: acceptsNewPairings,
        activeSessions: _links.length,
      );

  /// This phone, told to a peer once the session is usable.
  DeviceInfo describeSelf() => DeviceInfo(
        id: identity.id,
        name: _describeName(),
        platform: NativeBackends.currentPlatform,
        // The listening end, which is what this field records. The name is the
        // desktop's history rather than a claim about hardware.
        role: PeerRole.server,
        appVersion: kAppVersion,
      );

  @visibleForTesting
  Future<void> acceptForTesting(ServerSession session) => _onAccepted(session);

  Future<void> _onAccepted(ServerSession session) async {
    if (session.awaitingPairing) {
      await _onKnock(session);
      return;
    }

    final peer = await trustStore.findByPublicKey(
      session.handshake.peerStaticPublicKey,
    );

    // A device both ends agreed to remember is let straight in, and so is one
    // already allowed this run: the first because two people said so and it
    // survives a restart, the second because a Wi-Fi drop must not become a
    // dialog.
    if (session.awaitingApproval &&
        peer?.autoAdmit != true &&
        !_admittedThisRun.contains(session.peerId.value)) {
      await _hold(session, peer);
      return;
    }

    await _admit(session, name: peer?.name, platform: peer?.platform);
  }

  /// A device this phone has paired with, asking to come in now.
  Future<void> _hold(ServerSession session, TrustedPeer? peer) async {
    final pending = PendingInboundConnection(
      session: session,
      peerId: session.peerId,
      // The stored name, never one the peer sent with this connection. A
      // paired device is not a stranger, but it is still the party asking, and
      // a name it can rewrite between connections is a name that can wear
      // another device's in the prompt.
      peerName: peer?.name ?? session.peerId.short,
      platform: peer?.platform ?? PlatformKind.unknown,
      requestedAt: _clock.now(),
    );
    _pendingConnections[session.peerId.value] = pending;

    // Told before asked, so the other device shows "waiting" rather than a
    // session that behaves exactly like a dead one.
    try {
      await session.session.send(
        ConnectionRequest(
          deviceName: _describeName(),
          timeoutSeconds: kConnectionApprovalWindow.inSeconds,
        ),
      );
    } on Object catch (e) {
      _pendingConnections.remove(session.peerId.value);
      _log.debug(() => 'could not tell a peer it was waiting: $e');
      return;
    }

    _publishPendingConnections();
    _scheduleApprovalExpiry(pending);
  }

  /// Turns an unanswered request away rather than leaving the peer spinning.
  void _scheduleApprovalExpiry(PendingInboundConnection pending) {
    unawaited(() async {
      await _clock.delay(kConnectionApprovalWindow);
      if (_pendingConnections[pending.peerId.value] != pending) return;
      await _refuse(pending, ConnectionAnswer.timedOut);
    }());
  }

  /// Lets a held connection in, and stops asking about that device this run.
  Future<void> approveConnection(PendingInboundConnection request) async {
    if (_pendingConnections.remove(request.peerId.value) != request) return;
    _publishPendingConnections();
    _admittedThisRun.add(request.peerId.value);

    // The decision first, then the welcome: the peer unblocks its own screen
    // on this message, and the grant that [_admit] sends would otherwise arrive
    // while it still believed it was waiting.
    await request.session.session.send(
      const ConnectionDecision(ConnectionAnswer.allowed),
    );
    await _admit(
      request.session,
      name: request.peerName,
      platform: request.platform,
    );

    _log.info(
      'let a trusted device in',
      fields: <String, Object?>{'peer': request.peerId.value},
    );
  }

  /// Turns a held connection away.
  Future<void> declineConnection(PendingInboundConnection request) async {
    if (_pendingConnections.remove(request.peerId.value) != request) return;
    _publishPendingConnections();
    await _refuse(request, ConnectionAnswer.declined);
  }

  Future<void> _refuse(
    PendingInboundConnection request,
    ConnectionAnswer answer,
  ) async {
    if (_pendingConnections.remove(request.peerId.value) != null) {
      _publishPendingConnections();
    }
    try {
      await request.session.session.send(ConnectionDecision(answer));
    } on Object catch (e) {
      // The peer may already be gone, and the answer was "no" either way.
      _log.debug(() => 'could not tell the peer it was turned away: $e');
    }
    await request.session.session.close(reason: CloseReason.userRequested);

    _log.info(
      'turned a connection away',
      fields: <String, Object?>{
        'peer': request.peerId.value,
        'answer': answer.name,
      },
    );
  }

  /// A device that has never paired with this phone.
  Future<void> _onKnock(ServerSession session) async {
    if (!acceptsNewPairings) {
      await session.session.close(reason: CloseReason.userRequested);
      return;
    }

    // Before anything is shown. A peer that has burned its attempts cannot even
    // raise a prompt, which is what stops a stranger on the café Wi-Fi papering
    // the screen with six-digit codes until one gets tapped out of irritation.
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

    _pending[session.peerId.value] = PendingInboundPairing(
      session: session,
      peerId: session.peerId,
      shortAuthenticationString: session.handshake.shortAuthenticationString,
      requestedAt: _clock.now(),
    );
    _publishPending();
  }

  /// Lets a session through and starts reading from it.
  Future<void> _admit(
    ServerSession session, {
    String? name,
    PlatformKind? platform,
  }) async {
    // A no-op for a session that was never held, and the whole of the
    // difference for one that was: until this runs the session drops every
    // message outside the handshake and trust subsystems, including the grant
    // and the device info sent at the bottom of this method.
    session.session.admit();

    _links[session.peerId.value] = InboundLink(
      session: session.session,
      peerId: session.peerId,
      name: name ?? session.peerId.short,
      platform: platform ?? PlatformKind.unknown,
      since: _clock.now(),
    );
    _publishLinks();

    _messageSubscriptions[session.peerId.value] = session.session.messages
        .listen((message) => _onMessage(session, message),
            cancelOnError: false);

    // A tier is sent because the protocol expects one and the peer's client
    // will wait for it. It says nothing about what this phone will actually do
    // — [isAllowedFromPeer] decides that, message by message, and it would
    // refuse a keystroke from a peer holding every tier there is.
    await session.session.send(
      const PermissionGrant(tier: PermissionTier.standard),
    );
    await session.session.send(DeviceInfoMessage(describeSelf()));
    await _maybeAskToRemember(session);
  }

  /// Puts "should we stop asking about this device?" to the user, once.
  ///
  /// Nothing goes on the wire here: the peer is asking its own user the same
  /// question at the same moment, and what is sent is each side's answer.
  Future<void> _maybeAskToRemember(ServerSession session) async {
    final peer = await trustStore.findByPublicKey(
      session.handshake.peerStaticPublicKey,
    );
    if (!shouldAskToRemember(peer)) return;
    if (_agreements.containsKey(session.peerId.value)) return;

    _agreements[session.peerId.value] = RememberAgreement(
      peerId: session.peerId,
      peerName: peer!.name,
    );
    final pending = PendingInboundRemember(
      session: session,
      peerId: session.peerId,
      peerName: peer.name,
    );
    _pendingRemembers[session.peerId.value] = pending;
    _publishPendingRemembers();
  }

  void _publishPendingRemembers() {
    if (_rememberRequests.isClosed) return;
    _rememberRequests.add(pendingRemembers);
  }

  /// Records what the user said and tells the peer.
  ///
  /// The answer goes out whichever way it went: a peer with its own copy of
  /// this question on screen has no way to take it down but an answer.
  Future<void> answerRemember(
    PendingInboundRemember request, {
    required bool agreed,
  }) async {
    if (_pendingRemembers.remove(request.peerId.value) != null) {
      _publishPendingRemembers();
    }
    final agreement = _agreements[request.peerId.value];
    if (agreement == null) return;
    if (!agreement.recordMine(agreed: agreed)) return;

    try {
      await request.session.session.send(RememberConnection(agreed: agreed));
    } on Object catch (e) {
      _log.debug(() => 'could not send a remember answer: $e');
    }
    await _settleRemember(request.peerId);
  }

  /// The peer's half of the agreement.
  Future<void> _onPeerRemember(
    ServerSession session, {
    required bool agreed,
  }) async {
    final agreement = _agreements[session.peerId.value];
    if (agreement == null) {
      // Nothing was asked here, so this phone already remembers the device and
      // its answer is already yes. Saying so lets a peer that has forgotten us
      // agree again without a round that could never complete.
      final peer = await trustStore.findById(session.peerId);
      if (peer == null || !peer.autoAdmit) return;
      try {
        await session.session.send(const RememberConnection(agreed: true));
      } on Object catch (_) {
        // Nothing left to tell.
      }
      return;
    }
    if (!agreement.recordTheirs(agreed: agreed)) return;
    await _settleRemember(session.peerId);
  }

  /// Writes down a settled agreement, and only a settled one.
  Future<void> _settleRemember(DeviceId peerId) async {
    final agreement = _agreements[peerId.value];
    // Nothing is written before this device's own user has answered. The peer
    // saying yes on its own is not a record of anything having been asked here.
    if (agreement == null || agreement.mine == null) return;
    // Kept alive while it is only half answered, so the peer's answer arriving
    // later in this same session can still settle it into a promise.
    if (agreement.isSettled) _agreements.remove(peerId.value);

    final peer = await trustStore.findById(peerId);
    if (peer == null) return;
    await trustStore.upsert(agreement.applyTo(peer));
    await onTrustChanged();

    _log.info(
      switch ((agreement.isAgreed, agreement.isSettled)) {
        (true, _) => 'both ends agreed to remember each other',
        (_, true) => 'this connection will not be remembered',
        (_, false) => 'answered here; waiting on the other end',
      },
      fields: <String, Object?>{'peer': peerId.value},
    );
  }

  void _onMessage(ServerSession session, Message message) {
    // Answered here rather than forwarded, for the same reason as the device
    // info below: its effect is on this class's own state, and it is not a
    // request for the phone to *do* anything — see [isAllowedFromPeer], which
    // is about that second question and rightly refuses this one.
    if (message is RememberConnection) {
      unawaited(_onPeerRemember(session, agreed: message.agreed));
      return;
    }

    // Learning the peer's name is handled here rather than passed through,
    // because it is the one message whose effect is on this class's own state.
    if (message is DeviceInfoMessage) {
      final existing = _links[session.peerId.value];
      if (existing == null) return;
      final sanitised = sanitiseDeviceName(message.info.name);
      _links[session.peerId.value] = existing
          .withName(sanitised ?? existing.name)
          .withPlatform(message.info.platform);
      _publishLinks();
      unawaited(_rememberPeerInfo(session.peerId, message.info));
      return;
    }

    if (!isAllowedFromPeer(message)) {
      // Dropped rather than answered. There is no "not supported" reply in the
      // protocol for a message a peer had no business sending, and inventing
      // one would tell a prober which messages exist.
      _log.debug(
        () => 'ignored ${message.runtimeType} from ${session.peerId.short}',
      );
      return;
    }

    if (!_messages.isClosed) {
      _messages.add(InboundMessage(session.session, message));
    }
  }

  Future<void> _onEnded(ServerSession session) async {
    await _messageSubscriptions.remove(session.peerId.value)?.cancel();
    // Half an agreement is not kept for the next session: the other half is on
    // a device that is no longer here.
    _agreements.remove(session.peerId.value);
    if (_pendingRemembers.remove(session.peerId.value) != null) {
      _publishPendingRemembers();
    }
    final wasLinked = _links.remove(session.peerId.value) != null;
    final wasPending = _pending.remove(session.peerId.value) != null;
    final wasHeld = _pendingConnections.remove(session.peerId.value) != null;
    if (wasLinked) _publishLinks();
    if (wasPending) _publishPending();
    if (wasHeld) _publishPendingConnections();
  }

  /// Approves a device the user has confirmed the six digits with.
  ///
  /// The trust record is built from the handshake result, never from anything
  /// the peer claimed, so a device cannot register a key it does not hold.
  Future<void> approvePairing(PendingInboundPairing request) async {
    if (_pending.remove(request.peerId.value) == null) return;
    _publishPending();

    final peer = _pairing.accept(
      handshake: request.session.handshake,
      peerName: request.provisionalName,
      platform: PlatformKind.unknown,
      permissionTier: PermissionTier.standard.wireValue,
      lastAddress: request.session.address,
    );
    await trustStore.upsert(peer);
    await onTrustChanged();

    request.session.session.completePairing();
    await _admit(request.session, name: peer.name);

    _log.info(
      'let a nearby device in',
      fields: <String, Object?>{'peer': request.peerId.value},
    );
  }

  /// Turns a device away.
  Future<void> declinePairing(PendingInboundPairing request) async {
    if (_pending.remove(request.peerId.value) == null) return;
    _publishPending();

    final rejection = _pairing.reject(
      peerId: request.peerId,
      reason: PairRejectReason.declined,
    );
    try {
      await request.session.session.send(rejection);
    } on Object catch (e) {
      // The peer may already be gone, and there is nothing to do about it: the
      // user's answer was "no", and a send that fails still leaves them
      // unpaired.
      _log.debug(() => 'could not tell the peer it was declined: $e');
    }
    await request.session.session.close(reason: CloseReason.userRequested);
  }

  /// Gracefully closes an inbound link with [peerId].
  Future<void> disconnectPeer(DeviceId peerId) async {
    final link = _links[peerId.value];
    if (link != null) {
      await link.session.close(reason: CloseReason.userRequested);
    }
  }

  /// Disconnects a device and forgets it.
  Future<void> revoke(DeviceId peerId) async {
    await _server?.revokePeer(peerId);
    await onTrustChanged();
  }

  Future<void> _rememberPeerInfo(DeviceId peerId, DeviceInfo info) async {
    final peer = await trustStore.findById(peerId);
    if (peer == null) return;
    final sanitised = sanitiseDeviceName(info.name);
    final newName = sanitised ?? peer.name;
    if (peer.name == newName && peer.platform == info.platform) return;
    await trustStore.upsert(
      TrustedPeer(
        id: peer.id,
        publicKey: peer.publicKey,
        name: newName,
        platform: info.platform != PlatformKind.unknown
            ? info.platform
            : peer.platform,
        pairedAt: peer.pairedAt,
        permissionTier: peer.permissionTier,
        lastSeenAt: _clock.now(),
        lastAddress: peer.lastAddress,
        revoked: peer.revoked,
        // Carried across explicitly: this rebuilds the record rather than
        // copying it, so a field left out here is a field silently reset — and
        // resetting these two would un-remember a device because it told us
        // its name.
        autoAdmit: peer.autoAdmit,
        rememberAsked: peer.rememberAsked,
      ),
    );
    await onTrustChanged();
  }

  void _publishLinks() {
    if (!_linkChanges.isClosed) _linkChanges.add(links);
  }

  void _publishPending() {
    if (!_pendingChanges.isClosed) _pendingChanges.add(pending);
  }

  void _publishPendingConnections() {
    if (!_pendingConnectionChanges.isClosed) {
      _pendingConnectionChanges.add(pendingConnections);
    }
  }
}

/// Whether this phone will act on [message] when a peer sends it in.
///
/// The phone's answer to `CommandDispatcher`, and it denies by default for the
/// same reason: the list is what a phone can meaningfully be asked to do by
/// something on the other side of a socket, and everything else is either
/// meaningless here or a thing no one asked for. A `KeyEvent` arriving at a
/// phone is not a feature waiting to be built — it is a message that should
/// never have been sent, and treating it as one is how the desktop's dispatcher
/// stays honest too.
///
/// Written as an exhaustive-looking switch on purpose. Adding a message type to
/// the protocol does not silently widen what a phone accepts; the default arm
/// catches it and a test asserts the shape of this list.
bool isAllowedFromPeer(Message message) => switch (message) {
      // A transfer, in either direction. The inbound half is the feature; the
      // outbound half is here because a peer this phone is *sending* to answers
      // on the same session, and its FileAccept is not a lesser message for
      // having arrived over a link the peer opened.
      FileOffer() ||
      FileAccept() ||
      FileChunk() ||
      FileComplete() ||
      FileAbort() =>
        true,

      // Text. `ClipboardUpdate` is how a shared link arrives; `ClipboardRequest`
      // is a peer asking for this phone's current clipboard, which it may have
      // and which costs nothing to answer.
      ClipboardUpdate() || ClipboardRequest() => true,
      _ => false,
    };
