import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/devices/device_list_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

void main() {
  const macText = '00:1A:2B:3C:4D:5E';

  /// A paired computer that discovery cannot currently see — the only state in
  /// which waking one is a sensible thing to offer.
  Future<InMemoryTrustStore> sleepingComputer(DeviceIdentity identity) async {
    final trust = InMemoryTrustStore();
    await trust.upsert(
      TrustedPeer(
        id: identity.id,
        publicKey: identity.publicKey,
        name: 'Office Mac',
        platform: PlatformKind.macos,
        pairedAt: DateTime.now(),
        permissionTier: 2,
        lastAddress: '192.168.1.100',
      ),
    );
    return trust;
  }

  InMemoryIdentityStore storageWithMac(DeviceIdentity identity) =>
      InMemoryIdentityStore(<String, String>{
        kWakeAddressesKey:
            jsonEncode(<String, String>{identity.id.value: macText}),
      });

  Future<void> pump(
    WidgetTester tester, {
    required TrustStore trustStore,
    required IdentityStore identityStore,
    RecordingWakeOnLanSender? sender,
    List<DiscoveredDevice> discovered = const <DiscoveredDevice>[],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: mobileDeviceListOverrides(
          discoveryOperational: true,
          trustStore: trustStore,
          identityStore: identityStore,
          discovered: discovered,
          wakeSender: sender,
        ),
        child: const MaterialApp(home: DeviceListScreen()),
      ),
    );
    // The stored addresses load asynchronously, like the trust store above it.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('offers Wake for a paired computer that is not answering',
      (tester) async {
    final identity = await DeviceIdentity.generate();
    final sender = RecordingWakeOnLanSender();

    await pump(
      tester,
      trustStore: await sleepingComputer(identity),
      identityStore: storageWithMac(identity),
      sender: sender,
    );

    expect(find.text('Office Mac'), findsOneWidget);
    expect(find.text('Wake'), findsOneWidget);

    await tester.tap(find.text('Wake'));
    await tester.pumpAndSettle();

    // Every requirement stated before the packet goes out, because none of them
    // can be detected afterwards: a wake that failed looks exactly like a wake
    // that worked from this side.
    expect(find.textContaining('Broadcasts a wake-up packet to $macText'),
        findsOneWidget);
    expect(find.textContaining('Ethernet cable'), findsOneWidget);
    expect(
      find.textContaining('Most Wi-Fi adapters cannot be woken this way'),
      findsOneWidget,
    );
    expect(find.textContaining('BIOS or UEFI'), findsOneWidget);
    expect(find.textContaining('Wake on Magic Packet'), findsOneWidget);
    expect(find.textContaining('cannot tell you whether this worked'),
        findsOneWidget);

    // Nothing is sent until the user says so.
    expect(sender.sent, isEmpty);

    await tester.tap(find.text('Send wake-up'));
    await tester.pumpAndSettle();

    expect(sender.sent, hasLength(1));
    expect(sender.sent.single.mac, MacAddress.tryParse(macText));
    expect(
      sender.sent.single.lastKnownAddress,
      '192.168.1.100',
      reason: 'the stored address is what the directed broadcast is derived '
          'from; without it only the limited broadcast is attempted',
    );
    expect(find.textContaining('Wake-up sent to Office Mac'), findsOneWidget);
  });

  testWidgets('cancelling the dialog sends nothing', (tester) async {
    final identity = await DeviceIdentity.generate();
    final sender = RecordingWakeOnLanSender();

    await pump(
      tester,
      trustStore: await sleepingComputer(identity),
      identityStore: storageWithMac(identity),
      sender: sender,
    );

    await tester.tap(find.text('Wake'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(sender.sent, isEmpty);
  });

  testWidgets('says so when the network refuses the broadcast', (tester) async {
    final identity = await DeviceIdentity.generate();
    final sender = RecordingWakeOnLanSender()..delivers = false;

    await pump(
      tester,
      trustStore: await sleepingComputer(identity),
      identityStore: storageWithMac(identity),
      sender: sender,
    );

    await tester.tap(find.text('Wake'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send wake-up'));
    await tester.pumpAndSettle();

    // Reporting "sent" after the OS refused every datagram would be the same
    // silent no-op the button exists to avoid.
    expect(
      find.textContaining('refused the wake-up broadcast'),
      findsOneWidget,
    );
  });

  testWidgets('no Wake button when the computer never reported an address',
      (tester) async {
    final identity = await DeviceIdentity.generate();

    await pump(
      tester,
      trustStore: await sleepingComputer(identity),
      // No stored address: an older desktop build, or one whose platform would
      // not give up a MAC.
      identityStore: InMemoryIdentityStore(),
      sender: RecordingWakeOnLanSender(),
    );

    expect(find.text('Office Mac'), findsOneWidget);
    expect(
      find.text('Wake'),
      findsNothing,
      reason: 'a Wake button with nothing to address the packet to would be a '
          'button that silently does nothing',
    );
  });

  testWidgets('no Wake button for a computer that is answering right now',
      (tester) async {
    final identity = await DeviceIdentity.generate();

    await pump(
      tester,
      trustStore: await sleepingComputer(identity),
      identityStore: storageWithMac(identity),
      sender: RecordingWakeOnLanSender(),
      discovered: <DiscoveredDevice>[
        DiscoveredDevice(
          beacon: Beacon(
            kind: BeaconKind.announce,
            deviceId: identity.id,
            name: 'Office Mac',
            platform: PlatformKind.macos,
            servicePort: kDefaultServicePort,
            protocolVersion: kProtocolVersion,
            publicKeyFingerprint: identity.publicKey.sublist(0, 8),
            capabilities: const Capabilities(Capabilities.mouse),
          ),
          address: '192.168.1.100',
          firstSeen: DateTime.now(),
          lastSeen: DateTime.now(),
        ),
      ],
    );

    expect(find.text('Office Mac'), findsOneWidget);
    expect(find.text('Wake'), findsNothing);
  });

  group('WakeAddressesNotifier', () {
    test('reads back what a desktop reported, and ignores nonsense', () async {
      final storage = InMemoryIdentityStore(<String, String>{
        kWakeAddressesKey: jsonEncode(<String, String>{
          'ABCDEFGHJKMNPQRSTVWXYZ0123': macText,
          'ABCDEFGHJKMNPQRSTVWXYZ0124': 'not-a-mac',
        }),
      });
      final container = ProviderContainer(
        overrides: <Override>[
          identityStoreProvider.overrideWith((ref) async => storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(wakeAddressesProvider.notifier);
      // The load is kicked off in the constructor; let it finish.
      await Future<void>.delayed(Duration.zero);

      expect(
        notifier.addressFor(const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123')),
        MacAddress.tryParse(macText),
      );
      expect(
        notifier.addressFor(const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0124')),
        isNull,
      );
      expect(notifier.addressFor(null), isNull);
    });

    test('persists a newly reported address', () async {
      final storage = InMemoryIdentityStore();
      final container = ProviderContainer(
        overrides: <Override>[
          identityStoreProvider.overrideWith((ref) async => storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(wakeAddressesProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await notifier.remember(
        const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123'),
        MacAddress.tryParse(macText)!,
      );

      expect(
        storage.values[kWakeAddressesKey],
        contains(macText),
      );
    });
  });
}
