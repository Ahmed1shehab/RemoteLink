import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/brand.dart';
import 'package:remotelink_desktop/src/app/providers.dart';
import 'package:remotelink_desktop/src/domain/auto_start.dart';
import 'package:remotelink_desktop/src/domain/desktop_preferences.dart';
import 'package:remotelink_desktop/src/ui/settings_screen.dart';

void main() {
  late Directory directory;
  late File settingsFile;
  late Directory launchAgents;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('rl-settings-screen');
    settingsFile = File('${directory.path}/settings.json');
    launchAgents = Directory('${directory.path}/LaunchAgents')
      ..createSync(recursive: true);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  /// Pumps the settings screen against a real preferences file in a temporary
  /// directory, and a login item that registers itself somewhere harmless.
  ///
  /// Deliberately not a fake preferences object: the thing worth testing is
  /// that a switch the user moves is still moved when they come back, and a
  /// fake store would agree with itself no matter what the real one did.
  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    final preferences = await DesktopPreferences.open(settingsFile);
    final container = ProviderContainer(
      overrides: <Override>[
        desktopPreferencesProvider.overrideWith((ref) async => preferences),
        autoStartProvider.overrideWithValue(
          AutoStart(
            label: 'com.example.test',
            executablePath: '/bin/true',
            launchAgentsDirectory: launchAgents,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Lets the notifier's real file write and `launchctl`-free registration
  /// finish.
  ///
  /// `pump` alone will not do it: the switch's `onChanged` is fire-and-forget by
  /// design — a settings toggle that awaits a disk write before it moves feels
  /// broken — so the work continues on the real event loop, which the widget
  /// tester's fake clock does not advance. This is the same shape as the helper
  /// in `desktop_service_test.dart`, for the same reason.
  Future<void> settleIo(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
  }

  testWidgets('names the product and its version', (tester) async {
    await pumpSettings(tester);

    expect(find.text(kProductName), findsWidgets);
    expect(find.text('Version $kAppVersion'), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);
  });

  testWidgets('start at login is on until the user says otherwise',
      (tester) async {
    await pumpSettings(tester);

    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Start when I log in'),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('turning it off is written down, not just drawn', (tester) async {
    // The bug this guards: registration used to be unconditional at startup, so
    // the switch moved, looked right, and was undone by the next launch.
    await pumpSettings(tester);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Start when I log in'));
    await settleIo(tester);

    final reopened = await DesktopPreferences.open(settingsFile);
    expect(
      reopened.boolean(PreferenceKeys.startAtLogin, orElse: true),
      isFalse,
    );
  });

  testWidgets('turning it off removes the login item', (tester) async {
    final autoStart = AutoStart(
      label: 'com.example.test',
      executablePath: '/bin/true',
      launchAgentsDirectory: launchAgents,
    );
    await autoStart.enable();
    // Only macOS registers through a file; elsewhere there is nothing here to
    // remove and the assertion below would be testing the temporary directory.
    if (!Platform.isMacOS) return;
    expect(await autoStart.isEnabled(), isTrue);

    await pumpSettings(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Start when I log in'));
    await settleIo(tester);

    expect(await autoStart.isEnabled(), isFalse);
  });

  testWidgets('turning it back on registers again', (tester) async {
    if (!Platform.isMacOS) return;
    final preferences = await DesktopPreferences.open(settingsFile);
    await preferences.setBoolean(PreferenceKeys.startAtLogin, value: false);

    await pumpSettings(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Start when I log in'));
    await settleIo(tester);

    final autoStart = AutoStart(
      label: 'com.example.test',
      executablePath: '/bin/true',
      launchAgentsDirectory: launchAgents,
    );
    expect(await autoStart.isEnabled(), isTrue);
  });

  testWidgets('the switch shows the stored answer, not the default',
      (tester) async {
    final preferences = await DesktopPreferences.open(settingsFile);
    await preferences.setBoolean(PreferenceKeys.startAtLogin, value: false);

    await pumpSettings(tester);
    await settleIo(tester);

    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Start when I log in'),
    );
    expect(toggle.value, isFalse);
  });

  testWidgets('says what the close button does, and where to quit',
      (tester) async {
    // The close button hiding rather than quitting looks exactly like a bug
    // when nobody says so, and the menu-bar item is the only way out.
    await pumpSettings(tester);

    expect(
      find.text('Closing this window keeps the service running'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        Platform.isMacOS ? 'menu bar' : 'notification area',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renames this computer', (tester) async {
    final container = await pumpSettings(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Studio Mac  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(container.read(deviceNameProvider), 'Studio Mac');
  });

  testWidgets('refuses to save an empty name', (tester) async {
    final container = await pumpSettings(tester);
    final before = container.read(deviceNameProvider);

    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // A blank name would leave the phone showing a nameless row, which is
    // worse than the hostname it started with.
    expect(container.read(deviceNameProvider), before);
  });
}
