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
Future<_Host> _startHost({
  String name = 'Test Phone',
  String Function()? nameSource,
  Future<void> Function()? onTrustChanged,
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
  );
  await service.start();

  return (
    service: service,
    trustStore: trustStore,
    identity: identity,
    port: service.boundPort,
  );
}

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
