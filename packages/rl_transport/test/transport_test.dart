import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';
import 'package:test/test.dart';

const Capabilities _caps = Capabilities(
  Capabilities.mouse | Capabilities.keyboard | Capabilities.clipboardText,
);

void main() {
  group('Beacon', () {
    Beacon sample({BeaconKind kind = BeaconKind.announce}) => Beacon(
          kind: kind,
          deviceId: const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123'),
          name: "Ahmed's MacBook Pro",
          platform: PlatformKind.macos,
          servicePort: 47811,
          protocolVersion: kProtocolVersion,
          publicKeyFingerprint:
              Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
          capabilities: _caps,
          activeSessions: 2,
        );

    test('round trips through its datagram encoding', () {
      final original = sample();
      final parsed = Beacon.tryParse(original.encode());

      expect(parsed, isNotNull);
      expect(parsed!.deviceId, original.deviceId);
      expect(parsed.name, original.name);
      expect(parsed.platform, PlatformKind.macos);
      expect(parsed.servicePort, 47811);
      expect(parsed.publicKeyFingerprint, original.publicKeyFingerprint);
      expect(parsed.capabilities.has(Capabilities.mouse), isTrue);
      expect(parsed.activeSessions, 2);
    });

    test('fits comfortably inside one datagram', () {
      // Fragmented multicast is unreliable on consumer access points, so the
      // beacon must stay well under a 1500-byte MTU.
      expect(sample().encode().length, lessThan(512));
    });

    test('rejects datagrams from other protocols without throwing', () {
      // This parses unauthenticated input from any host on the network. A
      // malformed packet must cost one drop, not an exception that kills the
      // listener.
      expect(Beacon.tryParse(Uint8List(0)), isNull);
      expect(Beacon.tryParse(Uint8List.fromList(<int>[1, 2, 3, 4, 5])), isNull);
      expect(
        Beacon.tryParse(Uint8List.fromList('GET / HTTP/1.1'.codeUnits)),
        isNull,
      );
    });

    test('rejects a truncated beacon', () {
      final encoded = sample().encode();
      expect(
        Beacon.tryParse(Uint8List.sublistView(encoded, 0, encoded.length ~/ 2)),
        isNull,
      );
    });

    test('rejects an unsupported protocol version', () {
      final encoded = sample().encode();
      encoded[kBeaconMagic.length] = 99;
      expect(Beacon.tryParse(encoded), isNull);
    });

    test('all three kinds survive the round trip', () {
      for (final kind in BeaconKind.values) {
        expect(Beacon.tryParse(sample(kind: kind).encode())?.kind, kind);
      }
    });
  });

  group('DiscoveredDevice', () {
    test('goes stale after the timeout', () {
      final device = DiscoveredDevice(
        beacon: Beacon(
          kind: BeaconKind.announce,
          deviceId: const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123'),
          name: 'PC',
          platform: PlatformKind.windows,
          servicePort: 47811,
          protocolVersion: 1,
          publicKeyFingerprint: Uint8List(8),
          capabilities: _caps,
        ),
        address: '192.168.1.5',
        firstSeen: DateTime.utc(2026),
        lastSeen: DateTime.utc(2026),
      );

      expect(
        device.isStale(DateTime.utc(2026).add(const Duration(seconds: 3)),
            kDeviceTimeout),
        isFalse,
      );
      expect(
        device.isStale(DateTime.utc(2026).add(const Duration(seconds: 30)),
            kDeviceTimeout),
        isTrue,
      );
    });
  });

  group('BackoffPolicy', () {
    test('the first attempt is immediate', () {
      expect(
        BackoffPolicy.responsive.delayFor(0, Random(1)),
        Duration.zero,
        reason: 'a Wi-Fi handoff must not become a visible disconnection',
      );
    });

    test('grows exponentially and then caps', () {
      const policy = BackoffPolicy(jitter: 0);
      final random = Random(1);

      expect(policy.delayFor(1, random).inMilliseconds, 100);
      expect(policy.delayFor(2, random).inMilliseconds, 200);
      expect(policy.delayFor(3, random).inMilliseconds, 400);
      expect(policy.delayFor(20, random), policy.maximum);
    });

    test('jitter spreads simultaneous retries apart', () {
      // Without this, every device in the house retries in lockstep after a
      // router reboot and collides on every attempt.
      const policy = BackoffPolicy();
      final delays = <int>{
        for (var seed = 0; seed < 20; seed++)
          policy.delayFor(5, Random(seed)).inMicroseconds,
      };
      expect(delays.length, greaterThan(10));
    });

    test('jittered delays never exceed the cap', () {
      const policy = BackoffPolicy();
      for (var seed = 0; seed < 50; seed++) {
        expect(
          policy.delayFor(30, Random(seed)),
          lessThanOrEqualTo(policy.maximum),
        );
      }
    });
  });

  group('ConnectionQuality', () {
    test('bars map to perceptual thresholds, not round numbers', () {
      ConnectionQuality withRtt(int micros) => ConnectionQuality(
            roundTripMicros: micros,
            jitterMicros: 0,
            sentMessages: 0,
            receivedMessages: 0,
            sentBytes: 0,
            receivedBytes: 0,
            missedHeartbeats: 0,
          );

      expect(withRtt(0).bars, 0, reason: 'no sample yet');
      expect(withRtt(5000).bars, 4, reason: '5 ms is indistinguishable');
      expect(withRtt(40000).bars, 3);
      expect(withRtt(100000).bars, 2);
      expect(withRtt(400000).bars, 1, reason: 'pointing becomes guesswork');
    });
  });

  group('end to end over loopback', () {
    late DeviceIdentity phoneIdentity;
    late DeviceIdentity desktopIdentity;
    late InMemoryTrustStore trustStore;
    late RemoteLinkServer server;
    late RemoteLinkClient client;
    late Clock clock;

    setUp(() async {
      clock = SystemClock();
      phoneIdentity = await DeviceIdentity.generate();
      desktopIdentity = await DeviceIdentity.generate();
      trustStore = InMemoryTrustStore();

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: _caps,
        trustStore: trustStore,
        clock: clock,
        // Port 0 asks the OS for a free one, so parallel test runs cannot
        // collide on a hard-coded port.
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: _caps,
        clock: clock,
      );
    });

    tearDown(() async {
      await client.dispose();
      await server.stop();
      await trustStore.dispose();
    });

    test('an unpaired client connects and lands in the pairing state',
        () async {
      final acceptedFuture = server.accepted.first;

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
        ),
      );

      final accepted = await acceptedFuture.timeout(
        const Duration(seconds: 10),
      );

      expect(accepted.peerId, phoneIdentity.id);
      expect(accepted.awaitingPairing, isTrue);
      expect(
        accepted.handshake.peerStaticPublicKey,
        phoneIdentity.publicKey,
      );
      expect(server.sessionCount, 1);
    });

    test('a trusted client connects silently and exchanges messages', () async {
      await trustStore.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: 2,
        ),
      );

      final acceptedFuture = server.accepted.first;

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      final accepted =
          await acceptedFuture.timeout(const Duration(seconds: 10));
      expect(accepted.awaitingPairing, isFalse);
      expect(accepted.handshake.peerWasKnown, isTrue);

      // The server finishes its half of the handshake one message before the
      // client finishes its own, so `server.accepted` firing does NOT mean the
      // client has a session yet. Waiting on the server's signal alone is a
      // race, and it is the one that made this test flaky.
      await client.waitUntilConnected();

      final received = accepted.session.messages.first;
      final sent = await client.send(
        const MouseMove(deltaX: 17, deltaY: -42),
      );
      expect(sent, isTrue);

      final message =
          await received.timeout(const Duration(seconds: 10)) as MouseMove;
      expect(message.deltaX, 17);
      expect(message.deltaY, -42);
    });

    test('the server → client direction works too', () async {
      await trustStore.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: 2,
        ),
      );

      final acceptedFuture = server.accepted.first;
      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );
      final accepted =
          await acceptedFuture.timeout(const Duration(seconds: 10));
      await client.waitUntilConnected();

      final inbound = client.messages.first;
      await accepted.session.send(
        const SystemStatus(volume: 0.4, isMuted: false, uptimeSeconds: 99),
      );

      final status =
          await inbound.timeout(const Duration(seconds: 10)) as SystemStatus;
      expect(status.uptimeSeconds, 99);
      expect(status.volume, closeTo(0.4, 0.001));
    });

    test('overlapping sends stay ordered and authenticate', () async {
      // Regression test for a real bug found only by running this suite.
      //
      // `DirectionalCipher.seal` is asynchronous: the nonce is allocated before
      // the await and the socket write happens after it. Overlapping sends
      // therefore took nonces 0 and 1 but could reach the socket in the other
      // order, and the peer — which derives the nonce from arrival order —
      // rejected the first record with an AEAD failure that looks exactly like
      // an active attacker.
      //
      // In production the overlap came from the one-second heartbeat firing
      // while application data was in flight. Firing a burst without awaiting
      // between sends reproduces it far more reliably.
      await trustStore.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: 2,
        ),
      );

      final acceptedFuture = server.accepted.first;
      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );
      final accepted =
          await acceptedFuture.timeout(const Duration(seconds: 10));
      await client.waitUntilConnected();

      const burst = 25;
      final received = <String>[];
      final complete = Completer<void>();

      // TextInput rather than MouseMove: cursor deltas are declared lossy and
      // are deliberately coalesced under load, which would merge the burst and
      // defeat the point of the test.
      final subscription = accepted.session.messages.listen((message) {
        if (message is! TextInput) return;
        received.add(message.text);
        if (received.length == burst && !complete.isCompleted) {
          complete.complete();
        }
      });
      addTearDown(subscription.cancel);

      // No await between sends — this is what a fast paste or a key repeat
      // looks like, and it is what used to corrupt the nonce sequence.
      final results = await Future.wait<bool>(<Future<bool>>[
        for (var i = 0; i < burst; i++) client.send(TextInput('$i')),
      ]);
      expect(results.every((ok) => ok), isTrue, reason: 'every send accepted');

      await complete.future.timeout(const Duration(seconds: 10));
      expect(
        received,
        List<String>.generate(burst, (i) => '$i'),
        reason: 'records must arrive in the order they were sent',
      );
      expect(
        accepted.session.state,
        isNot(SessionState.closed),
        reason: 'a nonce desync would have torn the session down',
      );
    });

    test('a client with the wrong server key refuses to connect', () async {
      final impostorKey = (await DeviceIdentity.generate()).publicKey;

      final failed = client.states.firstWhere(
        (state) => state == ClientState.failed,
      );

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: impostorKey,
        ),
      );

      await failed.timeout(const Duration(seconds: 10));
      expect(client.state, ClientState.failed);
      expect(client.isConnected, isFalse);
    });

    test('a revoked device is refused', () async {
      await trustStore.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: 2,
          revoked: true,
        ),
      );

      var accepted = false;
      final subscription =
          server.accepted.listen((_) => accepted = true);
      addTearDown(subscription.cancel);

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      await Future<void>.delayed(const Duration(seconds: 2));
      expect(accepted, isFalse);
      expect(server.sessionCount, 0);
    });

    test('a reconnect replaces the earlier session for the same device',
        () async {
      // Otherwise a phone that drops off Wi-Fi accumulates ghost sessions still
      // holding input state — a modifier key latched by a connection that no
      // longer exists.
      await trustStore.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: 2,
        ),
      );

      final target = ConnectionTarget(
        host: '127.0.0.1',
        port: server.boundPort,
        deviceId: desktopIdentity.id,
        serverPublicKey: desktopIdentity.publicKey,
      );

      final first = server.accepted.first;
      await client.connect(target);
      await first.timeout(const Duration(seconds: 10));
      expect(server.sessionCount, 1);

      final second = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: _caps,
        clock: clock,
      );
      addTearDown(second.dispose);

      final secondAccepted = server.accepted.first;
      await second.connect(target);
      await secondAccepted.timeout(const Duration(seconds: 10));

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.sessionCount, 1, reason: 'the old session must be evicted');
    });
  });

  group('FramedConnection framing', () {
    test('reassembles records split across reads', () async {
      // TCP is a stream: a single write can arrive as three reads. This is the
      // property the length prefix exists to guarantee.
      final server = await ServerSocketHarness.start();
      addTearDown(server.dispose);

      final connection = await FramedConnection.connect(
        '127.0.0.1',
        server.port,
      );
      addTearDown(connection.close);

      final received = <Uint8List>[];
      final subscription = connection.records.listen(received.add);
      addTearDown(subscription.cancel);

      final payload = Uint8List.fromList(List<int>.generate(1000, (i) => i));
      final framed = Uint8List(4 + payload.length);
      ByteData.sublistView(framed).setUint32(0, payload.length);
      framed.setRange(4, framed.length, payload);

      // Deliberately dribble the record out in pieces.
      await server.write(Uint8List.sublistView(framed, 0, 2));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await server.write(Uint8List.sublistView(framed, 2, 300));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await server.write(Uint8List.sublistView(framed, 300));

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received, hasLength(1));
      expect(received.single, payload);
    });

    test('splits several records that arrive in one read', () async {
      final server = await ServerSocketHarness.start();
      addTearDown(server.dispose);

      final connection = await FramedConnection.connect(
        '127.0.0.1',
        server.port,
      );
      addTearDown(connection.close);

      final received = <Uint8List>[];
      final subscription = connection.records.listen(received.add);
      addTearDown(subscription.cancel);

      final builder = BytesBuilder();
      for (var i = 1; i <= 5; i++) {
        final payload = Uint8List.fromList(List<int>.filled(i, i));
        final framed = Uint8List(4 + payload.length);
        ByteData.sublistView(framed).setUint32(0, payload.length);
        framed.setRange(4, framed.length, payload);
        builder.add(framed);
      }
      await server.write(builder.takeBytes());

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(received[i], hasLength(i + 1));
      }
    });
  });
}

/// Minimal TCP server for exercising framing directly.
final class ServerSocketHarness {
  ServerSocketHarness._(this._server, this._clientFuture);

  final ServerSocket _server;
  final Future<Socket> _clientFuture;

  static Future<ServerSocketHarness> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return ServerSocketHarness._(server, server.first);
  }

  int get port => _server.port;

  Future<void> write(List<int> bytes) async {
    final socket = await _clientFuture;
    socket.add(bytes);
    await socket.flush();
  }

  Future<void> dispose() async {
    try {
      (await _clientFuture).destroy();
    } on Object {
      // Nothing ever connected; nothing to clean up.
    }
    await _server.close();
  }
}
