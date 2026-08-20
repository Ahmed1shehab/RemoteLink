import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/providers.dart';
import 'package:remotelink_desktop/src/domain/auto_start.dart';
import 'package:remotelink_desktop/src/domain/desktop_preferences.dart';

void main() {
  late Directory directory;
  late File file;
  late Directory launchAgents;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('rl-preferences');
    file = File('${directory.path}/settings.json');
    launchAgents = Directory('${directory.path}/LaunchAgents')
      ..createSync(recursive: true);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  group('the identifier the login item is filed under', () {
    // Renaming the bundle to `com.remotelink.*` for the App Store moved this
    // label with it. The old plist does not disappear because the name changed:
    // it sits in ~/Library/LaunchAgents pointing at a binary that has moved, so
    // launchd reports a failure at every login, for a login item the user
    // cannot find under the app's name because it is filed under `com.example`.
    AutoStart subject() => AutoStart(
          label: 'com.remotelink.desktop',
          executablePath: '/bin/true',
          launchAgentsDirectory: launchAgents,
          legacyLabels: const <String>['com.example.remotelinkDesktop'],
        );

    File legacyPlist() =>
        File('${launchAgents.path}/com.example.remotelinkDesktop.plist');

    test('an entry under a previous label is removed when enabling', () async {
      legacyPlist().writeAsStringSync('<plist>stale</plist>');

      await subject().enable();

      expect(legacyPlist().existsSync(), isFalse);
      expect(
        File('${launchAgents.path}/com.remotelink.desktop.plist').existsSync(),
        isTrue,
        reason: 'the new label is registered in its place',
      );
    });

    test('and when disabling, so opting out cleans up too', () async {
      // The path that would otherwise strand it forever: someone who turns the
      // setting off never calls enable again, so a sweep that only ran there
      // would leave the stale entry running at every login.
      legacyPlist().writeAsStringSync('<plist>stale</plist>');

      await subject().disable();

      expect(legacyPlist().existsSync(), isFalse);
    });

    test('a missing legacy entry is not an error', () async {
      await subject().enable();
      expect(legacyPlist().existsSync(), isFalse);
    });

    test('the shipped label matches the bundle identifier', () {
      // Both are read by the OS and neither is derived from the other, so
      // nothing but this catches them drifting apart.
      expect(kAutoStartLabel, 'com.remotelink.desktop');
      expect(kLegacyAutoStartLabels, contains('com.example.remotelinkDesktop'));
    });
  });

  group('DesktopPreferences', () {
    test('starts empty when there is no file yet', () async {
      final preferences = DesktopPreferences.open(file);

      expect(preferences.contains(PreferenceKeys.startAtLogin), isFalse);
      expect(
        preferences.boolean(PreferenceKeys.startAtLogin, orElse: true),
        isTrue,
      );
    });

    test('a written value survives a reopen', () async {
      final first = DesktopPreferences.open(file);
      await first.setBoolean(PreferenceKeys.startAtLogin, value: false);

      final second = DesktopPreferences.open(file);
      expect(second.contains(PreferenceKeys.startAtLogin), isTrue);
      expect(
        second.boolean(PreferenceKeys.startAtLogin, orElse: true),
        isFalse,
      );
    });

    test(
        'a damaged file falls back to defaults instead of refusing to '
        'start', () async {
      // A service the user depends on must not be held up by its own
      // settings file. Losing a preference is recoverable; failing to accept
      // connections because a JSON file has a stray byte is not.
      file.writeAsStringSync('{not json at all');

      final preferences = DesktopPreferences.open(file);
      expect(preferences.contains(PreferenceKeys.startAtLogin), isFalse);
      expect(
        preferences.boolean(PreferenceKeys.startAtLogin, orElse: true),
        isTrue,
      );
    });

    test(
        'a file holding something other than an object is treated as '
        'absent', () async {
      file.writeAsStringSync('[1, 2, 3]');

      final preferences = DesktopPreferences.open(file);
      expect(preferences.contains(PreferenceKeys.startAtLogin), isFalse);
    });

    test('a value of the wrong type falls back rather than crashing', () async {
      file.writeAsStringSync('{"startAtLogin": "yes please"}');

      final preferences = DesktopPreferences.open(file);
      expect(preferences.contains(PreferenceKeys.startAtLogin), isTrue);
      expect(
        preferences.boolean(PreferenceKeys.startAtLogin, orElse: false),
        isFalse,
      );
    });
  });

  group('reconcileAutoStart', () {
    test('registers on the very first launch and records that it did',
        () async {
      final preferences = DesktopPreferences.open(file);
      var enabled = 0;
      var disabled = 0;

      final result = await reconcileAutoStart(
        preferences: preferences,
        enable: () async => enabled++,
        disable: () async => disabled++,
      );

      expect(result, isTrue);
      expect(enabled, 1);
      expect(disabled, 0);
      // Recording it is what makes the *second* launch respect an answer of
      // no. Without this the choice can never be remembered.
      expect(preferences.contains(PreferenceKeys.startAtLogin), isTrue);
    });

    test('leaves a stored "off" off, launch after launch', () async {
      // The bug this replaces: registration ran unconditionally at every
      // launch, so turning the switch off lasted exactly until the next time
      // the app was opened — silently, and forever.
      final preferences = DesktopPreferences.open(file);
      await preferences.setBoolean(PreferenceKeys.startAtLogin, value: false);

      var enabled = 0;
      var disabled = 0;
      for (var launch = 0; launch < 3; launch++) {
        final result = await reconcileAutoStart(
          preferences: DesktopPreferences.open(file),
          enable: () async => enabled++,
          disable: () async => disabled++,
        );
        expect(result, isFalse);
      }

      expect(enabled, 0);
      expect(disabled, 3, reason: 'a stale login item must be removed');
    });

    test('re-registers a stored "on" so a moved executable keeps working',
        () async {
      // Every update and every `flutter run` puts the binary somewhere new,
      // and a login item pointing at a path that no longer exists fails at
      // each login with nothing to tell the user why.
      final preferences = DesktopPreferences.open(file);
      await preferences.setBoolean(PreferenceKeys.startAtLogin, value: true);

      var enabled = 0;
      for (var launch = 0; launch < 3; launch++) {
        await reconcileAutoStart(
          preferences: DesktopPreferences.open(file),
          enable: () async => enabled++,
          disable: () async {},
        );
      }

      expect(enabled, 3);
    });

    test('does not overwrite an answer it already has', () async {
      final preferences = DesktopPreferences.open(file);
      await preferences.setBoolean(PreferenceKeys.startAtLogin, value: false);

      await reconcileAutoStart(
        preferences: preferences,
        enable: () async {},
        disable: () async {},
      );

      final reopened = DesktopPreferences.open(file);
      expect(
        reopened.boolean(PreferenceKeys.startAtLogin, orElse: true),
        isFalse,
      );
    });
  });

  group('the switch behind the settings screen', () {
    /// A container wired to a temporary settings file and a login item that
    /// registers itself somewhere harmless.
    ///
    /// Driven from a plain `test` rather than a `testWidgets`: the notifier
    /// writes a file and registers with the OS, both of which are real
    /// asynchronous I/O, and a widget test runs on a fake clock that never
    /// advances it. What the *screen* does with this state is covered in
    /// `settings_screen_test.dart`, which needs no I/O to assert it.
    ProviderContainer containerForTest() {
      final container = ProviderContainer(
        overrides: <Override>[
          desktopPreferencesProvider
              .overrideWith((ref) => DesktopPreferences.open(file)),
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
      return container;
    }

    test('starts from the stored answer rather than the default', () async {
      final preferences = DesktopPreferences.open(file);
      await preferences.setBoolean(PreferenceKeys.startAtLogin, value: false);

      final container = containerForTest();
      expect(container.read(startAtLoginProvider), isTrue,
          reason: 'optimistic until the file has been read');

      // The read is asynchronous, so the switch corrects itself a moment later
      // rather than blocking the screen behind a disk read.
      await container.read(desktopPreferencesProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(startAtLoginProvider), isFalse);
    });

    test('turning it off is written down, not just drawn', () async {
      // The bug this guards: registration ran unconditionally at startup, so
      // the switch moved, looked right, and was undone by the next launch.
      final container = containerForTest();
      await container.read(startAtLoginProvider.notifier).set(enabled: false);

      final reopened = DesktopPreferences.open(file);
      expect(
        reopened.boolean(PreferenceKeys.startAtLogin, orElse: true),
        isFalse,
      );
    });

    test('turning it off removes the login item', () async {
      // Only macOS registers through a file this test can see; elsewhere the
      // assertion would be about an empty temporary directory.
      if (!Platform.isMacOS) return;
      final autoStart = AutoStart(
        label: 'com.example.test',
        executablePath: '/bin/true',
        launchAgentsDirectory: launchAgents,
      );
      await autoStart.enable();
      expect(await autoStart.isEnabled(), isTrue);

      final container = containerForTest();
      await container.read(startAtLoginProvider.notifier).set(enabled: false);

      expect(await autoStart.isEnabled(), isFalse);
    });

    test('turning it back on registers again', () async {
      if (!Platform.isMacOS) return;
      final container = containerForTest();
      await container.read(startAtLoginProvider.notifier).set(enabled: true);

      final autoStart = AutoStart(
        label: 'com.example.test',
        executablePath: '/bin/true',
        launchAgentsDirectory: launchAgents,
      );
      expect(await autoStart.isEnabled(), isTrue);
    });
  });
}
