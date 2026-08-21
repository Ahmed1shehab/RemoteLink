import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/brand.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/control/control_screen.dart';
import 'package:remotelink_mobile/src/features/devices/device_list_screen.dart';
import 'package:remotelink_mobile/src/features/devices/link_service.dart';
import 'package:remotelink_mobile/src/features/input/pointer_controller.dart';
import 'package:remotelink_mobile/src/features/settings/settings_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

void main() {
  group('SettingsScreen', () {
    testWidgets('renders every section', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final identity = await DeviceIdentity.generate();
      final trustStore = InMemoryTrustStore();
      await trustStore.upsert(
        TrustedPeer(
          id: const DeviceId('0123456789ABCDEFGHJKMNPQRS'),
          publicKey: Uint8List(32),
          name: 'Living Room PC',
          platform: PlatformKind.windows,
          pairedAt: DateTime.now(),
          permissionTier: 2,
          lastAddress: '192.168.1.50',
        ),
      );

      final logSink = MemoryLogSink();
      logSink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'test.scope',
          message: 'Test log entry',
          time: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileSettingsOverrides(
            identity: identity,
            trustStore: trustStore,
            deviceName: 'My Test Phone',
            memoryLogSink: logSink,
          ),
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Section 1: THIS PHONE
      expect(find.text('This Phone'), findsOneWidget);
      expect(find.text('My Test Phone'), findsOneWidget);
      expect(find.text(identity.id.value), findsOneWidget);
      expect(find.text('Public-key fingerprint'), findsOneWidget);

      // Section 2: PAIRED COMPUTERS
      expect(find.text('Paired Computers'), findsOneWidget);
      expect(find.text('Living Room PC'), findsOneWidget);
      expect(find.textContaining('Last seen: 192.168.1.50'), findsOneWidget);

      // Section 3: TOUCHPAD
      expect(find.text('Touchpad'), findsOneWidget);
      expect(find.text('Pointer sensitivity'), findsOneWidget);
      expect(find.text('Natural scrolling'), findsOneWidget);
      expect(find.text('Tap to click'), findsOneWidget);

      // Section 4: CLIPBOARD
      expect(find.text('Clipboard'), findsOneWidget);
      expect(find.text('Sync from computer'), findsOneWidget);
      expect(find.text('Sync to computer'), findsOneWidget);
      expect(
        find.textContaining('Why does my phone need to be open?'),
        findsOneWidget,
      );

      // Section 5: BACKGROUND — absent, and that is the assertion. These tests
      // run on the host, where there is no service to run, and a switch
      // offered where nothing can honour it is worse than no switch.
      expect(find.text('Background'), findsNothing);

      // Section 6: DIAGNOSTICS
      expect(find.text('Diagnostics'), findsOneWidget);
      expect(find.text('Connection state'), findsOneWidget);
      expect(find.text('Round-trip time'), findsOneWidget);
      expect(find.text('Discovery route'), findsOneWidget);
      expect(find.text('Export Logs'), findsOneWidget);

      // Section 7: ABOUT
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Remote Link'), findsOneWidget);
      expect(find.text('Version $kAppVersion'), findsOneWidget);
      expect(find.text('Licenses'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the background section appears where a service can run',
        (tester) async {
      // The switch is offered on Android and nowhere else, so this stands in
      // for the platform the host is not.
      //
      // Tall surface, like the section sweep above: the settings list mounts
      // lazily, and a section below the fold is a section `find.text` cannot
      // see at all.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final identity = await DeviceIdentity.generate();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...mobileSettingsOverrides(
              identity: identity,
              trustStore: InMemoryTrustStore(),
              deviceName: 'My Test Phone',
            ),
            linkServiceProvider.overrideWithValue(const _SupportedLinkService()),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Background'), findsOneWidget);
      expect(find.text('Stay connected in the background'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('Remote Link keeps stopping?'),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.tap(find.text('Remote Link keeps stopping?'));
      await tester.pumpAndSettle();

      // The phones this exists for, named rather than linked: their autostart
      // screens have no public intent to open.
      expect(find.textContaining('Xiaomi'), findsOneWidget);
      expect(find.text('Open battery settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the diagnostics filter row fits a narrow phone',
        (tester) async {
      // 720 physical pixels at 2x is a common budget phone, and it is where the
      // log-filter row ran 49 pixels past the card and painted overflow stripes
      // across the export button. The default 800-logical-pixel test surface
      // is wide enough to hide it, so the width has to be stated here.
      tester.view.physicalSize = const Size(720, 1640);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final identity = await DeviceIdentity.generate();
      final trustStore = InMemoryTrustStore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileSettingsOverrides(
            identity: identity,
            trustStore: trustStore,
            deviceName: 'My Test Phone',
            memoryLogSink: MemoryLogSink(),
          ),
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.dragUntilVisible(
        find.text('Export Logs'),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      expect(find.text('Export Logs'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'an invalid rename is rejected and leaves the stored name unchanged',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = InMemoryIdentityStore();
      await storage.write('remotelink.device.name', 'Initial Phone Name');

      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileSettingsOverrides(
            identityStore: storage,
            deviceName: 'Initial Phone Name',
          ),
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Initial Phone Name'), findsOneWidget);

      // Tap the rename button
      final renameButton = find.byTooltip('Rename this phone');
      expect(renameButton, findsOneWidget);
      await tester.tap(renameButton);
      await tester.pumpAndSettle();

      expect(find.text('Rename this phone'), findsOneWidget);

      // Enter an invalid name (e.g. whitespace only or > 64 chars)
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Error message is displayed and dialog stays open
      expect(
        find.text(
          'Invalid name: 1–64 characters, no control codes or line breaks.',
        ),
        findsOneWidget,
      );

      // Cancel the dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Stored name is unchanged
      expect(
          await storage.read('remotelink.device.name'), 'Initial Phone Name');
      expect(find.text('Initial Phone Name'), findsOneWidget);
    });

    testWidgets('a valid rename updates the stored name and UI',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = InMemoryIdentityStore();
      await storage.write('remotelink.device.name', 'Old Name');

      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileSettingsOverrides(
            identityStore: storage,
            deviceName: 'Old Name',
          ),
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      final renameButton = find.byTooltip('Rename this phone');
      await tester.tap(renameButton);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Pixel 9 Pro');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(await storage.read('remotelink.device.name'), 'Pixel 9 Pro');
      expect(find.text('Pixel 9 Pro'), findsOneWidget);
    });

    testWidgets('"forget" requires confirmation and only then removes the peer',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = InMemoryIdentityStore();
      final trustStore = InMemoryTrustStore();
      const peerId = DeviceId('0123456789ABCDEFGHJKMNPQRS');
      final peer = TrustedPeer(
        id: peerId,
        publicKey: Uint8List(32),
        name: 'Work iMac',
        platform: PlatformKind.macos,
        pairedAt: DateTime.now(),
        permissionTier: 2,
        lastAddress: '192.168.1.120',
      );
      await trustStore.upsert(peer);
      await persistTrustStore(trustStore, storage);

      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileSettingsOverrides(
            identityStore: storage,
            trustStore: trustStore,
          ),
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Work iMac'), findsOneWidget);

      // Tap forget icon button
      final forgetButton = find.byTooltip('Forget Work iMac');
      expect(forgetButton, findsOneWidget);
      await tester.tap(forgetButton);
      await tester.pumpAndSettle();

      // Confirmation dialog appears
      expect(find.text('Forget Work iMac?'), findsOneWidget);
      expect(
        find.textContaining(
            'This will remove this computer from your trusted list'),
        findsOneWidget,
      );

      // 1. Cancel does NOT remove the peer
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await trustStore.findById(peerId), isNotNull);
      expect(find.text('Work iMac'), findsOneWidget);

      // 2. Tap forget again and confirm
      await tester.tap(forgetButton);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
      await tester.pumpAndSettle();

      // Peer is removed from trust store
      expect(await trustStore.findById(peerId), isNull);
      expect(find.text('Work iMac'), findsNothing);
      expect(
        find.text(
            'No paired computers yet. Pair with a computer on your Wi-Fi network to start.'),
        findsOneWidget,
      );
    });

    testWidgets('a touchpad setting round-trips through storage',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = InMemoryIdentityStore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileSettingsOverrides(
            identityStore: storage,
          ),
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Toggle natural scrolling switch
      final naturalScrollingFinder = find.widgetWithText(
        SwitchListTile,
        'Natural scrolling',
      );
      expect(naturalScrollingFinder, findsOneWidget);

      // Initial value is true
      SwitchListTile tile = tester.widget(naturalScrollingFinder);
      expect(tile.value, isTrue);

      // Tap switch inside the tile
      final switchFinder = find.descendant(
        of: naturalScrollingFinder,
        matching: find.byType(Switch),
      );
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump();

      tile = tester.widget(naturalScrollingFinder);
      expect(tile.value, isFalse);

      // Verify written to storage
      final storedJson = await storage.read('remotelink.settings.pointer');
      expect(storedJson, isNotNull);
      final decoded = jsonDecode(storedJson!) as Map<String, dynamic>;
      expect(decoded['naturalScrolling'], isFalse);

      // Verify that PointerSettings deserialization preserves it
      final loadedSettings = PointerSettings.fromJson(decoded);
      expect(loadedSettings.naturalScrolling, isFalse);

      // Verify behavior in PointerController
      final controller = PointerController(settings: loadedSettings);
      final scroll = controller.translateScroll(const Offset(0, 40));
      // With natural scrolling FALSE, direction is -1
      expect(scroll.linesY, -1);
    });

    testWidgets('clipboard settings toggle and persist', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = InMemoryIdentityStore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileSettingsOverrides(
            identityStore: storage,
          ),
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      final syncFromDesktopFinder = find.widgetWithText(
        SwitchListTile,
        'Sync from computer',
      );
      expect(syncFromDesktopFinder, findsOneWidget);

      final switchFinder = find.descendant(
        of: syncFromDesktopFinder,
        matching: find.byType(Switch),
      );
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump();

      final storedJson = await storage.read('remotelink.settings.clipboard');
      expect(storedJson, isNotNull);
      final decoded = jsonDecode(storedJson!) as Map<String, dynamic>;
      expect(decoded['syncFromDesktop'], isFalse);
    });

    testWidgets('reachable from DeviceListScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileDeviceListOverrides(
            discoveryOperational: true,
          ),
          child: const MaterialApp(home: DeviceListScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      final settingsButton = find.byTooltip('Settings');
      expect(settingsButton, findsOneWidget);

      await tester.tap(settingsButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('This Phone'), findsOneWidget);
    });

    testWidgets('reachable from ControlScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith(
              (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
            ),
            clientStateProvider.overrideWith(
              (ref) => Stream<ClientState>.value(ClientState.connected),
            ),
            systemStatusProvider.overrideWith(
              (ref) => const Stream<SystemStatus?>.empty(),
            ),
            connectionQualityProvider.overrideWith(
              (ref) => const Stream<ConnectionQuality>.empty(),
            ),
          ],
          child: const MaterialApp(home: ControlScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      final settingsButton = find.byTooltip('Settings');
      expect(settingsButton, findsOneWidget);

      await tester.tap(settingsButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('This Phone'), findsOneWidget);
    });

    testWidgets(
        'permission elevation dialog displays current tier and explanation of requested tier',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final identity = await DeviceIdentity.generate();
      final trustStore = InMemoryTrustStore();
      await trustStore.upsert(
        TrustedPeer(
          id: const DeviceId('0123456789ABCDEFGHJKMNPQRS'),
          publicKey: Uint8List(32),
          name: 'Living Room PC',
          platform: PlatformKind.windows,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.standard.wireValue,
          lastAddress: '192.168.1.50',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileSettingsOverrides(
            identity: identity,
            trustStore: trustStore,
            deviceName: 'My Test Phone',
          ),
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Find permission button for Living Room PC
      final permButton = find.byTooltip('Permissions for Living Room PC');
      expect(permButton, findsOneWidget);

      await tester.tap(permButton);
      await tester.pumpAndSettle();

      // Dialog is displayed
      expect(find.text('Permissions · Living Room PC'), findsOneWidget);
      expect(find.text('Current Permission Tier'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(
        find.text(
          'Allows sending keyboard and mouse input, synchronizing clipboard, '
          'controlling media, viewing this screen, and transferring files.',
        ),
        findsOneWidget,
      );

      // What requested tier allows box
      expect(find.text('What Extended allows:'), findsOneWidget);
      expect(
        find.text(
          'Allows launching applications and running pre-registered commands.',
        ),
        findsOneWidget,
      );

      // Justification field
      expect(
        find.widgetWithText(TextField, 'Reason / Justification (optional)'),
        findsOneWidget,
      );

      // Cancel closes the dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Permissions · Living Room PC'), findsNothing);
    });
  });
}

/// A link service that claims a platform which can run one.
final class _SupportedLinkService implements LinkService {
  const _SupportedLinkService();

  @override
  bool get isSupported => true;

  @override
  Future<void> start({
    required String title,
    required String body,
    required String disconnectLabel,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<bool> openBatterySettings() async => true;

  @override
  Stream<void> get disconnectRequests => const Stream<void>.empty();
}
