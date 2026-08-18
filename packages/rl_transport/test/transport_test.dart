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
        device.isStale(
            DateTime.utc(2026).add(const Duration(seconds: 3)), kDeviceTimeout),
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

    test('awaiting the drain sends every frame instead of the last', () async {
      // Screen frames are declared lossy, which is right for the default path:
      // if frames back up, the newest picture is the only one worth sending
      // and the coalescer keeps exactly that one.
      //
      // It is wrong for the capture loop, which produces the next frame only
      // once the last one is away. There, `send` returning before the write
      // means the loop is paced by its own timer rather than by the link, and
      // frames accumulate in a buffer nobody is measuring — the backlog *is*
      // the lag the user sees. `awaitDrain` makes the future mean "the link
      // has taken this", and the observable consequence is that a paced
      // producer's frames all arrive rather than collapsing into one.
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

      const frames = 5;
      final received = <int>[];
      final complete = Completer<void>();
      final subscription = client.messages.listen((message) {
        if (message is! ScreenFrame) return;
        received.add(message.sequence);
        if (received.length == frames && !complete.isCompleted) {
          complete.complete();
        }
      });
      addTearDown(subscription.cancel);

      ScreenFrame frameNumber(int sequence) => ScreenFrame(
            sequence: sequence,
            ptsMicros: sequence * 1000,
            isKeyframe: true,
            width: 1280,
            height: 720,
            data: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
          );

      // Fired without awaiting between them, so no microtask runs in the gap.
      // That is what the lossy queue is built for and what it does here: every
      // pending screen frame shares one key, so a second frame arriving before
      // the queue drains replaces the first and only the newest survives.
      // Awaiting each one in turn would not show the difference, because the
      // await itself yields and lets the queue drain between frames.
      await Future.wait<void>(<Future<void>>[
        for (var i = 0; i < frames; i++)
          accepted.session.send(frameNumber(i), awaitDrain: true),
      ]);

      await complete.future.timeout(const Duration(seconds: 10));
      expect(
        received,
        List<int>.generate(frames, (i) => i),
        reason: 'every frame should have gone out, in order',
      );
    });

    test('without the drain, queued frames coalesce to the newest', () async {
      // The other half of the pair above, and the reason `awaitDrain` had to be
      // opt-in rather than the new default. Coalescing is correct for a
      // producer that does not wait: when frames are backing up, the newest
      // picture is the only one worth the bandwidth and every older one is
      // already wrong. Deleting that behaviour to fix the capture loop would
      // have traded one latency bug for another.
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

      final received = <int>[];
      final subscription = client.messages.listen((message) {
        if (message is ScreenFrame) received.add(message.sequence);
      });
      addTearDown(subscription.cancel);

      for (var i = 0; i < 5; i++) {
        unawaited(
          accepted.session.send(
            ScreenFrame(
              sequence: i,
              ptsMicros: i * 1000,
              isKeyframe: true,
              width: 1280,
              height: 720,
              data: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
            ),
          ),
        );
      }

      // Long enough for five frames to have arrived had they been sent.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(received, <int>[4],
          reason: 'only the newest frame is worth sending');
    });

    test('a stale address is abandoned once discovery finds the real one',
        () async {
      // The bug, from a real device log: the supervisor was given an address
      // the computer had since moved off, and retried it sixteen times over two
      // minutes while the machine announced its actual address over Bonjour the
      // whole time. Retrying harder cannot fix a wrong address.
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

      final deadPort = await _closedLoopbackPort();

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: deadPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      // Let it fail at least once, so the retarget lands mid-backoff rather
      // than before the supervisor has even tried.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final moved = client.retarget(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
        ),
      );
      expect(moved, isTrue);

      await client.waitUntilConnected(timeout: const Duration(seconds: 10));
      expect(client.target?.port, server.boundPort);
    });

    test('retargeting keeps the stored key rather than the beacon\'s',
        () async {
      // The new address arrives from a discovery beacon, which anyone on the
      // network can send. The address is safe to believe because the handshake
      // verifies the identity afterwards — but only if the *stored* key is
      // still what it is verified against.
      // Two closed loopback ports, so the supervisor stays in its ordinary
      // retry path throughout and never reaches a live peer. Pointing it at an
      // unroutable address instead produces a socket error outside that path,
      // which fails the test for a reason that has nothing to do with the
      // property being checked.
      final closed = await _closedLoopbackPort();
      final alsoClosed = await _closedLoopbackPort();

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: closed,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      final impostor = (await DeviceIdentity.generate()).publicKey;
      client.retarget(
        ConnectionTarget(
          host: '127.0.0.1',
          port: alsoClosed,
          deviceId: desktopIdentity.id,
          serverPublicKey: impostor,
        ),
      );

      expect(client.target?.port, alsoClosed);
      expect(
        client.target?.serverPublicKey,
        desktopIdentity.publicKey,
        reason: 'a beacon replaced the key the handshake verifies against',
      );
      await client.disconnect();
    });

    test('refuses to be aimed at a different computer', () async {
      // Otherwise anyone who can broadcast on this network could walk the
      // phone onto a machine of their choosing.
      final closed = await _closedLoopbackPort();
      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: closed,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      final stranger = await DeviceIdentity.generate();
      expect(
        client.retarget(
          ConnectionTarget(
            host: '127.0.0.1',
            port: closed + 1,
            deviceId: stranger.id,
          ),
        ),
        isFalse,
      );
      expect(client.target?.port, closed);
      await client.disconnect();
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

    test('a revoked device receives a terminal error and stops reconnecting',
        () async {
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

      await client.dispose();
      final reconnectClock = FakeClock();
      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: _caps,
        clock: reconnectClock,
        backoff: const BackoffPolicy(jitter: 0),
      );

      var accepted = false;
      final subscription = server.accepted.listen((_) => accepted = true);
      addTearDown(subscription.cancel);
      final failed = client.states.firstWhere(
        (state) => state == ClientState.failed,
      );

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      await failed.timeout(const Duration(seconds: 10));
      expect(accepted, isFalse);
      expect(server.sessionCount, 0);
      expect(client.failureCode, ProtocolErrorCode.revoked);
      expect(client.connectionAttemptCount, 1);

      // A fake clock makes the negative assertion deterministic: advancing
      // beyond the maximum backoff would release every retry timer if the
      // supervisor had armed one.
      reconnectClock.advance(const Duration(days: 1));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        client.connectionAttemptCount,
        1,
        reason: 'a revoked peer must not make a second connection attempt',
      );
    });

    test('live revocation fails the client without another attempt', () async {
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

      await client.dispose();
      final reconnectClock = FakeClock();
      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: _caps,
        clock: reconnectClock,
        backoff: const BackoffPolicy(jitter: 0),
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
      await acceptedFuture.timeout(const Duration(seconds: 10));
      await client.waitUntilConnected();

      final failed = client.states.firstWhere(
        (state) => state == ClientState.failed,
      );
      final attemptsAtRevocation = client.connectionAttemptCount;
      await server.revokePeer(phoneIdentity.id);
      await failed.timeout(const Duration(seconds: 10));

      expect(client.failureCode, ProtocolErrorCode.revoked);
      reconnectClock.advance(const Duration(days: 1));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        client.connectionAttemptCount - attemptsAtRevocation,
        lessThanOrEqualTo(1),
        reason: 'revocation permits at most one racing reconnect attempt',
      );
    });

    test('every non-retryable protocol error fails with its code', () async {
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

      final terminalCodes =
          ProtocolErrorCode.values.where((code) => !code.isRetryable).toList();

      for (final code in terminalCodes) {
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

        final failed = client.states.firstWhere(
          (state) => state == ClientState.failed,
        );
        final ended = server.ended.first;
        await accepted.session.send(
          ErrorMessage(code: code, detail: 'terminal test error'),
        );

        await failed.timeout(const Duration(seconds: 10));
        expect(client.failureCode, code);
        await ended.timeout(const Duration(seconds: 10));
      }
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

    test('the granted tier is readable by something that subscribed late',
        () async {
      // The desktop sends the grant the moment a trusted session is
      // established, and `messages` is a broadcast stream — so a screen built
      // a moment later sees nothing at all. Every UI asking "what tier am I?"
      // got null and kept it, because a device whose tier never changes never
      // receives a second grant. The phone's screen-share button checks the
      // tier before offering itself, so it never appeared.
      //
      // Deliberately subscribing *after* the connection is up: subscribing
      // first is the case that already worked.
      await trustStore.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.admin.wireValue,
        ),
      );

      expect(client.grantedTier, isNull, reason: 'nothing granted yet');

      final accepted = server.accepted.first;
      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );
      final session = await accepted.timeout(const Duration(seconds: 10));
      await client.waitUntilConnected();

      await session.session.send(
        const PermissionGrant(tier: PermissionTier.admin),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(client.grantedTier, PermissionTier.admin);
    });
  });

  group('heartbeat liveness', () {
    // Real timers, deliberately. The heartbeat is a `Timer.periodic` over a
    // real socket, so there is nothing here that a fake clock alone can drive:
    // what is faked is the *clock the deadline is measured against*, which is
    // what lets a sixty-second silence be created without waiting sixty
    // seconds. The test still costs about two real seconds, one per tick.
    late DeviceIdentity phoneIdentity;
    late DeviceIdentity desktopIdentity;
    late InMemoryTrustStore trustStore;
    late RemoteLinkServer server;
    late RemoteLinkClient client;
    late FakeClock phoneClock;

    setUp(() async {
      phoneIdentity = await DeviceIdentity.generate();
      desktopIdentity = await DeviceIdentity.generate();
      trustStore = InMemoryTrustStore();
      // The phone's clock is the fake one; the desk keeps real time. Sharing a
      // fake between them would advance both, and the desk would then hang up
      // on the phone for the very silence this test is creating.
      phoneClock = FakeClock();

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: _caps,
        trustStore: trustStore,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: _caps,
        clock: phoneClock,
      );

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
    });

    tearDown(() async {
      await client.dispose();
      await server.stop();
      await trustStore.dispose();
    });

    test('a peer still delivering data is not declared silent', () async {
      // The bug this covers, seen on a real phone: while a screen stream ran,
      // the session was torn down roughly every fifteen seconds. Both the
      // frames and the pongs share one TCP stream, so a queued 200 kB frame
      // sits in front of the pong and delays it past the deadline — and the
      // deadline was measured on pongs alone. The desk was visibly alive,
      // sending thirty frames a second, and was hung up on for being silent.
      final acceptedFuture = server.accepted.first;
      // Off zero before the first tick. At exactly zero the "have we ever
      // pinged" guard never opens and the deadline is never evaluated at all,
      // which would make this test pass without testing anything.
      phoneClock.advance(const Duration(seconds: 5));

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
      await client.waitUntilConnected(timeout: const Duration(seconds: 10));
      final session = client.session!;

      // Wait out one full ping/pong before creating the silence. Doing it
      // sooner means the first tick both establishes and refreshes the pong
      // time, and the gap this test depends on never exists.
      await session.quality.first.timeout(const Duration(seconds: 5));

      // A minute with no pong, and traffic arriving throughout.
      phoneClock.advance(const Duration(seconds: 60));
      final delivered = session.messages.first;
      await accepted.session.send(const MouseMove(deltaX: 1, deltaY: 1));
      await delivered.timeout(const Duration(seconds: 5));

      final outcome = await Future.any<String>(<Future<String>>[
        session.quality.first.then((_) => 'stayed up'),
        session.stateChanges
            .firstWhere((state) => state == SessionState.closed)
            .then((_) => 'hung up'),
      ]).timeout(const Duration(seconds: 5));

      expect(
        outcome,
        'stayed up',
        reason: 'the peer was sending data the whole time',
      );
      expect(identical(client.session, session), isTrue);
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
    // A reference to the socket the harness owns via _clientFuture, not a new
    // one. dispose() destroys it; closing here would tear down the connection
    // between writes.
    // ignore: close_sinks
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

/// A loopback port nothing is listening on.
///
/// Bound and immediately released rather than guessed: an arbitrary port number
/// is occasionally in use on a developer's machine, and a test that connects to
/// something real by accident fails in a way that looks like a protocol bug.
Future<int> _closedLoopbackPort() async {
  final probe = await ServerSocket.bind('127.0.0.1', 0);
  final port = probe.port;
  await probe.close();
  return port;
}
