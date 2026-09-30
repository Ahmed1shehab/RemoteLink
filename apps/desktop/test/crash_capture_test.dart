import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/crash_capture.dart';
import 'package:remotelink_desktop/src/app/providers.dart';
import 'package:remotelink_desktop/src/ui/diagnostics_screen.dart';
import 'package:rl_core/rl_core.dart';

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

  group('Desktop CrashCapture', () {
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
        '#0 main (test.dart:1:1)',
      ]);

      expect(handler.lastReport, isNotNull);
      expect(
          handler.lastReport!.error.toString(), contains('test-isolate-crash'));
      expect(
          handler.lastReport!.stackTrace.toString(), contains('test.dart:1:1'));
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

  group('Desktop Diagnostics Redaction Export', () {
    testWidgets('copying full diagnostics and logs redacts sensitive data',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final clipboard = _FakeSystemClipboard()..install(tester.binding);
      addTearDown(() => clipboard.remove(tester.binding));

      final logSink = MemoryLogSink();
      logSink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'test',
          time: DateTime(2026, 8, 16, 12, 0, 0),
          message:
              'Connected to peer 192.168.1.50 from /Users/ahmed/secret.pdf with key=abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...desktopHomeOverrides,
            memoryLogSinkProvider.overrideWithValue(logSink),
          ],
          child: const MaterialApp(
            home: DiagnosticsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Tap "Copy All"
      await tester.tap(find.text('Copy All'));
      await tester.pump();

      expect(clipboard.text, isNotNull);
      final fullText = clipboard.text!;

      // Verify IPs are redacted
      expect(fullText, isNot(contains('192.168.1.100')));
      expect(fullText, isNot(contains('192.168.1.50')));
      expect(fullText, contains(LogRedactor.redactedIp));

      // Verify peer names are redacted
      expect(fullText, isNot(contains('Pixel 8 Pro')));
      expect(fullText, contains(LogRedactor.redactedPeerName));

      // Verify home paths and keys in system logs are redacted
      expect(fullText, isNot(contains('/Users/ahmed/secret.pdf')));
      expect(
        fullText,
        isNot(contains(
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789')),
      );
      expect(fullText, contains(LogRedactor.redactedKey));

      // Tap "Copy Logs"
      await tester.tap(find.text('Copy Logs'));
      await tester.pump();

      expect(clipboard.text, isNotNull);
      final logText = clipboard.text!;

      expect(logText, isNot(contains('192.168.1.50')));
      expect(logText, contains(LogRedactor.redactedIp));
      expect(logText, isNot(contains('/Users/ahmed/secret.pdf')));
      expect(logText, contains(LogRedactor.redactedKey));
    });

    testWidgets(
        'copying full diagnostics and logs includes persistent file sink logs and last crash report, redacted',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final clipboard = _FakeSystemClipboard()..install(tester.binding);
      addTearDown(() => clipboard.remove(tester.binding));

      final memoryBackend = MemoryLogFileBackend();
      final fileSink = FileLogSink(
        path: '/desktop/app.log',
        backend: memoryBackend,
        flushInterval: null,
      );
      addTearDown(fileSink.dispose);

      fileSink.write(
        LogRecord(
          level: LogLevel.info,
          scope: 'desktop.file',
          time: DateTime(2026, 8, 16, 12, 0, 0),
          message:
              'Persistent log connected to 192.168.1.50 for /Users/ahmed/invoice.pdf with key=1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
      );

      final crashHandler = CrashHandler();
      crashHandler.recordCrash(
        Exception(
            'Desktop fatal crash accessing /Users/ahmed/desktop_key.token for Pixel 8 Pro'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...desktopHomeOverrides,
            fileLogSinkProvider.overrideWithValue(fileSink),
            crashHandlerProvider.overrideWithValue(crashHandler),
          ],
          child: const MaterialApp(
            home: DiagnosticsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Tap "Copy All"
      await tester.tap(find.text('Copy All'));
      await tester.pump();

      expect(clipboard.text, isNotNull);
      final fullText = clipboard.text!;

      // Crash report and file log present in Copy All
      expect(fullText, contains('--- Last Crash Report ---'));
      expect(fullText, contains('Desktop fatal crash'));
      expect(fullText, contains('Persistent log connected to'));

      // Redacted in Copy All
      expect(fullText, isNot(contains('192.168.1.50')));
      expect(fullText, contains(LogRedactor.redactedIp));
      expect(fullText, isNot(contains('/Users/ahmed/invoice.pdf')));
      expect(fullText, isNot(contains('/Users/ahmed/desktop_key.token')));
      expect(fullText, contains(LogRedactor.redactedPath));
      expect(fullText, isNot(contains('Pixel 8 Pro')));
      expect(fullText, contains(LogRedactor.redactedPeerName));

      // Tap "Copy Logs"
      await tester.tap(find.text('Copy Logs'));
      await tester.pump();

      expect(clipboard.text, isNotNull);
      final logText = clipboard.text!;

      expect(logText, contains('=== Remote Link Crash Report ==='));
      expect(logText, contains('Desktop fatal crash'));
      expect(logText, contains('Persistent log connected to'));
      expect(logText, isNot(contains('192.168.1.50')));
      expect(logText, contains(LogRedactor.redactedIp));
      expect(logText, isNot(contains('/Users/ahmed/invoice.pdf')));
      expect(logText, isNot(contains('/Users/ahmed/desktop_key.token')));
      expect(logText, contains(LogRedactor.redactedPath));
    });
  });
}
