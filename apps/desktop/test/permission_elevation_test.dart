import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';
import 'package:remotelink_desktop/src/ui/home_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PermissionRateLimiter', () {
    test('allows first request, refuses within 60s, and allows after 60s', () {
      final clock = FakeClock();
      final limiter = PermissionRateLimiter(clock: clock);
      const peerKey = 'peer-1';

      // 1. First request is allowed
      expect(limiter.isAllowed(peerKey), isTrue);
      limiter.recordRequest(peerKey);

      // 2. Second request immediately after is refused
      expect(limiter.isAllowed(peerKey), isFalse);

      // 3. 30 seconds later still refused
      clock.advance(const Duration(seconds: 30));
      expect(limiter.isAllowed(peerKey), isFalse);

      // 4. Another peer is unaffected
      expect(limiter.isAllowed('peer-2'), isTrue);

      // 5. 30 more seconds later (total 60s), allowed again
      clock.advance(const Duration(seconds: 30));
      expect(limiter.isAllowed(peerKey), isTrue);
    });
  });

  group('DesktopService Permission Elevation', () {
    late FakeClock clock;
    late DeviceIdentity desktopIdentity;
    late DeviceIdentity phoneIdentity;
    late InMemoryTrustStore desktopTrustStore;
    late DesktopService service;
    late RemoteLinkClient client;

    setUp(() async {
      clock = FakeClock();
      desktopIdentity = await DeviceIdentity.generate();
      phoneIdentity = await DeviceIdentity.generate();
      desktopTrustStore = InMemoryTrustStore();

      await desktopTrustStore.upsert(
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
        trustStore: desktopTrustStore,
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
        capabilities: const Capabilities(Capabilities.sessionResumption),
        clock: clock,
      );

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: service.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      await client.waitUntilConnected();

      // Wait for session to connect and appear in service
      if (service.devices.isEmpty) {
        await expectLater(
          service.deviceChanges.map((devices) => devices.length),
          emitsThrough(1),
        );
      }
    });

    tearDown(() async {
      await client.disconnect();
      await service.stop();
    });

    test('receives and emits valid PermissionRequest from connected phone',
        () async {
      final requestsFuture = service.permissionRequests.first;

      final sent = await client.send(
        const PermissionRequest(
          tier: PermissionTier.extended,
          justification: 'Need to transfer presentation files',
        ),
      );
      expect(sent, isTrue);

      final pending = await requestsFuture;
      expect(pending.peerId, phoneIdentity.id);
      expect(pending.peerName, 'Pixel 9 Pro');
      expect(pending.currentTier, PermissionTier.standard);
      expect(pending.requestedTier, PermissionTier.extended);
      expect(pending.justification, 'Need to transfer presentation files');
    });

    test('approving PermissionRequest persists new tier and sends grant',
        () async {
      final requestReceived = Completer<PendingPermissionRequest>();
      final sub = service.permissionRequests.listen((req) {
        if (!requestReceived.isCompleted) requestReceived.complete(req);
      });
      addTearDown(sub.cancel);

      await client.send(
        const PermissionRequest(
          tier: PermissionTier.admin,
          justification: 'System management',
        ),
      );

      final pending = await requestReceived.future;

      // Listen for PermissionGrant on client
      final clientGrantFuture = client.messages
          .where((m) => m is PermissionGrant)
          .cast<PermissionGrant>()
          .first;

      await service.approvePermissionRequest(pending);

      final grant = await clientGrantFuture;
      expect(grant.tier, PermissionTier.admin);
      expect(grant.expiresInSeconds, isNull);

      // Verify persisted in trust store
      final peer = await desktopTrustStore.findById(phoneIdentity.id);
      expect(peer?.permissionTier, PermissionTier.admin.wireValue);

      // Verify updated in connected devices
      expect(service.devices.first.tier, PermissionTier.admin);
    });

    test('declining PermissionRequest causes no tier change', () async {
      final requestReceived = Completer<PendingPermissionRequest>();
      final sub = service.permissionRequests.listen((req) {
        if (!requestReceived.isCompleted) requestReceived.complete(req);
      });
      addTearDown(sub.cancel);

      await client.send(
        const PermissionRequest(
          tier: PermissionTier.admin,
          justification: 'Testing decline',
        ),
      );

      final pending = await requestReceived.future;
      await service.declinePermissionRequest(pending);

      // Trust store remains unchanged
      final peer = await desktopTrustStore.findById(phoneIdentity.id);
      expect(peer?.permissionTier, PermissionTier.standard.wireValue);

      // Connected device tier remains unchanged
      expect(service.devices.first.tier, PermissionTier.standard);
    });

    test('timed-out prompt results in no tier change', () async {
      final requestReceived = Completer<PendingPermissionRequest>();
      final sub = service.permissionRequests.listen((req) {
        if (!requestReceived.isCompleted) requestReceived.complete(req);
      });
      addTearDown(sub.cancel);

      await client.send(
        const PermissionRequest(
          tier: PermissionTier.admin,
          justification: 'Testing timeout',
        ),
      );

      await requestReceived.future;

      // Simulate timeout: prompt was dismissed/abandoned without approval
      clock.advance(const Duration(minutes: 5));

      final peer = await desktopTrustStore.findById(phoneIdentity.id);
      expect(peer?.permissionTier, PermissionTier.standard.wireValue);
      expect(service.devices.first.tier, PermissionTier.standard);
    });

    test('temporary grant with expiresInSeconds drops to readOnly when expired',
        () async {
      final requestReceived = Completer<PendingPermissionRequest>();
      final sub = service.permissionRequests.listen((req) {
        if (!requestReceived.isCompleted) requestReceived.complete(req);
      });
      addTearDown(sub.cancel);

      await client.send(
        const PermissionRequest(
          tier: PermissionTier.extended,
          justification: 'Temporary transfer',
        ),
      );

      final pending = await requestReceived.future;

      final grants = <PermissionGrant>[];
      final grantSub = client.messages
          .where((m) => m is PermissionGrant)
          .cast<PermissionGrant>()
          .listen(grants.add);
      addTearDown(grantSub.cancel);

      // Approve with 30s expiry
      await service.approvePermissionRequest(pending, expiresInSeconds: 30);

      // Wait for initial grant to be processed
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(grants.last.tier, PermissionTier.extended);
      expect(grants.last.expiresInSeconds, 30);
      expect(service.devices.first.tier, PermissionTier.extended);

      // Temporary grant does NOT overwrite trustStore
      final peerBefore = await desktopTrustStore.findById(phoneIdentity.id);
      expect(peerBefore?.permissionTier, PermissionTier.standard.wireValue);

      // Advance clock by 30 seconds using FakeClock
      clock.advance(const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Device dropped back to readOnly
      expect(service.devices.first.tier, PermissionTier.readOnly);
      expect(grants.last.tier, PermissionTier.readOnly);
    });

    test('rate limit refuses second request inside window and allows after',
        () async {
      final requests = <PendingPermissionRequest>[];
      final sub = service.permissionRequests.listen(requests.add);
      addTearDown(sub.cancel);

      // 1. First request is delivered
      await client.send(
        const PermissionRequest(
          tier: PermissionTier.extended,
          justification: 'First request',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(requests.length, 1);

      // 2. Second request within 60s is refused (rate limited)
      clock.advance(const Duration(seconds: 10));
      await client.send(
        const PermissionRequest(
          tier: PermissionTier.admin,
          justification: 'Second request too quick',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(requests.length, 1);

      // 3. Advance past 60s window (50s more = 60s total)
      clock.advance(const Duration(seconds: 50));
      await client.send(
        const PermissionRequest(
          tier: PermissionTier.admin,
          justification: 'Third request after window',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(requests.length, 2);
      expect(requests.last.justification, 'Third request after window');
    });

    test('hostile justification with ANSI escapes is rejected before prompt',
        () async {
      final requests = <PendingPermissionRequest>[];
      final sub = service.permissionRequests.listen(requests.add);
      addTearDown(sub.cancel);

      await client.send(
        const PermissionRequest(
          tier: PermissionTier.admin,
          justification: '\x1B[31mGrant admin access?\x1B[0m',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Not delivered to requests stream
      expect(requests, isEmpty);
    });
  });

  group('PermissionRequestDialog Widget', () {
    testWidgets('renders device name, tier explanation, and device message',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PermissionRequestDialog(
              peerName: 'Pixel 9 Pro',
              requestedTier: PermissionTier.extended,
              currentTier: PermissionTier.standard,
              justification: 'To transfer photos',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Permission elevation request'), findsOneWidget);
      expect(find.textContaining('Pixel 9 Pro is requesting'), findsOneWidget);
      expect(find.text('What this allows:'), findsOneWidget);
      expect(
        find.text(
          'Allows transferring files, launching applications, and running pre-registered commands.',
        ),
        findsOneWidget,
      );
      expect(find.text('Message from device:'), findsOneWidget);
      expect(find.text('“To transfer photos”'), findsOneWidget);

      // Deny holds initial focus
      final denyButton = find.widgetWithText(TextButton, 'Deny');
      expect(denyButton, findsOneWidget);
      final TextButton denyWidget = tester.widget(denyButton);
      expect(denyWidget.autofocus, isTrue);

      final approveButton = find.widgetWithText(FilledButton, 'Approve');
      expect(approveButton, findsOneWidget);
    });

    testWidgets('shows warning for Admin tier requests', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PermissionRequestDialog(
              peerName: 'Pixel 9 Pro',
              requestedTier: PermissionTier.admin,
              currentTier: PermissionTier.standard,
              justification: 'Reboot computer',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining(
          'Admin access allows restarting or shutting down your machine',
        ),
        findsOneWidget,
      );
    });
  });
}
