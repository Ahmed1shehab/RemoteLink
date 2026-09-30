import 'dart:async';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';
import 'package:test/test.dart';

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('ticket did not arrive');
}

void main() {
  test(
      'full handshake issues ticket; resume uses one response and rotates ticket',
      () async {
    final desktop = await DeviceIdentity.generate();
    final phone = await DeviceIdentity.generate();
    final trust = InMemoryTrustStore();
    await trust.upsert(TrustedPeer(
      id: phone.id,
      publicKey: phone.publicKey,
      name: 'phone',
      platform: PlatformKind.android,
      pairedAt: DateTime.now(),
      permissionTier: PermissionTier.standard.wireValue,
    ));
    const clientCaps =
        Capabilities(Capabilities.mouse | Capabilities.sessionResumption);
    const serverCaps = Capabilities(Capabilities.mouse |
        Capabilities.keyboard |
        Capabilities.sessionResumption);
    var server = RemoteLinkServer(
        identity: desktop,
        capabilities: serverCaps,
        trustStore: trust,
        clock: SystemClock(),
        port: 0);
    await server.start();
    final client = RemoteLinkClient(
        identity: phone, capabilities: clientCaps, clock: SystemClock());
    var target = ConnectionTarget(
        host: '127.0.0.1',
        port: server.boundPort,
        deviceId: desktop.id,
        serverPublicKey: desktop.publicKey);
    try {
      final fullWatch = Stopwatch()..start();
      await client.connect(target);
      final first = await client.waitUntilConnected();
      fullWatch.stop();
      expect(first.wasResumed, isFalse);
      await _until(() => client.resumptionFor(desktop.publicKey) != null);
      final oldTicket = client.resumptionFor(desktop.publicKey)!.ticket;
      final oldExporter = first.exporterSecret;
      final oldSecret =
          Uint8List.fromList(client.resumptionFor(desktop.publicKey)!.secret);
      await client.disconnect();
      final watch = Stopwatch()..start();
      await client.connect(target);
      final resumed = await client.waitUntilConnected();
      watch.stop();
      expect(resumed.wasResumed, isTrue);
      expect(resumed.capabilities.bits, clientCaps.bits);
      expect(server.sessions.single.session.capabilities.bits, clientCaps.bits);
      expect(resumed.exporterSecret, isNot(equals(oldExporter)));
      expect(server.sessions.single.session.wasResumed, isTrue);
      await _until(
          () => client.resumptionFor(desktop.publicKey)?.ticket != oldTicket);
      // CI timing is variable; this records the loopback figure while the
      // one-response assertion above proves the protocol round-trip count.
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 10)));
      expect(watch.elapsed, lessThan(fullWatch.elapsed));

      // Presenting the consumed ticket again must fall back on the same socket.
      client.restoreResumption(desktop.publicKey,
          ClientResumption(ticket: oldTicket, secret: oldSecret));
      await client.disconnect();
      await client.connect(target);
      expect((await client.waitUntilConnected()).wasResumed, isFalse);

      // A changed AEAD byte cannot authenticate and costs one full handshake.
      await _until(
          () => client.resumptionFor(desktop.publicKey)!.ticket != oldTicket);
      final saved = client.resumptionFor(desktop.publicKey)!;
      final tampered = Uint8List.fromList(saved.ticket)..[30] ^= 1;
      client.restoreResumption(desktop.publicKey,
          ClientResumption(ticket: tampered, secret: saved.secret));
      await client.disconnect();
      await client.connect(target);
      expect((await client.waitUntilConnected()).wasResumed, isFalse);

      // A new process has a new ticket key even with the same static identity.
      await _until(
          () => client.resumptionFor(desktop.publicKey)!.ticket != tampered);
      await client.disconnect();
      await server.stop();
      server = RemoteLinkServer(
          identity: desktop,
          capabilities: serverCaps,
          trustStore: trust,
          clock: SystemClock(),
          port: 0);
      await server.start();
      target = ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktop.id,
          serverPublicKey: desktop.publicKey);
      await client.connect(target);
      expect((await client.waitUntilConnected()).wasResumed, isFalse);

      // A revoked peer cannot use even a fresh ticket.
      await _until(() => client.resumptionFor(desktop.publicKey) != null);
      await trust.revoke(phone.id);
      await client.disconnect();
      await client.connect(target);
      final rejected = await client.waitUntilConnected();
      expect(rejected.wasResumed, isFalse);
    } finally {
      await client.dispose();
      await server.stop();
      await trust.dispose();
    }
  });
}
