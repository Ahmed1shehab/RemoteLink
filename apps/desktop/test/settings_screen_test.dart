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

  /// Puts an answer in the settings file without going near the event loop.
  ///
  /// Writing it through [DesktopPreferences.setBoolean] would be more faithful
  /// and would also hang: the write is real asynchronous file I/O, and a widget
  /// test's fake clock never advances it. The write path is exercised in
  /// `start_at_login_test.dart`, which runs without one.
  void seedStartAtLogin({required bool value}) =>
      settingsFile.writeAsStringSync('{"startAtLogin": $value}');

  /// Pumps the settings screen against a real preferences file in a temporary
  /// directory, and a login item that registers itself somewhere harmless.
  ///
  /// Deliberately not a fake preferences object: the thing worth testing is
  /// that a switch the user moves is still moved when they come back, and a
  /// fake store would agree with itself no matter what the real one did.
  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    final preferences = DesktopPreferences.open(settingsFile);
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

  testWidgets('moving the switch is reported straight away', (tester) async {
    // Only the state the screen reads back, not the disk. The write is real
    // file I/O on the real event loop, and a widget test runs on a fake clock
    // that never advances it — `start_at_login_test.dart` covers persistence
    // and the login item where there is no fake clock to deadlock against.
    final container = await pumpSettings(tester);
    expect(container.read(startAtLoginProvider), isTrue);

    await tester
        .tap(find.widgetWithText(SwitchListTile, 'Start when I log in'));
    await tester.pump();

    expect(container.read(startAtLoginProvider), isFalse);
    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Start when I log in'),
    );
    expect(toggle.value, isFalse,
        reason: 'the switch must move under the '
            'finger, not after a round trip to launchctl');
  });

  testWidgets('the switch shows the stored answer, not the default',
      (tester) async {
    seedStartAtLogin(value: false);

    await pumpSettings(tester);
    await tester.pump();

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
