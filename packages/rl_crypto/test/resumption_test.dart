import 'dart:async';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:test/test.dart';

void main() {
  Future<(Uint8List, Uint8List, Uint8List)> request(
      Uint8List ticket, Uint8List secret) async {
    final nonce = Uint8List(32)..[0] = 7;
    final proof =
        await Primitives.mac(key: secret, data: <int>[...ticket, ...nonce]);
    return (ticket, nonce, proof);
  }

  test('one ticket is accepted once; tampering and another server key fail',
      () async {
    final clock = FakeClock();
    final server = ResumptionTickets(clock: clock);
    final otherServer = ResumptionTickets(clock: clock);
    final key = Uint8List(32)..[0] = 4;
    final secret = Uint8List(32)..[0] = 8;
    final ticket = await server.issue(peerKey: key, tier: 2, secret: secret);
    final (bytes, nonce, proof) = await request(ticket, secret);
    Future<bool> trusted(Uint8List peer, int tier) async =>
        tier == 2 && Primitives.constantTimeEquals(peer, key);
    expect(await otherServer.open(bytes, nonce, proof, trusted), isNull);
    final tampered = Uint8List.fromList(ticket)..[30] ^= 1;
    expect(await server.open(tampered, nonce, proof, trusted), isNull);
    expect(await server.open(bytes, nonce, proof, trusted), isNotNull);
    expect(await server.open(bytes, nonce, proof, trusted), isNull);
  });

  test('concurrent presentation admits only one socket', () async {
    final server = ResumptionTickets(clock: FakeClock());
    final key = Uint8List(32);
    final secret = Uint8List(32);
    final ticket = await server.issue(peerKey: key, tier: 2, secret: secret);
    final (_, nonce, proof) = await request(ticket, secret);
    final bothLookupsStarted = Completer<void>();
    var lookups = 0;
    Future<bool> trusted(Uint8List _, int __) async {
      lookups++;
      if (lookups == 2) bothLookupsStarted.complete();
      await bothLookupsStarted.future;
      return true;
    }

    final attempts = await Future.wait(<Future<OpenedTicket?>>[
      server.open(ticket, nonce, proof, trusted),
      server.open(ticket, nonce, proof, trusted),
    ]);
    expect(attempts.where((result) => result != null).length, 1);
  });

  test('expiry, rotation and revocation reject without consuming', () async {
    final clock = FakeClock();
    final server = ResumptionTickets(clock: clock);
    final key = Uint8List(32);
    final secret = Uint8List(32);
    final ticket = await server.issue(peerKey: key, tier: 2, secret: secret);
    final (_, nonce, proof) = await request(ticket, secret);
    expect(await server.open(ticket, nonce, proof, (_, __) async => false),
        isNull);
    clock.advance(const Duration(hours: 1));
    expect(await server.open(ticket, nonce, proof, (_, __) async => true),
        isNotNull);
    final next = await server.issue(peerKey: key, tier: 2, secret: secret);
    final (_, nonce2, proof2) = await request(next, secret);
    clock.advance(const Duration(hours: 25));
    expect(
        await server.open(next, nonce2, proof2, (_, __) async => true), isNull);
  });

  test('resume keys agree, differ from old keys, and require ephemeral secret',
      () async {
    final secret = Uint8List(32)..[0] = 11;
    final client = await Primitives.generateKeyPair();
    final server = await Primitives.generateKeyPair();
    final cp = Uint8List.fromList((await client.extractPublicKey()).bytes);
    final sp = Uint8List.fromList((await server.extractPublicKey()).bytes);
    final salt = await ResumeKeys.transcript(
        Uint8List(125), Uint8List(32), cp, sp, Uint8List(8));
    final cShared =
        await Primitives.sharedSecret(keyPair: client, remotePublicKey: sp);
    final sShared =
        await Primitives.sharedSecret(keyPair: server, remotePublicKey: cp);
    final c = await ResumeKeys.derive(
        secret: secret, shared: cShared, transcript: salt, client: true);
    final s = await ResumeKeys.derive(
        secret: secret, shared: sShared, transcript: salt, client: false);
    final sealed = await c.send.seal(<int>[1, 2, 3]);
    expect(await s.receive.open(sealed, counter: 0), <int>[1, 2, 3]);
    final guessed = await ResumeKeys.derive(
        secret: secret, shared: Uint8List(32), transcript: salt, client: false);
    expect(() => guessed.receive.open(sealed, counter: 0),
        throwsA(isA<SecurityError>()));
    expect(c.resumptionSecret, isNot(secret));
  });
}
