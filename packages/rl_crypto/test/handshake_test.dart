import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

const Capabilities _caps = Capabilities(
  Capabilities.mouse | Capabilities.keyboard | Capabilities.clipboardText,
);

/// Drives both halves of a handshake to completion in memory.
///
/// No sockets: the handshake is defined purely in terms of message objects and
/// byte blobs, which is exactly what makes an adversarial test like the
/// machine-in-the-middle case below possible at all.
Future<(HandshakeResult, HandshakeResult)> _run({
  required DeviceIdentity client,
  required DeviceIdentity server,
  Uint8List? expectedServerKey,
  PeerLookup? lookupPeer,
}) async {
  final clientSide = ClientHandshake(
    identity: client,
    capabilities: _caps,
    expectedServerKey: expectedServerKey,
  );
  final serverSide = ServerHandshake(
    identity: server,
    capabilities: _caps,
    lookupPeer: lookupPeer ?? (_) async => null,
  );

  final hello = await clientSide.createHello();
  final (serverHello, sealedStatic) = await serverSide.receiveClientHello(hello);
  await clientSide.receiveServerHello(serverHello);
  await clientSide.receiveServerStatic(sealedStatic);
  final clientFinish = await clientSide.createClientFinish();
  final (sealedConfirm, serverResult) =
      await serverSide.receiveClientFinish(clientFinish);
  final clientResult = await clientSide.receiveServerConfirm(sealedConfirm);

  return (clientResult, serverResult);
}

void main() {
  late DeviceIdentity phone;
  late DeviceIdentity desktop;

  setUp(() async {
    phone = await DeviceIdentity.generate();
    desktop = await DeviceIdentity.generate();
  });

  group('identity', () {
    test('device id is derived deterministically from the public key', () async {
      final privateKey = await phone.extractPrivateKey();
      final restored = await DeviceIdentity.fromPrivateKey(privateKey);
      expect(restored.id, phone.id);
      expect(restored.publicKey, phone.publicKey);
    });

    test('separate identities differ', () {
      expect(phone.id, isNot(desktop.id));
    });

    test('a wrong-length seed is rejected rather than silently rekeying', () {
      // Silently producing a different identity here would look to the user
      // like every paired device had forgotten them.
      expect(
        () => DeviceIdentity.fromPrivateKey(Uint8List(16)),
        throwsA(isA<SecurityError>()),
      );
    });
  });

  group('successful handshake', () {
    test('both sides agree on keys, identities, and the SAS', () async {
      final (clientResult, serverResult) =
          await _run(client: phone, server: desktop);

      expect(clientResult.peerId, desktop.id);
      expect(serverResult.peerId, phone.id);
      expect(clientResult.peerStaticPublicKey, desktop.publicKey);
      expect(serverResult.peerStaticPublicKey, phone.publicKey);
      expect(
        clientResult.shortAuthenticationString,
        serverResult.shortAuthenticationString,
      );
      expect(clientResult.shortAuthenticationString, hasLength(6));
      expect(
        int.tryParse(clientResult.shortAuthenticationString),
        isNotNull,
        reason: 'SAS must be six digits the user can read aloud',
      );
    });

    test('capabilities are intersected, not merely copied', () async {
      final clientSide = ClientHandshake(
        identity: phone,
        capabilities: const Capabilities(
          Capabilities.mouse | Capabilities.screenCapture,
        ),
      );
      final serverSide = ServerHandshake(
        identity: desktop,
        capabilities: const Capabilities(
          Capabilities.mouse | Capabilities.fileTransfer,
        ),
        lookupPeer: (_) async => null,
      );

      final hello = await clientSide.createHello();
      final (serverHello, sealedStatic) =
          await serverSide.receiveClientHello(hello);
      await clientSide.receiveServerHello(serverHello);
      await clientSide.receiveServerStatic(sealedStatic);
      final finish = await clientSide.createClientFinish();
      final (confirm, _) = await serverSide.receiveClientFinish(finish);
      final result = await clientSide.receiveServerConfirm(confirm);

      expect(result.capabilities.has(Capabilities.mouse), isTrue);
      expect(result.capabilities.has(Capabilities.screenCapture), isFalse);
      expect(result.capabilities.has(Capabilities.fileTransfer), isFalse);
    });

    test('derived session keys interoperate in both directions', () async {
      final (clientResult, serverResult) =
          await _run(client: phone, server: desktop);

      final plaintext = Uint8List.fromList('mouse move 3 -5'.codeUnits);
      final aad = Uint8List.fromList(<int>[1, 2, 3, 4]);

      final phoneToDesktop =
          await clientResult.keys.send.seal(plaintext, aad: aad);
      final received = await serverResult.keys.receive.open(
        phoneToDesktop,
        counter: 0,
        aad: aad,
      );
      expect(received, plaintext);

      final desktopToPhone =
          await serverResult.keys.send.seal(plaintext, aad: aad);
      final echoed = await clientResult.keys.receive.open(
        desktopToPhone,
        counter: 0,
        aad: aad,
      );
      expect(echoed, plaintext);
    });

    test('static keys never appear in the plaintext hello messages', () async {
      // A passive observer must not be able to fingerprint which devices are
      // talking, only that someone is.
      final clientSide = ClientHandshake(identity: phone, capabilities: _caps);
      final serverSide = ServerHandshake(
        identity: desktop,
        capabilities: _caps,
        lookupPeer: (_) async => null,
      );

      final hello = await clientSide.createHello();
      final (serverHello, _) = await serverSide.receiveClientHello(hello);

      expect(
        _contains(hello.encodePayload(), phone.publicKey),
        isFalse,
        reason: 'client hello leaked the static key',
      );
      expect(
        _contains(serverHello.encodePayload(), desktop.publicKey),
        isFalse,
        reason: 'server hello leaked the static key',
      );
    });

    test('two runs of the same pair derive different keys', () async {
      // Forward secrecy: recovering both long-term keys later must not decrypt
      // a recorded session, which requires fresh ephemerals every time.
      final (first, _) = await _run(client: phone, server: desktop);
      final (second, _) = await _run(client: phone, server: desktop);

      expect(
        first.shortAuthenticationString,
        isNot(second.shortAuthenticationString),
      );
    });
  });

  group('trust', () {
    test('a known peer completes without requiring pairing', () async {
      final trusted = TrustedPeer(
        id: phone.id,
        publicKey: phone.publicKey,
        name: 'Phone',
        platform: PlatformKind.android,
        pairedAt: DateTime.utc(2026),
        permissionTier: 2,
      );

      final (clientResult, serverResult) = await _run(
        client: phone,
        server: desktop,
        expectedServerKey: desktop.publicKey,
        lookupPeer: (key) async =>
            Primitives.constantTimeEquals(key, phone.publicKey)
                ? trusted
                : null,
      );

      expect(clientResult.requiresPairing, isFalse);
      expect(clientResult.peerWasKnown, isTrue);
      expect(serverResult.requiresPairing, isFalse);
      expect(serverResult.peerWasKnown, isTrue);
    });

    test('an unknown peer is flagged as needing pairing', () async {
      final (clientResult, serverResult) =
          await _run(client: phone, server: desktop);
      expect(clientResult.requiresPairing, isTrue);
      expect(serverResult.requiresPairing, isTrue);
    });

    test('a revoked peer is refused outright', () async {
      final revoked = TrustedPeer(
        id: phone.id,
        publicKey: phone.publicKey,
        name: 'Phone',
        platform: PlatformKind.android,
        pairedAt: DateTime.utc(2026),
        permissionTier: 2,
        revoked: true,
      );

      await expectLater(
        _run(
          client: phone,
          server: desktop,
          lookupPeer: (_) async => revoked,
        ),
        throwsA(
          isA<SecurityError>()
              .having((e) => e.code, 'code', 'security.peer_revoked'),
        ),
      );
    });

    test('a substituted server key is rejected, not re-paired', () async {
      // The attack this blocks: someone takes over the desktop's address and
      // hopes the user will tap through a "pair again?" dialog.
      final impostor = await DeviceIdentity.generate();

      await expectLater(
        _run(
          client: phone,
          server: impostor,
          expectedServerKey: desktop.publicKey,
        ),
        throwsA(
          isA<SecurityError>()
              .having((e) => e.code, 'code', 'security.server_key_mismatch'),
        ),
      );
    });
  });

  group('machine-in-the-middle', () {
    test('a relaying attacker produces mismatched SAS on the two screens',
        () async {
      // This is the property the whole pairing flow rests on. The attacker runs
      // two perfectly valid handshakes — nothing fails cryptographically — but
      // cannot make both transcripts hash to the same six digits, so the user
      // sees different numbers and declines.
      final attacker = await DeviceIdentity.generate();

      final (phoneSide, _) = await _run(client: phone, server: attacker);
      final (_, desktopSide) = await _run(client: attacker, server: desktop);

      expect(
        phoneSide.shortAuthenticationString,
        isNot(desktopSide.shortAuthenticationString),
        reason: 'a relay must not be able to match both SAS values',
      );
    });

    test('tampering with the server hello breaks the handshake', () async {
      final clientSide = ClientHandshake(identity: phone, capabilities: _caps);
      final serverSide = ServerHandshake(
        identity: desktop,
        capabilities: _caps,
        lookupPeer: (_) async => null,
      );

      final hello = await clientSide.createHello();
      final (serverHello, sealedStatic) =
          await serverSide.receiveClientHello(hello);

      // Swap in a different ephemeral key, as an active attacker would.
      final tampered = ServerHello(
        selectedVersion: serverHello.selectedVersion,
        serverId: serverHello.serverId,
        ephemeralPublicKey: Uint8List.fromList(List<int>.filled(32, 9)),
        serverNonce: serverHello.serverNonce,
        capabilities: serverHello.capabilities,
        requiresPairing: serverHello.requiresPairing,
      );

      await clientSide.receiveServerHello(tampered);
      await expectLater(
        clientSide.receiveServerStatic(sealedStatic),
        throwsA(isA<SecurityError>()),
      );
    });

    test('a flipped bit in the sealed static key fails authentication',
        () async {
      final clientSide = ClientHandshake(identity: phone, capabilities: _caps);
      final serverSide = ServerHandshake(
        identity: desktop,
        capabilities: _caps,
        lookupPeer: (_) async => null,
      );

      final hello = await clientSide.createHello();
      final (serverHello, sealedStatic) =
          await serverSide.receiveClientHello(hello);
      await clientSide.receiveServerHello(serverHello);

      sealedStatic[3] ^= 0x01;

      await expectLater(
        clientSide.receiveServerStatic(sealedStatic),
        throwsA(
          isA<SecurityError>().having(
            (e) => e.code,
            'code',
            'security.authentication_failed',
          ),
        ),
      );
    });

    test('a forged client confirmation is rejected', () async {
      final clientSide = ClientHandshake(identity: phone, capabilities: _caps);
      final serverSide = ServerHandshake(
        identity: desktop,
        capabilities: _caps,
        lookupPeer: (_) async => null,
      );

      final hello = await clientSide.createHello();
      final (serverHello, sealedStatic) =
          await serverSide.receiveClientHello(hello);
      await clientSide.receiveServerHello(serverHello);
      await clientSide.receiveServerStatic(sealedStatic);

      final finish = await clientSide.createClientFinish();
      finish[finish.length - 5] ^= 0xFF;

      await expectLater(
        serverSide.receiveClientFinish(finish),
        throwsA(isA<SecurityError>()),
      );
    });
  });

  group('version negotiation', () {
    test('no overlapping version range is a clean failure', () async {
      final serverSide = ServerHandshake(
        identity: desktop,
        capabilities: _caps,
        lookupPeer: (_) async => null,
      );

      final incompatible = ClientHello(
        minVersion: 99,
        maxVersion: 99,
        ephemeralPublicKey: Uint8List(32),
        clientNonce: Uint8List(32),
        capabilities: _caps,
      );

      await expectLater(
        serverSide.receiveClientHello(incompatible),
        throwsA(
          isA<SecurityError>()
              .having((e) => e.code, 'code', 'security.version_mismatch'),
        ),
      );
    });

    test('connecting to the wrong server is caught before key agreement',
        () async {
      final serverSide = ServerHandshake(
        identity: desktop,
        capabilities: _caps,
        lookupPeer: (_) async => null,
      );

      final misdirected = ClientHello(
        minVersion: kMinSupportedProtocolVersion,
        maxVersion: kProtocolVersion,
        ephemeralPublicKey: Uint8List(32),
        clientNonce: Uint8List(32),
        capabilities: _caps,
        knownServerId: phone.id,
      );

      await expectLater(
        serverSide.receiveClientHello(misdirected),
        throwsA(
          isA<SecurityError>()
              .having((e) => e.code, 'code', 'security.wrong_server'),
        ),
      );
    });
  });

  group('handshake object lifecycle', () {
    test('a completed handshake cannot be reused', () async {
      final clientSide = ClientHandshake(identity: phone, capabilities: _caps);
      final serverSide = ServerHandshake(
        identity: desktop,
        capabilities: _caps,
        lookupPeer: (_) async => null,
      );

      final hello = await clientSide.createHello();
      final (serverHello, sealedStatic) =
          await serverSide.receiveClientHello(hello);
      await clientSide.receiveServerHello(serverHello);
      await clientSide.receiveServerStatic(sealedStatic);
      final finish = await clientSide.createClientFinish();
      final (confirm, _) = await serverSide.receiveClientFinish(finish);
      await clientSide.receiveServerConfirm(confirm);

      expect(clientSide.isComplete, isTrue);
      await expectLater(
        clientSide.createHello(),
        throwsA(
          isA<SecurityError>()
              .having((e) => e.code, 'code', 'security.handshake_reused'),
        ),
      );
    });
  });
}

/// Whether [haystack] contains [needle] as a contiguous run.
bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
