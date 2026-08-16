import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:test/test.dart';

/// The trust store decides whether a connecting device is asked to pair or
/// waved straight through, so its lookups are a security control rather than a
/// convenience. It had no tests at all.
void main() {
  /// Builds a peer whose public key is deterministic but distinct per [seed].
  TrustedPeer peerWith(int seed, {bool revoked = false, String? name}) {
    final key = Uint8List(32)..fillRange(0, 32, seed);
    return TrustedPeer(
      id: DeviceId('device-$seed'),
      publicKey: key,
      name: name ?? 'Device $seed',
      platform: PlatformKind.android,
      pairedAt: DateTime.utc(2026),
      permissionTier: 2,
      revoked: revoked,
    );
  }

  group('InMemoryTrustStore', () {
    late InMemoryTrustStore store;

    setUp(() => store = InMemoryTrustStore());
    tearDown(() => store.dispose());

    test('a peer that was never added is unknown by id and by key', () async {
      expect(await store.findById(const DeviceId('nobody')), isNull);
      expect(await store.findByPublicKey(Uint8List(32)), isNull);
    });

    test('upsert stores a peer findable by id and by public key', () async {
      final peer = peerWith(1);
      await store.upsert(peer);

      expect((await store.findById(peer.id))?.name, 'Device 1');
      expect((await store.findByPublicKey(peer.publicKey))?.id, peer.id);
    });

    test('upsert on an existing id replaces rather than duplicates', () async {
      await store.upsert(peerWith(1));
      await store.upsert(peerWith(1, name: 'Renamed'));

      final all = await store.listPeers();
      expect(all, hasLength(1));
      expect(all.single.name, 'Renamed');
    });

    test('lookup by key does not match a different key', () async {
      await store.upsert(peerWith(1));

      final otherKey = Uint8List(32)..fillRange(0, 32, 2);
      expect(await store.findByPublicKey(otherKey), isNull);
    });

    test('a key that shares a prefix but differs later does not match',
        () async {
      await store.upsert(peerWith(1));

      // The discovery beacon advertises only an 8-byte fingerprint, and
      // SECURITY.md is explicit that it must never be treated as a trust key.
      // A store that matched on a prefix would quietly make it one.
      final nearMiss = Uint8List(32)..fillRange(0, 32, 1);
      nearMiss[31] = 99;

      expect(await store.findByPublicKey(nearMiss), isNull);
    });

    group('revocation', () {
      test('revoke retains the record and marks it', () async {
        final peer = peerWith(1);
        await store.upsert(peer);
        await store.revoke(peer.id);

        final stored = await store.findById(peer.id);
        expect(
          stored,
          isNotNull,
          reason: 'a revoked peer is retained so a reconnect can be answered '
              'with a definitive "revoked" rather than an ambiguous "unknown", '
              'which would send the user into a pairing flow that then fails',
        );
        expect(stored!.revoked, isTrue);
      });

      test('a revoked peer is excluded from activePeers', () async {
        await store.upsert(peerWith(1));
        await store.upsert(peerWith(2));
        await store.revoke(const DeviceId('device-2'));

        final active = await store.activePeers();
        expect(active.map((p) => p.id.value), <String>['device-1']);
      });

      test('a revoked peer is still findable by key', () async {
        final peer = peerWith(1);
        await store.upsert(peer);
        await store.revoke(peer.id);

        final found = await store.findByPublicKey(peer.publicKey);
        expect(
          found?.revoked,
          isTrue,
          reason: 'the server looks a peer up by key during the handshake and '
              'must be able to see that it was revoked',
        );
      });

      test('revoking an unknown peer is a no-op, not an insertion', () async {
        await store.revoke(const DeviceId('never-seen'));
        expect(await store.listPeers(), isEmpty);
      });
    });

    group('forget', () {
      test('forget removes the record entirely', () async {
        final peer = peerWith(1);
        await store.upsert(peer);
        await store.forget(peer.id);

        expect(await store.findById(peer.id), isNull);
        expect(await store.findByPublicKey(peer.publicKey), isNull);
        expect(await store.listPeers(), isEmpty);
      });

      test('a forgotten peer reconnects as unknown, so pairing runs again',
          () async {
        final peer = peerWith(1);
        await store.upsert(peer);
        await store.forget(peer.id);

        // The distinction from revoke() is the whole point: forgetting means
        // "start over", revoking means "refuse".
        expect(await store.findByPublicKey(peer.publicKey), isNull);
      });
    });
  });
}
