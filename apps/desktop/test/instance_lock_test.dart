import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/instance_lock.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

void main() {
  late Directory directory;
  late File file;
  late InstanceLock lock;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('rl-instance-lock');
    file = File('${directory.path}/instance.lock');
    lock = InstanceLock(file);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  group('InstanceLock', () {
    test('a first launch is free to start', () async {
      expect(await lock.otherInstance(), isNull);
    });

    test('a lock naming a port somebody holds means another copy is up',
        () async {
      final held = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      addTearDown(held.close);
      await lock.claim(port: held.port);

      final other = await lock.otherInstance();
      expect(other, isNotNull);
      expect(other!.port, held.port);
    });

    test('a lock left behind by a crash is taken over, not obeyed', () async {
      // The port is recorded and nothing is listening on it, which is what a
      // lock file outliving its process looks like. Treating that as "already
      // running" would leave the user unable to start the app at all until they
      // found and deleted a file they have never heard of.
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = socket.port;
      await lock.claim(port: port);
      await socket.close();

      expect(await lock.otherInstance(), isNull);
    });

    test('a damaged lock is treated as no lock', () async {
      file.writeAsStringSync('this is not json');
      expect(await lock.otherInstance(), isNull);
    });

    test('a lock with no port is treated as no lock', () async {
      file.writeAsStringSync(jsonEncode(<String, Object?>{'pid': 1}));
      expect(await lock.otherInstance(), isNull);
    });

    test('claiming records the port and this process', () async {
      await lock.claim(port: 47811);

      final written =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(written['port'], 47811);
      expect(written['pid'], pid);
      expect(DateTime.tryParse('${written['startedAt']}'), isNotNull);
    });

    test('releasing removes the file', () async {
      await lock.claim(port: 47811);
      expect(file.existsSync(), isTrue);

      await lock.release();
      expect(file.existsSync(), isFalse);
    });

    test('releasing a lock that is already gone is not an error', () async {
      await lock.release();
      expect(file.existsSync(), isFalse);
    });
  });

  group('the port the server actually binds', () {
    late DeviceIdentity identity;
    late TrustStore trustStore;

    setUp(() async {
      identity = await DeviceIdentity.generate();
      trustStore = InMemoryTrustStore();
    });

    RemoteLinkServer serverOn(int port, {bool allowFallback = true}) =>
        RemoteLinkServer(
          identity: identity,
          capabilities: const Capabilities(Capabilities.mouse),
          trustStore: trustStore,
          clock: SystemClock(),
          port: port,
          allowPortFallback: allowFallback,
        );

    test('is the preferred one when it is free', () async {
      final probe = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = probe.port;
      await probe.close();

      final server = serverOn(port);
      await server.start();
      addTearDown(server.stop);

      expect(server.boundPort, port);
    });

    test('falls back to another when the preferred one is taken', () async {
      // The whole point: a companion that refuses to start because a number is
      // busy is a companion the phone cannot reach at all. Every client learns
      // the port from discovery, so any port will do.
      final occupier = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      addTearDown(occupier.close);

      final server = serverOn(occupier.port);
      await server.start();
      addTearDown(server.stop);

      expect(server.isRunning, isTrue);
      expect(server.boundPort, isNot(occupier.port));
      expect(server.boundPort, greaterThan(0));
    });

    test('still refuses when the caller asked it not to fall back', () async {
      final occupier = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      addTearDown(occupier.close);

      final server = serverOn(occupier.port, allowFallback: false);
      await expectLater(
        server.start(),
        throwsA(
          isA<TransportError>()
              .having((e) => e.code, 'code', 'transport.bind_failed'),
        ),
      );
      expect(server.isRunning, isFalse);
    });

    test('a fallback port is reachable, not merely bound', () async {
      // `boundPort` reporting a number proves nothing on its own; the listener
      // has to be attached to the socket that was bound second.
      final occupier = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      addTearDown(occupier.close);

      final server = serverOn(occupier.port);
      await server.start();
      addTearDown(server.stop);

      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.boundPort,
      );
      addTearDown(socket.destroy);
      expect(socket.remotePort, server.boundPort);
    });
  });
}
