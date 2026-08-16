import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/devices/device_list_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('renders the empty state when no computers are discovered',
      (tester) async {
    await _pumpDeviceList(tester, discoveryOperational: true);

    expect(find.text('Computers'), findsOneWidget);
    expect(find.text('Looking for computers'), findsOneWidget);
    expect(find.text('Connect by address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains when automatic discovery is unavailable',
      (tester) async {
    await _pumpDeviceList(tester, discoveryOperational: false);

    expect(
      find.text('This device can’t search automatically'),
      findsOneWidget,
    );
    expect(
      find.textContaining('iPhones need a special Apple permission'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a revoked computer shows an explicit fresh-pairing action',
      (tester) async {
    late DeviceIdentity desktopIdentity;
    late InMemoryTrustStore desktopTrust;
    late InMemoryTrustStore mobileTrust;
    late RemoteLinkServer server;
    late RemoteLinkClient client;

    await tester.runAsync(() async {
      final phoneIdentity = await DeviceIdentity.generate();
      desktopIdentity = await DeviceIdentity.generate();
      desktopTrust = InMemoryTrustStore();
      await desktopTrust.upsert(
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

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: const Capabilities(Capabilities.mouse),
        trustStore: desktopTrust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(Capabilities.mouse),
        clock: SystemClock(),
      );
      final failed = client.states.firstWhere(
        (state) => state == ClientState.failed,
      );
      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
          displayName: 'Office Mac',
        ),
      );
      await failed.timeout(const Duration(seconds: 10));
      for (var i = 0; i < 100 && client.session != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      mobileTrust = InMemoryTrustStore();
      await mobileTrust.upsert(
        TrustedPeer(
          id: desktopIdentity.id,
          publicKey: desktopIdentity.publicKey,
          name: 'Office Mac',
          platform: PlatformKind.macos,
          pairedAt: DateTime.now(),
          permissionTier: 2,
          lastAddress: '127.0.0.1',
        ),
      );
    });
    addTearDown(
      () => tester.runAsync(() async {
        await client.dispose();
        await server.stop();
        await desktopTrust.dispose();
        await mobileTrust.dispose();
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: mobileDeviceListOverrides(
          discoveryOperational: true,
          trustStore: mobileTrust,
          client: client,
          discovered: <DiscoveredDevice>[
            DiscoveredDevice(
              beacon: Beacon(
                kind: BeaconKind.announce,
                deviceId: desktopIdentity.id,
                name: 'Office Mac',
                platform: PlatformKind.macos,
                servicePort: server.boundPort,
                protocolVersion: kProtocolVersion,
                publicKeyFingerprint: desktopIdentity.publicKey.sublist(0, 8),
                capabilities: const Capabilities(Capabilities.mouse),
              ),
              address: '127.0.0.1',
              firstSeen: DateTime.now(),
              lastSeen: DateTime.now(),
            ),
          ],
        ),
        child: const MaterialApp(home: DeviceListScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('This computer removed your access'), findsOneWidget);
    expect(find.text('Pair again'), findsOneWidget);
  });

  testWidgets('allows renaming a paired computer', (tester) async {
    final desktopIdentity = await DeviceIdentity.generate();
    final mobileTrust = InMemoryTrustStore();
    await mobileTrust.upsert(
      TrustedPeer(
        id: desktopIdentity.id,
        publicKey: desktopIdentity.publicKey,
        name: 'Original Mac',
        platform: PlatformKind.macos,
        pairedAt: DateTime.now(),
        permissionTier: 2,
        lastAddress: '192.168.1.100',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: mobileDeviceListOverrides(
          discoveryOperational: true,
          trustStore: mobileTrust,
        ),
        child: const MaterialApp(home: DeviceListScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Original Mac'), findsOneWidget);
    final editButton = find.byIcon(Icons.edit_outlined);
    expect(editButton, findsOneWidget);

    await tester.tap(editButton);
    await tester.pumpAndSettle();

    expect(find.text('Rename computer'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Renamed MacBook Pro');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updatedPeer = await mobileTrust.findById(desktopIdentity.id);
    expect(updatedPeer?.name, 'Renamed MacBook Pro');
  });
}

Future<void> _pumpDeviceList(
  WidgetTester tester, {
  required bool discoveryOperational,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: mobileDeviceListOverrides(
        discoveryOperational: discoveryOperational,
      ),
      child: const MaterialApp(home: DeviceListScreen()),
    ),
  );

  // Flush the overridden FutureProvider and the derived stream providers.
  await tester.pump();
  await tester.pump();
}
