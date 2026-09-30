import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/devices/device_list_screen.dart';
import 'package:remotelink_mobile/src/features/host/host_providers.dart';
import 'package:remotelink_mobile/src/features/settings/settings_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

void main() {
  test('desktop rename validates and updates only the trusted peer', () async {
    final identity = await DeviceIdentity.generate();
    final otherIdentity = await DeviceIdentity.generate();
    final store = InMemoryTrustStore();
    await store.upsert(TrustedPeer(
      id: identity.id,
      publicKey: identity.publicKey,
      name: 'Old computer',
      platform: PlatformKind.macos,
      pairedAt: DateTime.utc(2025),
      permissionTier: PermissionTier.standard.wireValue,
    ));
    await store.upsert(TrustedPeer(
      id: otherIdentity.id,
      publicKey: otherIdentity.publicKey,
      name: 'Other computer',
      platform: PlatformKind.windows,
      pairedAt: DateTime.utc(2025),
      permissionTier: PermissionTier.standard.wireValue,
    ));

    expect(
        await applyDesktopRename(store, identity.id, 'New computer'), isTrue);
    expect((await store.findById(identity.id))?.name, 'New computer');
    expect((await store.findById(otherIdentity.id))?.name, 'Other computer');
    for (final invalid in <String>[
      'x' * 1000,
      '\u200b\u200b',
      'bad\u001b[31m',
    ]) {
      expect(await applyDesktopRename(store, identity.id, invalid), isFalse);
    }
    expect((await store.findById(identity.id))?.name, 'New computer');
    await store.dispose();
  });

  group('authenticated rename direction', () {
    late DeviceIdentity phoneIdentity;
    late DeviceIdentity desktopIdentity;
    late InMemoryTrustStore desktopStore;
    late InMemoryTrustStore phoneStore;
    late InMemoryIdentityStore storage;
    late RemoteLinkServer server;
    late RemoteLinkClient client;
    late List<DeviceRename> received;
    late StreamSubscription<Message> subscription;

    setUp(() async {
      phoneIdentity = await DeviceIdentity.generate();
      desktopIdentity = await DeviceIdentity.generate();
      desktopStore = InMemoryTrustStore();
      phoneStore = InMemoryTrustStore();
      storage = InMemoryIdentityStore();
      await desktopStore.upsert(TrustedPeer(
        id: phoneIdentity.id,
        publicKey: phoneIdentity.publicKey,
        name: 'My Phone',
        platform: PlatformKind.android,
        pairedAt: DateTime.now(),
        permissionTier: PermissionTier.standard.wireValue,
      ));
      await phoneStore.upsert(TrustedPeer(
        id: desktopIdentity.id,
        publicKey: desktopIdentity.publicKey,
        name: 'Office Mac',
        platform: PlatformKind.macos,
        pairedAt: DateTime.now(),
        permissionTier: PermissionTier.standard.wireValue,
      ));
      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: const Capabilities(Capabilities.mouse),
        trustStore: desktopStore,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();
      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(Capabilities.mouse),
        clock: SystemClock(),
      );
      await client.connect(ConnectionTarget(
        host: '127.0.0.1',
        port: server.boundPort,
        deviceId: desktopIdentity.id,
        serverPublicKey: desktopIdentity.publicKey,
      ));
      await client.waitUntilConnected();
      received = <DeviceRename>[];
      subscription = server.sessions.single.session.messages
          .where((message) => message is DeviceRename)
          .listen((message) => received.add(message as DeviceRename));
    });

    tearDown(() async {
      await subscription.cancel();
      await client.dispose();
      await server.stop();
      await phoneStore.dispose();
      await desktopStore.dispose();
    });

    test('phone self-rename sends its own name', () async {
      final container = ProviderContainer(overrides: [
        identityStoreProvider.overrideWith((ref) async => storage),
        clientProvider.overrideWith((ref) async => client),
      ]);
      addTearDown(container.dispose);
      await container.read(clientProvider.future);

      expect(
          await container.read(deviceNameProvider.notifier).setDeviceName(
                '  My New Phone  ',
              ),
          isNull);
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (received.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(received.single.name, 'My New Phone');
      expect(await storage.read('remotelink.device.name'), 'My New Phone');
    });

    testWidgets('settings computer alias stays on the phone', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: mobileSettingsOverrides(
          identity: phoneIdentity,
          identityStore: storage,
          trustStore: phoneStore,
          client: client,
        ),
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Rename Office Mac'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Desk Alias');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(
          (await phoneStore.findById(desktopIdentity.id))?.name, 'Desk Alias');
      expect(received, isEmpty);
    });

    testWidgets('device list computer alias stays on the phone',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...mobileDeviceListOverrides(
            discoveryOperational: false,
            trustStore: phoneStore,
            client: client,
            identityStore: storage,
          ),
          connectedDeviceIdsProvider.overrideWith((ref) => <DeviceId>{}),
        ],
        child: const MaterialApp(home: DeviceListScreen()),
      ));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Rename computer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Desk Alias');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(
          (await phoneStore.findById(desktopIdentity.id))?.name, 'Desk Alias');
      expect(received, isEmpty);
    });
  });
}
