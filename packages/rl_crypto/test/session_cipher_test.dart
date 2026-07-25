import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:test/test.dart';

Uint8List _key(int fill) => Uint8List.fromList(List<int>.filled(32, fill));

void main() {
  group('DirectionalCipher', () {
    test('seal then open round trips', () async {
      final sender = DirectionalCipher(key: _key(1), label: 'test');
      final receiver = DirectionalCipher(key: _key(1), label: 'test');

      final plaintext = Uint8List.fromList('hello desktop'.codeUnits);
      final sealed = await sender.seal(plaintext);
      expect(await receiver.open(sealed, counter: 0), plaintext);
    });

    test('the counter advances so no nonce is ever reused', () async {
      final sender = DirectionalCipher(key: _key(2), label: 'test');
      final receiver = DirectionalCipher(key: _key(2), label: 'test');

      final plaintext = Uint8List.fromList(<int>[1, 2, 3]);
      final first = await sender.seal(plaintext);
      final second = await sender.seal(plaintext);

      expect(sender.counter, 2);
      expect(
        first,
        isNot(second),
        reason: 'identical plaintexts must not produce identical ciphertexts',
      );
      expect(await receiver.open(first, counter: 0), plaintext);
      expect(await receiver.open(second, counter: 1), plaintext);
    });

    test('associated data is bound into the tag', () async {
      // This is what stops an attacker replaying a valid ciphertext under a
      // different frame header — a "left click" resent as a "right click".
      final sender = DirectionalCipher(key: _key(3), label: 'test');
      final receiver = DirectionalCipher(key: _key(3), label: 'test');

      final sealed = await sender.seal(
        Uint8List.fromList(<int>[9]),
        aad: Uint8List.fromList(<int>[0xAA]),
      );

      await expectLater(
        receiver.open(sealed, counter: 0, aad: Uint8List.fromList(<int>[0xBB])),
        throwsA(isA<SecurityError>()),
      );
    });

    test('a flipped bit in the ciphertext fails authentication', () async {
      final sender = DirectionalCipher(key: _key(4), label: 'test');
      final receiver = DirectionalCipher(key: _key(4), label: 'test');

      final sealed = await sender.seal(Uint8List.fromList(<int>[1, 2, 3, 4]));
      sealed[0] ^= 0x01;

      await expectLater(
        receiver.open(sealed, counter: 0),
        throwsA(
          isA<SecurityError>().having(
            (e) => e.code,
            'code',
            'security.authentication_failed',
          ),
        ),
      );
    });

    test('the wrong key fails without revealing why', () async {
      final sender = DirectionalCipher(key: _key(5), label: 'test');
      final receiver = DirectionalCipher(key: _key(6), label: 'test');

      final sealed = await sender.seal(Uint8List.fromList(<int>[1]));
      await expectLater(
        receiver.open(sealed, counter: 0),
        throwsA(
          isA<SecurityError>().having(
            (e) => e.code,
            'code',
            // Same code as a tampered frame: distinguishing them is an oracle.
            'security.authentication_failed',
          ),
        ),
      );
    });

    test('a truncated message is rejected before decryption', () async {
      final receiver = DirectionalCipher(key: _key(7), label: 'test');
      await expectLater(
        receiver.open(Uint8List(4), counter: 0),
        throwsA(
          isA<SecurityError>().having(
            (e) => e.code,
            'code',
            'security.ciphertext_too_short',
          ),
        ),
      );
    });
  });

  group('ReplayWindow', () {
    test('accepts strictly increasing sequences', () {
      final window = ReplayWindow();
      for (var i = 0; i < 100; i++) {
        expect(window.accept(i), isTrue);
      }
      expect(window.highest, 99);
    });

    test('rejects an exact replay', () {
      final window = ReplayWindow()..accept(5);
      expect(window.accept(5), isFalse);
    });

    test('accepts out-of-order arrivals inside the window', () {
      // Datagrams reorder; that is normal and must not be treated as an attack.
      final window = ReplayWindow()..accept(10);
      expect(window.accept(8), isTrue);
      expect(window.accept(9), isTrue);
      expect(window.accept(8), isFalse, reason: 'now a replay');
    });

    test('rejects sequences older than the window', () {
      final window = ReplayWindow(size: 64)..accept(200);
      expect(window.accept(200 - 64), isFalse);
      expect(window.accept(200 - 63), isTrue);
    });

    test('a large forward jump clears the window without wrapping', () {
      final window = ReplayWindow()
        ..accept(1)
        ..accept(2);
      expect(window.accept(1000), isTrue);
      expect(window.accept(2), isFalse, reason: 'far outside the window now');
      expect(window.accept(999), isTrue);
    });

    test('negative sequences are rejected', () {
      expect(ReplayWindow().accept(-1), isFalse);
    });
  });

  group('constantTimeEquals', () {
    test('compares content, not identity', () {
      expect(
        Primitives.constantTimeEquals(<int>[1, 2, 3], <int>[1, 2, 3]),
        isTrue,
      );
      expect(
        Primitives.constantTimeEquals(<int>[1, 2, 3], <int>[1, 2, 4]),
        isFalse,
      );
      expect(Primitives.constantTimeEquals(<int>[1], <int>[1, 2]), isFalse);
      expect(Primitives.constantTimeEquals(<int>[], <int>[]), isTrue);
    });
  });

  group('PairingPayload', () {
    test('round trips through its URI form', () {
      final payload = PairingPayload(
        deviceId: const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123'),
        publicKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
        name: "Ahmed's MacBook Pro",
        host: '192.168.1.42',
        port: 47811,
        token: Uint8List.fromList(<int>[9, 8, 7, 6]),
      );

      final parsed = PairingPayload.tryParse(payload.toUri());
      expect(parsed, isNotNull);
      expect(parsed!.deviceId, payload.deviceId);
      expect(parsed.publicKey, payload.publicKey);
      expect(parsed.name, payload.name);
      expect(parsed.host, payload.host);
      expect(parsed.port, payload.port);
      expect(parsed.token, payload.token);
    });

    test('rejects arbitrary scanned text without throwing', () {
      // The camera sees whatever is in front of it; a QR code on a cereal box
      // is not an exceptional condition.
      expect(PairingPayload.tryParse('https://example.com'), isNull);
      expect(PairingPayload.tryParse('not a uri at all'), isNull);
      expect(PairingPayload.tryParse(''), isNull);
      expect(PairingPayload.tryParse('remotelink://pair/SHORT?k=x'), isNull);
    });

    test('rejects a payload whose key is the wrong length', () {
      expect(
        PairingPayload.tryParse(
          'remotelink://pair/ABCDEFGHJKMNPQRSTVWXYZ0123'
          '?k=AAAA&h=1.2.3.4&p=1',
        ),
        isNull,
      );
    });

    test('rejects an out-of-range port', () {
      final valid = PairingPayload(
        deviceId: const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123'),
        publicKey: Uint8List(32),
        name: 'x',
        host: '1.2.3.4',
        port: 1,
        token: Uint8List(0),
      ).toUri();

      expect(
        PairingPayload.tryParse(valid.replaceFirst('p=1', 'p=70000')),
        isNull,
      );
    });
  });

  group('PairingRateLimiter', () {
    test('allows attempts up to the limit then locks out', () {
      final clock = FakeClock();
      final limiter = PairingRateLimiter(clock: clock, maxAttempts: 3);

      expect(limiter.isAllowed('peer'), isTrue);
      expect(limiter.attemptsRemaining('peer'), 3);

      limiter.recordFailure('peer');
      expect(limiter.attemptsRemaining('peer'), 2);
      expect(limiter.isAllowed('peer'), isTrue);

      limiter
        ..recordFailure('peer')
        ..recordFailure('peer');

      expect(limiter.isAllowed('peer'), isFalse);
      expect(limiter.attemptsRemaining('peer'), 0);
      expect(limiter.retryAfterSeconds('peer'), greaterThan(0));
    });

    test('the lockout expires', () {
      final clock = FakeClock();
      final limiter = PairingRateLimiter(clock: clock, maxAttempts: 1)
        ..recordFailure('peer');

      expect(limiter.isAllowed('peer'), isFalse);
      clock.advance(kPairingLockout + const Duration(seconds: 1));
      expect(limiter.isAllowed('peer'), isTrue);
    });

    test('success clears the failure history', () {
      final limiter = PairingRateLimiter(clock: FakeClock(), maxAttempts: 3)
        ..recordFailure('peer')
        ..recordFailure('peer')
        ..recordSuccess('peer');

      expect(limiter.attemptsRemaining('peer'), 3);
    });

    test('lockouts are per peer, not global', () {
      // Otherwise one hostile device on the network could lock the user out of
      // pairing their own phone.
      final limiter = PairingRateLimiter(clock: FakeClock(), maxAttempts: 1)
        ..recordFailure('attacker');

      expect(limiter.isAllowed('attacker'), isFalse);
      expect(limiter.isAllowed('my-phone'), isTrue);
    });
  });

  group('InMemoryTrustStore', () {
    test('finds a peer by public key', () async {
      final store = InMemoryTrustStore();
      addTearDown(store.dispose);

      final peer = TrustedPeer(
        id: const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123'),
        publicKey: Uint8List.fromList(List<int>.filled(32, 5)),
        name: 'Phone',
        platform: PlatformKind.android,
        pairedAt: DateTime.utc(2026),
        permissionTier: 2,
      );
      await store.upsert(peer);

      expect(await store.findByPublicKey(peer.publicKey), peer);
      expect(await store.findByPublicKey(Uint8List(32)), isNull);
      expect(await store.isTrusted(peer.publicKey), isTrue);
    });

    test('revoking keeps the record but withdraws trust', () async {
      // Keeping it means a reconnect gets a definitive "revoked" rather than
      // being routed back into a pairing flow that would then fail.
      final store = InMemoryTrustStore();
      addTearDown(store.dispose);

      const id = DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123');
      final key = Uint8List.fromList(List<int>.filled(32, 5));
      await store.upsert(
        TrustedPeer(
          id: id,
          publicKey: key,
          name: 'Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.utc(2026),
          permissionTier: 2,
        ),
      );

      await store.revoke(id);

      expect(await store.findById(id), isNotNull);
      expect((await store.findById(id))!.revoked, isTrue);
      expect(await store.isTrusted(key), isFalse);
      expect(await store.activePeers(), isEmpty);
    });

    test('forgetting removes the record entirely', () async {
      final store = InMemoryTrustStore();
      addTearDown(store.dispose);

      const id = DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123');
      await store.upsert(
        TrustedPeer(
          id: id,
          publicKey: Uint8List(32),
          name: 'Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.utc(2026),
          permissionTier: 2,
        ),
      );

      await store.forget(id);
      expect(await store.findById(id), isNull);
      expect(await store.listPeers(), isEmpty);
    });
  });
}
