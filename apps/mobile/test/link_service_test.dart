import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/devices/link_service.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

/// Records what the background service was asked to do.
///
/// The Android half cannot be exercised from a widget test — a foreground
/// service needs a device — so the contract this pins is the Dart side of it:
/// that the service runs for exactly as long as there is a link worth keeping,
/// and that the notification never claims more than the connection does.
final class _RecordingLinkService implements LinkService {
  final List<String> calls = <String>[];
  final List<String> titles = <String>[];

  // Closed by `dispose` below, which every `tearDown` here calls. The lint
  // only recognises a `close()` in the same function that made the sink, and
  // a controller a fake has to expose cannot be created inside one.
  // ignore: close_sinks
  final StreamController<void> disconnects = StreamController<void>.broadcast();

  Future<void> dispose() => disconnects.close();

  @override
  Future<void> start({
    required String title,
    required String body,
    required String disconnectLabel,
  }) async {
    calls.add('start');
    titles.add(title);
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<bool> openBatterySettings() async {
    calls.add('battery');
    return true;
  }

  @override
  bool get isSupported => true;

  @override
  Future<bool> openAccessibilitySettings() async => false;

  @override
  Future<bool> backgroundClipboardEnabled() async => false;

  @override
  Stream<String> get backgroundCopies => const Stream<String>.empty();

  @override
  Stream<void> get backgroundReadRefusals => const Stream<void>.empty();


  @override
  Stream<void> get disconnectRequests => disconnects.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the background link service', () {
    late RemoteLinkServer server;
    late RemoteLinkClient client;
    late ProviderContainer container;
    late _RecordingLinkService service;
    late InMemoryTrustStore trust;
    late DeviceIdentity desktopIdentity;

    Future<void> connect() async {
      final connected =
          client.states.firstWhere((s) => s == ClientState.connected);
      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
          displayName: 'Work Mac',
        ),
      );
      await connected.timeout(const Duration(seconds: 10));
      await pumpEventQueue(times: 20);
    }

    setUp(() async {
      desktopIdentity = await DeviceIdentity.fromPrivateKey(
        Uint8List.fromList(List<int>.filled(32, 3)),
      );
      final phoneIdentity = await DeviceIdentity.fromPrivateKey(
        Uint8List.fromList(List<int>.filled(32, 5)),
      );

      trust = InMemoryTrustStore();
      await trust.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.extended.wireValue,
        ),
      );

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: const Capabilities(0),
        trustStore: trust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(0),
        clock: SystemClock(),
      );

      service = _RecordingLinkService();
      container = ProviderContainer(
        overrides: <Override>[
          identityStoreProvider
              .overrideWith((ref) async => InMemoryIdentityStore()),
          identityProvider
              .overrideWith((ref) => Future<DeviceIdentity>.value(phoneIdentity)),
          clientProvider.overrideWith((ref) async => client),
          linkServiceProvider.overrideWithValue(service),
        ],
      );
      container.read(backgroundLinkProvider);
      await container.read(clientProvider.future);
      await pumpEventQueue();
    });

    tearDown(() async {
      container.dispose();
      await service.dispose();
      await client.disconnect();
      await server.stop();
      await trust.dispose();
    });

    test('does not run before there is anything to keep alive', () async {
      expect(service.calls, isNot(contains('start')));
    });

    test('runs while connected and names the computer', () async {
      await connect();

      expect(service.calls, contains('start'));
      expect(service.titles.last, 'Connected to Work Mac');
    });

    test('stops when the user disconnects', () async {
      await connect();
      await client.disconnect();
      await pumpEventQueue(times: 20);

      expect(service.calls.last, 'stop');
    });

    test('a disconnect from the notification ends the session', () async {
      await connect();
      expect(client.isConnected, isTrue);

      service.disconnects.add(null);
      await pumpEventQueue(times: 30);

      expect(client.isConnected, isFalse);
      expect(service.calls.last, 'stop');
    });

    test('the preference stops it without ending the session', () async {
      await connect();

      await container.read(backgroundLinkEnabledProvider.notifier).set(false);
      await pumpEventQueue(times: 20);

      expect(service.calls.last, 'stop');
      expect(
        client.isConnected,
        isTrue,
        reason: 'turning off the notification is not asking to disconnect',
      );

      // And back on again mid-session, without waiting for a reconnect.
      await container.read(backgroundLinkEnabledProvider.notifier).set(true);
      await pumpEventQueue(times: 20);
      expect(service.calls.last, 'start');
    });
  });
}
