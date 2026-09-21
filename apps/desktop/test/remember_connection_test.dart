import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';
import 'package:remotelink_desktop/src/ui/home_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

/// Being asked to allow a device every time it connects is the right default
/// and the wrong ending. These cover the way out of it: both ends agree, once,
/// and the question stops being asked — and, just as importantly, that one end
/// agreeing is not enough.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopService remembering', () {
    late FakeClock clock;
    late DeviceIdentity desktopIdentity;
    late DeviceIdentity phoneIdentity;
    late InMemoryTrustStore trustStore;
    late DesktopService service;
    late RemoteLinkClient client;

    Future<void> storePhone({
      bool autoAdmit = false,
      bool rememberAsked = false,
    }) =>
        trustStore.upsert(
          TrustedPeer(
            id: phoneIdentity.id,
            publicKey: phoneIdentity.publicKey,
            name: 'Pixel 9 Pro',
            platform: PlatformKind.android,
            pairedAt: clock.now(),
            permissionTier: PermissionTier.standard.wireValue,
            autoAdmit: autoAdmit,
            rememberAsked: rememberAsked,
          ),
        );

    setUp(() async {
      clock = FakeClock();
      desktopIdentity = await DeviceIdentity.generate();
      phoneIdentity = await DeviceIdentity.generate();
      trustStore = InMemoryTrustStore();
      await storePhone();

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

    /// The phone's half of the agreement, as the phone app sends it.
    Future<void> answerFromThePhone({required bool agreed}) async {
      final session = await client.waitUntilConnected();
      await session.send(RememberConnection(agreed: agreed));
    }

    test('a remembered device is let straight in, with nobody asked', () async {
      await storePhone(autoAdmit: true, rememberAsked: true);

      final asked = <PendingConnection>[];
      final subscription = service.connectionRequests.listen(asked.add);
      addTearDown(subscription.cancel);

      await dial();
      await client.waitUntilConnected().timeout(const Duration(seconds: 10));

      // Long enough for a prompt to have been raised if one were coming.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(asked, isEmpty);
      expect(client.state, ClientState.connected);
    });

    test('two yeses are what make a device remembered', () async {
      final held = service.connectionRequests.first;
      final question = service.rememberRequests.first;

      await dial();
      await service.approveConnection(
        await held.timeout(const Duration(seconds: 10)),
      );

      final pending = await question.timeout(const Duration(seconds: 10));
      expect(pending.peerName, 'Pixel 9 Pro');

      // The phone's answer, then this computer's. Either order settles it; the
      // point is that neither one settles it alone.
      await answerFromThePhone(agreed: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final halfway = await trustStore.findById(phoneIdentity.id);
      expect(
        halfway?.autoAdmit,
        isFalse,
        reason: 'the peer agreeing is not this computer agreeing',
      );
      expect(
        halfway?.rememberAsked,
        isFalse,
        reason: 'nothing has been asked here yet, so nothing is recorded',
      );

      await service.answerRemember(pending, agreed: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final peer = await trustStore.findById(phoneIdentity.id);
      expect(peer?.autoAdmit, isTrue);
      expect(peer?.rememberAsked, isTrue);
    });

    test('this computer answering yes is told to the phone', () async {
      final held = service.connectionRequests.first;
      final question = service.rememberRequests.first;

      await dial();
      await service.approveConnection(
        await held.timeout(const Duration(seconds: 10)),
      );
      final pending = await question.timeout(const Duration(seconds: 10));

      final answer = client.messages
          .where((message) => message is RememberConnection)
          .cast<RememberConnection>()
          .first
          .timeout(const Duration(seconds: 10));

      await service.answerRemember(pending, agreed: true);
      expect((await answer).agreed, isTrue);
    });

    test('one no leaves the device asked-about, and stops the question',
        () async {
      final held = service.connectionRequests.first;
      final question = service.rememberRequests.first;

      await dial();
      await service.approveConnection(
        await held.timeout(const Duration(seconds: 10)),
      );
      final pending = await question.timeout(const Duration(seconds: 10));

      await answerFromThePhone(agreed: true);
      await service.answerRemember(pending, agreed: false);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final peer = await trustStore.findById(phoneIdentity.id);
      expect(peer?.autoAdmit, isFalse);
      // Asked once. A prompt that comes back on every connection is a prompt
      // people learn to dismiss without reading, which is worse than not
      // having asked.
      expect(peer?.rememberAsked, isTrue);

      final asked = <PendingRemember>[];
      final subscription = service.rememberRequests.listen(asked.add);
      addTearDown(subscription.cancel);

      await client.disconnect();
      await dial();
      await client.waitUntilConnected().timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(asked, isEmpty);
    });

    test('a peer that never answers is still only asked about once', () async {
      // An older build sends nothing back, and so does one whose user walked
      // away mid-question. Asking again on every connection would be a worse
      // nag than the prompt this whole feature exists to remove.
      final held = service.connectionRequests.first;
      final question = service.rememberRequests.first;

      await dial();
      await service.approveConnection(
        await held.timeout(const Duration(seconds: 10)),
      );
      final pending = await question.timeout(const Duration(seconds: 10));

      await service.answerRemember(pending, agreed: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final peer = await trustStore.findById(phoneIdentity.id);
      expect(peer?.rememberAsked, isTrue);
      expect(
        peer?.autoAdmit,
        isFalse,
        reason: 'one yes is not an agreement, however long the other end takes',
      );

      final asked = <PendingRemember>[];
      final subscription = service.rememberRequests.listen(asked.add);
      addTearDown(subscription.cancel);

      await client.disconnect();
      await dial();
      await client.waitUntilConnected().timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(asked, isEmpty);
    });

    test('a device whose owner changed their mind is asked about again',
        () async {
      await storePhone(autoAdmit: true, rememberAsked: true);
      await service.setAutoAdmit(phoneIdentity.id, remember: false);

      final held = service.connectionRequests.first;
      await dial();
      final pending = await held.timeout(const Duration(seconds: 10));
      expect(pending.peerId, phoneIdentity.id);
    });
  });

  group('RememberDeviceDialog', () {
    testWidgets('names the device and says both ends have to agree',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RememberDeviceDialog(peerName: 'Pixel 9 Pro'),
          ),
        ),
      );

      expect(find.textContaining('Pixel 9 Pro'), findsWidgets);
      // The promise this dialog cannot keep on its own has to be stated, or a
      // user who is asked again next time is right to think it did nothing.
      expect(find.textContaining('Both devices have to'), findsOneWidget);
    });
  });
}
