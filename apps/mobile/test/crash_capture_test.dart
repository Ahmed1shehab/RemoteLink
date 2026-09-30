import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/crash_capture.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/settings/settings_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';

import 'support/fakes.dart';

final class _FakeSystemClipboard {
  String? text;

  void install(TestWidgetsFlutterBinding binding) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.getData':
            return <String, Object?>{'text': text};
          case 'Clipboard.setData':
            text = (call.arguments as Map<Object?, Object?>)['text'] as String?;
            return null;
          default:
            return null;
        }
      },
    );
  }

  void remove(TestWidgetsFlutterBinding binding) =>
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mobile CrashCapture', () {
    test('installCrashCapture captures FlutterError', () {
      final memorySink = MemoryLogSink();
      final handler = CrashHandler(memorySink: memorySink);
      final uninstall = installCrashCapture(handler);
      addTearDown(uninstall);

      expect(handler.lastReport, isNull);

      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('test-flutter-error'),
          stack: StackTrace.current,
        ),
      );

      expect(handler.lastReport, isNotNull);
      expect(
          handler.lastReport!.error.toString(), contains('test-flutter-error'));
    });

    test('installCrashCapture captures PlatformDispatcher error', () {
      final memorySink = MemoryLogSink();
      final handler = CrashHandler(memorySink: memorySink);
      final uninstall = installCrashCapture(handler);
      addTearDown(uninstall);

      expect(handler.lastReport, isNull);

      PlatformDispatcher.instance.onError!(
        ArgumentError('test-platform-error'),
        StackTrace.current,
      );

      expect(handler.lastReport, isNotNull);
      expect(handler.lastReport!.error.toString(),
          contains('test-platform-error'));
    });

    test('handleIsolateError records unhandled isolate errors', () {
      final memorySink = MemoryLogSink();
      final handler = CrashHandler(memorySink: memorySink);

      expect(handler.lastReport, isNull);

      handleIsolateError(handler, <dynamic>[
        'test-isolate-crash',
        '#0 main (mobile_test.dart:1:1)',
      ]);

      expect(handler.lastReport, isNotNull);
      expect(
          handler.lastReport!.error.toString(), contains('test-isolate-crash'));
      expect(handler.lastReport!.stackTrace.toString(),
          contains('mobile_test.dart:1:1'));
    });

    test('uninstall restores previous handlers', () {
      final originalFlutter = FlutterError.onError;
      final originalPlatform = PlatformDispatcher.instance.onError;

      final memorySink = MemoryLogSink();
      final handler = CrashHandler(memorySink: memorySink);
      final uninstall = installCrashCapture(handler);

      expect(FlutterError.onError, isNot(equals(originalFlutter)));
      expect(
          PlatformDispatcher.instance.onError, isNot(equals(originalPlatform)));

      uninstall();

      expect(FlutterError.onError, equals(originalFlutter));
      expect(PlatformDispatcher.instance.onError, equals(originalPlatform));
    });
  });

  group('Mobile Settings Redaction Export', () {
    testWidgets('exporting logs redacts sensitive data before clipboard copy',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final clipboard = _FakeSystemClipboard()..install(tester.binding);
      addTearDown(() => clipboard.remove(tester.binding));

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
          scope: 'mobile.test',
          time: DateTime(2026, 8, 16, 12, 0, 0),
          message:
              'Connected to Living Room PC at 192.168.1.50 via /Users/ahmed/secret.pdf with key=abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
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

      // Scroll to Export Logs button so it is fully on-screen
      await tester.scrollUntilVisible(
        find.text('Export Logs'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Export Logs'));
      await tester.pumpAndSettle();

      expect(find.text('Export Logs'), findsOneWidget);

      await tester.tap(find.text('Export Logs'));
      await tester.pump();

      expect(clipboard.text, isNotNull);
      final logText = clipboard.text!;

      // Verify IP is redacted
      expect(logText, isNot(contains('192.168.1.50')));
      expect(logText, contains(LogRedactor.redactedIp));

      // Verify peer name is redacted
      expect(logText, isNot(contains('Living Room PC')));
      expect(logText, contains(LogRedactor.redactedPeerName));

      // Verify home path is redacted
      expect(logText, isNot(contains('/Users/ahmed/secret.pdf')));
      expect(logText, contains(LogRedactor.redactedPath));

      // Verify secret key is redacted
      expect(
        logText,
        isNot(contains(
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789')),
      );
      expect(logText, contains(LogRedactor.redactedKey));
    });

    testWidgets(
        'exporting logs includes persistent file sink logs and last crash report, redacted',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final clipboard = _FakeSystemClipboard()..install(tester.binding);
      addTearDown(() => clipboard.remove(tester.binding));

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

      final memoryBackend = MemoryLogFileBackend();
      final fileSink = FileLogSink(
        path: '/mobile/app.log',
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(fileSink.dispose);

      fileSink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'mobile.file',
          time: DateTime(2026, 8, 16, 12, 0, 0),
          message:
              'Persistent log connected to Living Room PC at 192.168.1.50 using /Users/ahmed/file.txt',
        ),
      );

      final crashHandler = CrashHandler();
      crashHandler.recordCrash(
        Exception(
            'Crash occurred for Living Room PC at /Users/ahmed/private.token'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...mobileSettingsOverrides(
              identity: identity,
              trustStore: trustStore,
              deviceName: 'My Test Phone',
            ),
            fileLogSinkProvider.overrideWithValue(fileSink),
            crashHandlerProvider.overrideWithValue(crashHandler),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Export Logs'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Export Logs'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export Logs'));
      await tester.pump();

      expect(clipboard.text, isNotNull);
      final logText = clipboard.text!;

      // Verify crash report is included
      expect(logText, contains('=== Remote Link Crash Report ==='));
      expect(logText, contains('Crash occurred for'));

      // Verify persistent file log is included
      expect(logText, contains('Persistent log connected to'));

      // Verify sensitive details are redacted across both sections
      expect(logText, isNot(contains('Living Room PC')));
      expect(logText, contains(LogRedactor.redactedPeerName));
      expect(logText, isNot(contains('192.168.1.50')));
      expect(logText, contains(LogRedactor.redactedIp));
      expect(logText, isNot(contains('/Users/ahmed/file.txt')));
      expect(logText, isNot(contains('/Users/ahmed/private.token')));
      expect(logText, contains(LogRedactor.redactedPath));
    });
  });
}
