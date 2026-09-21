import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/host/phone_advertiser.dart';
import 'package:remotelink_mobile/src/features/host/phone_host_service.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

void main() {
  group('what a phone will act on', () {
    // The phone's answer to the desktop's dispatcher test, and it exists for
    // the same reason: the list denies by default, so a message type added to
    // the protocol later cannot quietly widen what a phone accepts from
    // something on the other side of a socket. If this table has to be edited
    // to make a new feature work, that edit is the decision being made
    // deliberately rather than by omission.
    final allowed = <String, Message>{
      'a file offer': FileOffer(transferId: 't', files: const <OfferedFile>[]),
      'an acceptance of one we sent': const FileAccept(
        transferId: 't',
        sessionId: 's-1',
        fileTokens: <String, String>{},
      ),
      'a chunk': FileChunk(
        transferId: 't',
        sessionId: 's-1',
        fileId: 'f',
        token: 'tok',
        offset: 0,
        bytes: Uint8List(0),
      ),
      'the end of a file': FileComplete(
        transferId: 't',
        fileId: 'f',
        sha256: Uint8List(32),
      ),
      'an abort': const FileAbort(
        transferId: 't',
        reason: FileAbortReason.cancelled,
      ),
      'text arriving': ClipboardUpdate(
        items: const <ClipboardItem>[],
        contentHash: Uint8List(16),
        originDeviceId: 'x',
        originSequence: 1,
      ),
      'a request for our clipboard': const ClipboardRequest(),
    };

    final refused = <String, Message>{
      'a mouse move': const MouseMove(deltaX: 1, deltaY: 1),
      'a keystroke': const KeyEvent(
        hidUsage: HidKey.keyA,
        pressed: true,
        modifiers: Modifiers.none,
      ),
      'typed text': const TextInput('hello'),
      'a media command': const MediaCommand(action: MediaAction.playPause),
      'a volume change': const VolumeCommand(
        mode: VolumeMode.absolute,
        value: 0.5,
      ),
      'a message about our screen': const ScreenStreamStop(),
      'a rename': const DeviceRename('not yours to set'),
      'a demand for more permission': const PermissionRequest(
        tier: PermissionTier.extended,
      ),
    };

    for (final entry in allowed.entries) {
      test('${entry.key} is acted on', () {
        expect(isAllowedFromPeer(entry.value), isTrue);
      });
    }

    for (final entry in refused.entries) {
      test('${entry.key} is ignored', () {
        expect(isAllowedFromPeer(entry.value), isFalse);
      });
    }
  });

  group('what this phone tells the network about itself', () {
    test('advertises what it can host, not what it can drive', () async {
      final host = await _startHost(name: 'Test Phone');
      addTearDown(host.service.dispose);

      final beacon = host.service.describeBeacon();

      expect(beacon.name, 'Test Phone');
      expect(beacon.capabilities.has(Capabilities.fileTransfer), isTrue);
      expect(beacon.capabilities.has(Capabilities.clipboardText), isTrue);

      // The bits that would be a lie. As a client this phone advertises
      // `mouse` to mean "I can send pointer events"; hosting the same bit
      // would offer a computer a phone it can drive, and there is nothing on
      // the other end of that.
      expect(beacon.capabilities.has(Capabilities.mouse), isFalse);
      expect(beacon.capabilities.has(Capabilities.keyboard), isFalse);
      expect(beacon.capabilities.has(Capabilities.screenCapture), isFalse);
      expect(kMobileCapabilities.has(Capabilities.mouse), isTrue);
    });

    test('a rename reaches the next announcement', () async {
      var name = 'Old Name';
      final host = await _startHost(name: 'ignored', nameSource: () => name);
      addTearDown(host.service.dispose);

      name = 'New Name';
      expect(host.service.describeBeacon().name, 'New Name');
    });
  });

  group('a device that has never paired', () {
    test('waits at the door instead of being let in', () async {
      final host = await _startHost();
      addTearDown(host.service.dispose);

      final pendingFirst = host.service.pendingChanges.firstWhere(
        (pending) => pending.isNotEmpty,
      );

      final stranger = await _dial(host);
      addTearDown(stranger.client.dispose);

      final pending = await pendingFirst.timeout(const Duration(seconds: 10));

      expect(pending, hasLength(1));
      expect(pending.single.shortAuthenticationString, hasLength(6));
      // Nothing is connected yet. A pending device that showed up in the link
      // list would be offered as somewhere to send to, which is exactly the
      // device the user has not agreed to yet.
      expect(host.service.links, isEmpty);
      // And nothing has been written down.
      expect(await host.trustStore.activePeers(), isEmpty);
    });

    test('is turned away without a prompt when we are not accepting', () async {
      final host = await _startHost();
      addTearDown(host.service.dispose);
      host.service.acceptsNewPairings = false;

      final stranger = await _dial(host);
      addTearDown(stranger.client.dispose);

      // Long enough for a prompt to have appeared if one were going to. The
      // wait is on this side's own state rather than on the far end noticing,
      // so it does not depend on how fast a socket closes.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(host.service.pending, isEmpty);
      expect(host.service.links, isEmpty);
    });

    test('approving writes a peer built from the handshake, not its claims',
        () async {
      var trustChanges = 0;
      final host = await _startHost(onTrustChanged: () async => trustChanges++);
      addTearDown(host.service.dispose);

      final pendingFirst = host.service.pendingChanges.firstWhere(
        (pending) => pending.isNotEmpty,
      );
      final stranger = await _dial(host);
      addTearDown(stranger.client.dispose);
      final request = (await pendingFirst.timeout(
        const Duration(seconds: 10),
      ))
          .single;

      await host.service.approvePairing(request);

      final peers = await host.trustStore.activePeers();
      expect(peers, hasLength(1));
      // The key on record is the one the handshake proved, so a device cannot
      // register a key it does not hold by asking nicely.
      expect(peers.single.publicKey, stranger.identity.publicKey);
      expect(peers.single.id, stranger.identity.id);
      expect(trustChanges, 1);
      expect(host.service.pending, isEmpty);
      expect(host.service.links.single.peerId, stranger.identity.id);
    });

    test('declining leaves no record and no link', () async {
      var trustChanges = 0;
      final host = await _startHost(onTrustChanged: () async => trustChanges++);
      addTearDown(host.service.dispose);

      final pendingFirst = host.service.pendingChanges.firstWhere(
        (pending) => pending.isNotEmpty,
      );
      final stranger = await _dial(host);
      addTearDown(stranger.client.dispose);
      final request = (await pendingFirst.timeout(
        const Duration(seconds: 10),
      ))
          .single;

      await host.service.declinePairing(request);

      expect(await host.trustStore.activePeers(), isEmpty);
      expect(host.service.links, isEmpty);
      expect(host.service.pending, isEmpty);
      expect(trustChanges, 0);
    });
  });

  group('a device that has paired', () {
    test('is let in, and its transfers arrive; its keystrokes do not',
        () async {
      final peer = await DeviceIdentity.generate();
      final host = await _startHost();
      addTearDown(host.service.dispose);
      await host.trustStore.upsert(
        TrustedPeer(
          id: peer.id,
          publicKey: peer.publicKey,
          name: 'A Known Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.standard.wireValue,
        ),
      );

      final linked = host.service.linkChanges.firstWhere(
        (links) => links.isNotEmpty,
      );
      final known = await _dial(host, identity: peer);
      addTearDown(known.client.dispose);
      await linked.timeout(const Duration(seconds: 10));
      // The host seeing a link and the client being ready to send are two
      // different moments: the server finishes the handshake first, and a send
      // issued in the gap goes nowhere with nothing raised.
      await _until(() => known.client.isConnected);

      final delivered = <Message>[];
      final subscription = host.service.messages.listen(
        (inbound) => delivered.add(inbound.message),
      );
      addTearDown(subscription.cancel);

      await known.client.send(
        FileOffer(transferId: 't-1', files: const <OfferedFile>[]),
      );
      await known.client.send(const MouseMove(deltaX: 10, deltaY: 10));
      await known.client.send(
        const KeyEvent(
            hidUsage: HidKey.keyA, pressed: true, modifiers: Modifiers.none),
      );
      await known.client.send(
        FileOffer(transferId: 't-2', files: const <OfferedFile>[]),
      );

      // Both offers, in order, and nothing between them. Waiting for the
      // second is what makes the absence of the two in between meaningful:
      // they were sent first and had every chance to arrive.
      await _until(() => delivered.length >= 2);

      expect(delivered, everyElement(isA<FileOffer>()));
      expect(
        delivered.map((m) => (m as FileOffer).transferId),
        <String>['t-1', 't-2'],
      );
    });
  });

  group('a paired device asking to connect now', () {
    test('is asked about by default', () async {
      // The default is the feature. A phone is handed around, left on a table
      // and carried into range of people its owner paired with once, and a
      // setting nobody finds protects nobody.
      final host = await _startHost(asksBeforeConnecting: true);
      addTearDown(host.service.dispose);
      expect(host.service.asksBeforeConnecting, isTrue);
    });

    test('waits, and what it sends while waiting is dropped', () async {
      final peer = await DeviceIdentity.generate();
      final host = await _startHost(asksBeforeConnecting: true);
      addTearDown(host.service.dispose);
      await _trust(host, peer);

      final waiting = host.service.pendingConnectionChanges.firstWhere(
        (pending) => pending.isNotEmpty,
      );
      final known = await _dial(host, identity: peer);
      addTearDown(known.client.dispose);

      final pending =
          (await waiting.timeout(const Duration(seconds: 10))).single;
      expect(pending.peerId, peer.id);
      // The stored name, not one the connecting device sent with this
      // connection.
      expect(pending.peerName, 'A Known Phone');

      // Not a link yet: a device in this state must not be offered as
      // somewhere to send to.
      expect(host.service.links, isEmpty);

      final delivered = <Message>[];
      final subscription = host.service.messages.listen(
        (inbound) => delivered.add(inbound.message),
      );
      addTearDown(subscription.cancel);

      await _until(() => known.client.session != null);
      await known.client.send(
        FileOffer(transferId: 'held', files: const <OfferedFile>[]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(delivered, isEmpty);

      await host.service.approveConnection(pending);
      await known.client.send(
        FileOffer(transferId: 'allowed', files: const <OfferedFile>[]),
      );
      await _until(() => delivered.isNotEmpty);
      expect((delivered.single as FileOffer).transferId, 'allowed');
      expect(host.service.links.single.peerId, peer.id);
    });

    test('is not asked about twice in one run of the app', () async {
      // A phone's link drops every time the screen locks. A prompt on each of
      // those would be tapped away without being read, which is worse than not
      // asking at all.
      final peer = await DeviceIdentity.generate();
      final host = await _startHost(asksBeforeConnecting: true);
      addTearDown(host.service.dispose);
      await _trust(host, peer);

      final waiting = host.service.pendingConnectionChanges.firstWhere(
        (pending) => pending.isNotEmpty,
      );
      final first = await _dial(host, identity: peer);
      await host.service.approveConnection(
        (await waiting.timeout(const Duration(seconds: 10))).single,
      );
      // Connected, not merely admitted. The host finishes first, and a client
      // disposed in the gap never had a session to close — the socket would
      // stay open and this test would be waiting on a link that cannot go.
      await _until(() => first.client.isConnected);
      await first.client.dispose();
      await _until(() => host.service.links.isEmpty);

      final second = await _dial(host, identity: peer);
      addTearDown(second.client.dispose);

      await _until(() => host.service.links.isNotEmpty);
      expect(host.service.pendingConnections, isEmpty);
    });

    test('turning it away leaves no link and tells it so', () async {
      final peer = await DeviceIdentity.generate();
      final host = await _startHost(asksBeforeConnecting: true);
      addTearDown(host.service.dispose);
      await _trust(host, peer);

      final waiting = host.service.pendingConnectionChanges.firstWhere(
        (pending) => pending.isNotEmpty,
      );
      final known = await _dial(host, identity: peer);
      addTearDown(known.client.dispose);
      final pending =
          (await waiting.timeout(const Duration(seconds: 10))).single;

      await host.service.declineConnection(pending);
      await _until(() => known.client.refusal != null);

      expect(known.client.refusal, ConnectionAnswer.declined);
      expect(host.service.links, isEmpty);
      expect(host.service.pendingConnections, isEmpty);
      // Still paired. Refusing a connection is not the same as forgetting a
      // device, and conflating them would make "not now" unrecoverable.
      expect(await host.trustStore.activePeers(), hasLength(1));
    });
  });

  group('remembering a device', () {
    test('a remembered device is let straight in, with nobody asked', () async {
      final peer = await DeviceIdentity.generate();
      final host = await _startHost(asksBeforeConnecting: true);
      addTearDown(host.service.dispose);
      await _trust(host, peer, autoAdmit: true, rememberAsked: true);

      final known = await _dial(host, identity: peer);
      addTearDown(known.client.dispose);

      await _until(() => host.service.links.isNotEmpty);
      expect(host.service.pendingConnections, isEmpty);
      expect(host.service.links.single.peerId, peer.id);
    });

    test('two yeses are what make a device remembered', () async {
      final peer = await DeviceIdentity.generate();
      final host = await _startHost();
      addTearDown(host.service.dispose);
      await _trust(host, peer);

      final asked = host.service.rememberChanges.firstWhere(
        (pending) => pending.isNotEmpty,
      );
      final known = await _dial(host, identity: peer);
      addTearDown(known.client.dispose);

      final pending = (await asked.timeout(const Duration(seconds: 10))).single;
      expect(pending.peerName, 'A Known Phone');

      // The peer's answer alone changes nothing: this phone has not agreed.
      await _until(() => known.client.session != null);
      await known.client.send(const RememberConnection(agreed: true));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect((await host.trustStore.findById(peer.id))?.autoAdmit, isFalse);

      await host.service.answerRemember(pending, agreed: true);
      await _untilStored(host, peer.id, (stored) => stored?.autoAdmit ?? false);
      expect(host.service.pendingRemembers, isEmpty);
    });

    test('a no is asked once and then left alone', () async {
      final peer = await DeviceIdentity.generate();
      final host = await _startHost();
      addTearDown(host.service.dispose);
      await _trust(host, peer);

      final asked = host.service.rememberChanges.firstWhere(
        (pending) => pending.isNotEmpty,
      );
      final known = await _dial(host, identity: peer);
      addTearDown(known.client.dispose);
      final pending = (await asked.timeout(const Duration(seconds: 10))).single;

      await _until(() => known.client.session != null);
      await known.client.send(const RememberConnection(agreed: true));
      await host.service.answerRemember(pending, agreed: false);

      await _untilStored(
        host,
        peer.id,
        (stored) => stored?.rememberAsked ?? false,
      );
      expect((await host.trustStore.findById(peer.id))?.autoAdmit, isFalse);
      expect(host.service.pendingRemembers, isEmpty);
    });
  });
}

/// A running host, and the pieces a test needs to reach into it.
typedef _Host = ({
  PhoneHostService service,
  TrustStore trustStore,
  DeviceIdentity identity,
  int port,
});

/// Starts a host on an ephemeral port with no advertising.
///
/// Both advertisers are replaced rather than left to fail on their own. Bonjour
/// needs a platform plugin that does not exist in a widget test, and the UDP
/// beacon would bind a multicast socket — a test that joined a multicast group
/// would be a test that behaves differently depending on what else is on the
/// network.
/// [asksBeforeConnecting] is off unless a test says otherwise, which is the
/// opposite of the app's own default. A test about what a paired device may do
/// once it is in should not also be a test about being let in — left on, every
/// one of them would assert against a session the transport is holding, and the
/// first failure would look like a bug in the thing under test. Being let in
/// has its own group below.
Future<_Host> _startHost({
  String name = 'Test Phone',
  String Function()? nameSource,
  Future<void> Function()? onTrustChanged,
  bool asksBeforeConnecting = false,
}) async {
  final identity = await DeviceIdentity.generate();
  final trustStore = InMemoryTrustStore();

  final service = PhoneHostService(
    identity: identity,
    trustStore: trustStore,
    clock: SystemClock(),
    describeName: nameSource ?? () => name,
    onTrustChanged: onTrustChanged ?? () async {},
    advertiser: const InertAdvertiser(),
    // Port 0 so nothing collides with a suite running beside this one, and so
    // no test can accidentally depend on the real one.
    port: 0,
  )..asksBeforeConnecting = asksBeforeConnecting;
  await service.start();

  return (
    service: service,
    trustStore: trustStore,
    identity: identity,
    port: service.boundPort,
  );
}

/// Records [identity] as a device this host has already paired with.
Future<void> _trust(
  _Host host,
  DeviceIdentity identity, {
  bool autoAdmit = false,
  bool rememberAsked = false,
}) =>
    host.trustStore.upsert(
      TrustedPeer(
        id: identity.id,
        publicKey: identity.publicKey,
        name: 'A Known Phone',
        platform: PlatformKind.android,
        pairedAt: DateTime.now(),
        permissionTier: PermissionTier.standard.wireValue,
        autoAdmit: autoAdmit,
        rememberAsked: rememberAsked,
      ),
    );

/// A device connecting to the host under test.
typedef _Caller = ({RemoteLinkClient client, DeviceIdentity identity});

Future<_Caller> _dial(_Host host, {DeviceIdentity? identity}) async {
  final caller = identity ?? await DeviceIdentity.generate();
  final client = RemoteLinkClient(
    identity: caller,
    capabilities: kMobileCapabilities,
    clock: SystemClock(),
  );
  unawaited(
    client.connect(
      ConnectionTarget(
        host: '127.0.0.1',
        port: host.port,
        serverPublicKey: host.identity.publicKey,
      ),
    ),
  );
  return (client: client, identity: caller);
}

/// Waits for a condition rather than for a duration.
///
/// A `delayed` long enough to be reliable is a suite that takes minutes, and
/// one short enough to be quick is a suite that fails on a loaded machine.
/// The same, for a condition that has to be read out of the trust store.
Future<void> _untilStored(
  _Host host,
  DeviceId peerId,
  bool Function(TrustedPeer?) condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition(await host.trustStore.findById(peerId))) {
    if (DateTime.now().isAfter(deadline)) {
      fail('the trust store never reached the expected state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was still false after $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
