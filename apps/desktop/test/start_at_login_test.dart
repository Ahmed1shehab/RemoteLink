import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/auto_start.dart';
import 'package:remotelink_desktop/src/domain/desktop_preferences.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('rl-preferences');
    file = File('${directory.path}/settings.json');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  group('DesktopPreferences', () {
    test('starts empty when there is no file yet', () async {
      final preferences = await DesktopPreferences.open(file);

      expect(preferences.contains(PreferenceKeys.startAtLogin), isFalse);
      expect(
        preferences.boolean(PreferenceKeys.startAtLogin, orElse: true),
        isTrue,
      );
    });

    test('a written value survives a reopen', () async {
      final first = await DesktopPreferences.open(file);
      await first.setBoolean(PreferenceKeys.startAtLogin, value: false);

      final second = await DesktopPreferences.open(file);
      expect(second.contains(PreferenceKeys.startAtLogin), isTrue);
      expect(
        second.boolean(PreferenceKeys.startAtLogin, orElse: true),
        isFalse,
      );
    });

    test('a damaged file falls back to defaults instead of refusing to '
        'start', () async {
      // A service the user depends on must not be held up by its own
      // settings file. Losing a preference is recoverable; failing to accept
      // connections because a JSON file has a stray byte is not.
      file.writeAsStringSync('{not json at all');

      final preferences = await DesktopPreferences.open(file);
      expect(preferences.contains(PreferenceKeys.startAtLogin), isFalse);
      expect(
        preferences.boolean(PreferenceKeys.startAtLogin, orElse: true),
        isTrue,
      );
    });

    test('a file holding something other than an object is treated as '
        'absent', () async {
      file.writeAsStringSync('[1, 2, 3]');

      final preferences = await DesktopPreferences.open(file);
      expect(preferences.contains(PreferenceKeys.startAtLogin), isFalse);
    });

    test('a value of the wrong type falls back rather than crashing', () async {
      file.writeAsStringSync('{"startAtLogin": "yes please"}');

      final preferences = await DesktopPreferences.open(file);
      expect(preferences.contains(PreferenceKeys.startAtLogin), isTrue);
      expect(
        preferences.boolean(PreferenceKeys.startAtLogin, orElse: false),
        isFalse,
      );
    });
  });

  group('reconcileAutoStart', () {
    test('registers on the very first launch and records that it did', () async {
      final preferences = await DesktopPreferences.open(file);
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
      final preferences = await DesktopPreferences.open(file);
      await preferences.setBoolean(PreferenceKeys.startAtLogin, value: false);

      var enabled = 0;
      var disabled = 0;
      for (var launch = 0; launch < 3; launch++) {
        final result = await reconcileAutoStart(
          preferences: await DesktopPreferences.open(file),
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
      final preferences = await DesktopPreferences.open(file);
      await preferences.setBoolean(PreferenceKeys.startAtLogin, value: true);

      var enabled = 0;
      for (var launch = 0; launch < 3; launch++) {
        await reconcileAutoStart(
          preferences: await DesktopPreferences.open(file),
          enable: () async => enabled++,
          disable: () async {},
        );
      }

      expect(enabled, 3);
    });

    test('does not overwrite an answer it already has', () async {
      final preferences = await DesktopPreferences.open(file);
      await preferences.setBoolean(PreferenceKeys.startAtLogin, value: false);

      await reconcileAutoStart(
        preferences: preferences,
        enable: () async {},
        disable: () async {},
      );

      final reopened = await DesktopPreferences.open(file);
      expect(
        reopened.boolean(PreferenceKeys.startAtLogin, orElse: true),
        isFalse,
      );
    });
  });
}
