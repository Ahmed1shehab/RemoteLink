import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';
import 'package:remotelink_desktop/src/ui/home_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

/// Pairing asks whether a device may ever connect. This asks whether it may
/// connect *now*, and until it existed the second question was never put:
/// a phone paired once reached the computer from then on with nobody told,
/// which is fine while it is in its owner's pocket and is the whole problem
/// when it is not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopService admission', () {
    late FakeClock clock;
    late DeviceIdentity desktopIdentity;
    late DeviceIdentity phoneIdentity;
    late InMemoryTrustStore trustStore;
    late DesktopService service;
    late RemoteLinkClient client;

    setUp(() async {
      clock = FakeClock();
      desktopIdentity = await DeviceIdentity.generate();
      phoneIdentity = await DeviceIdentity.generate();
      trustStore = InMemoryTrustStore();

      await trustStore.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Pixel 9 Pro',
          platform: PlatformKind.android,
          pairedAt: clock.now(),
          permissionTier: PermissionTier.standard.wireValue,
        ),
      );

      service = DesktopService(
        identity: desktopIdentity,
        trustStore: trustStore,
        deviceName: 'Mac Studio',
        appVersion: '0.1.0',
        clock: clock,
        servicePort: 0,
        input: const UnsupportedInputBackend('test'),
        clipboardBackend: const UnsupportedClipboardBackend(),
        media: const UnsupportedMediaBackend(),
        brightness: const UnsupportedBrightnessBackend('test'),
        systemInfo: const UnsupportedSystemInfoBackend('test'),
        networkAdapters: const UnsupportedNetworkAdapterBackend('test'),
      );
      await service.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(Capabilities.clipboardText),
        clock: clock,
      );
    });

    tearDown(() async {
      await client.dispose();
      await service.stop();
      await trustStore.dispose();
    });

    Future<void> dial() => client.connect(
          ConnectionTarget(
            host: '127.0.0.1',
            port: service.boundPort,
            deviceId: desktopIdentity.id,
            serverPublicKey: desktopIdentity.publicKey,
            displayName: 'Mac Studio',
          ),
        );

    test('asking is on unless the user has turned it off', () {
      // The default is the feature. A setting that has to be found before it
      // protects anything protects nobody.
      expect(service.asksBeforeConnecting, isTrue);
    });

    test('a paired device is held, told so, and named from the trust store',
        () async {
      final held = service.connectionRequests.first;
      final toldToWait = client.states
          .firstWhere((state) => state == ClientState.awaitingApproval);

      await dial();
      final pending = await held.timeout(const Duration(seconds: 10));
      await toldToWait.timeout(const Duration(seconds: 10));

      expect(pending.peerId, phoneIdentity.id);
      // The stored name, never one the connecting device sent with the
      // request: a name it can rewrite between connections is a name that can
      // wear another device's in the prompt.
      expect(pending.peerName, 'Pixel 9 Pro');
      expect(client.heldBy, 'Mac Studio');
      expect(client.isConnected, isFalse);
    });

    test('nothing the held phone sends reaches the computer, until it does',
        () async {
      final held = service.connectionRequests.first;
      await dial();
      final pending = await held.timeout(const Duration(seconds: 10));

      // A rename is the cheapest message with a durable effect, and the effect
      // is what makes this test able to fail: it lands in the trust store or
      // it does not.
      final session = await client.waitUntilConnected();
      await session.send(const DeviceRename('Not yet'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Dropped, and the phone was not told what happened either — answering
      // would confirm to an unapproved device that it reached a real computer.
      expect(
          (await trustStore.findById(phoneIdentity.id))?.name, 'Pixel 9 Pro');

      final allowed = client.messages
          .where((message) => message is ConnectionDecision)
          .cast<ConnectionDecision>()
          .first
          .timeout(const Duration(seconds: 10));

      await service.approveConnection(pending);
      expect((await allowed).isAllowed, isTrue);

      await session.send(const DeviceRename('Now it arrives'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        (await trustStore.findById(phoneIdentity.id))?.name,
        'Now it arrives',
      );
    });

    test('a device let in once is not asked about again this run', () async {
      // A phone drops its link every time the Wi-Fi blips, and a prompt on
      // each of those would be trained away within a day. The answer holds
      // until the app quits, which is a window a person can hold in their head.
      final held = service.connectionRequests.first;
      await dial();
      await service.approveConnection(
        await held.timeout(const Duration(seconds: 10)),
      );
      await client.waitUntilConnected();

      final asked = <PendingConnection>[];
      final subscription = service.connectionRequests.listen(asked.add);
      addTearDown(subscription.cancel);

      await client.disconnect();
      await dial();
      await client.waitUntilConnected().timeout(const Duration(seconds: 10));

      // Long enough for a prompt to have been raised if one were coming.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(asked, isEmpty);
      expect(client.state, ClientState.connected);
    });

    test('turning a device away stops it, rather than making it try again',
        () async {
      final held = service.connectionRequests.first;
      await dial();
      final pending = await held.timeout(const Duration(seconds: 10));

      final refused =
          client.states.firstWhere((state) => state == ClientState.failed);
      await service.declineConnection(pending);
      await refused.timeout(const Duration(seconds: 10));

      expect(client.refusal, ConnectionAnswer.declined);
      final attempts = client.connectionAttemptCount;

      // The supervisor cannot tell a refusal from a dropped link. Left to
      // retry, it would put the question back on this screen every couple of
      // seconds until somebody tapped Allow to make it stop.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(client.connectionAttemptCount, attempts);
    });

    test('a request nobody answers is turned away by the clock', () async {
      final held = service.connectionRequests.first;
      await dial();
      await held.timeout(const Duration(seconds: 10));

      final refused =
          client.states.firstWhere((state) => state == ClientState.failed);

      // The window, on the fake clock the service was built with — no wall
      // clock and no sleeping through a real minute.
      clock.advance(kConnectionApprovalWindow);
      await refused.timeout(const Duration(seconds: 10));

      expect(
        client.refusal,
        ConnectionAnswer.timedOut,
        reason: 'an unattended computer is not the same as a refusal, and the '
            'phone says something different about each',
      );
    });

    test('switching the setting off lets the next connection straight in',
        () async {
      service.asksBeforeConnecting = false;

      final asked = <PendingConnection>[];
      final subscription = service.connectionRequests.listen(asked.add);
      addTearDown(subscription.cancel);

      await dial();
      await client.waitUntilConnected().timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(asked, isEmpty);
      expect(client.state, ClientState.connected);
    });
  });

  group('ConnectionRequestDialog', () {
    testWidgets('names the device and starts focused on refusing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConnectionRequestDialog(peerName: 'Pixel 9 Pro'),
          ),
        ),
      );

      expect(find.textContaining('Pixel 9 Pro'), findsOneWidget);

      // The affirmative button holds the initial focus on every other dialog
      // in this app. Not here: this one appears unprompted, and a Return
      // pressed at the wrong moment must not be what lets a device in.
      final focused = tester.widget<TextButton>(
        find.widgetWithText(TextButton, "Don't allow"),
      );
      expect(focused.autofocus, isTrue);
    });
  });
}
