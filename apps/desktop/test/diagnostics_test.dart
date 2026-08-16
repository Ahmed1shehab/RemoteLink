import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/ui/diagnostics_screen.dart';
import 'package:remotelink_desktop/src/ui/home_screen.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
      'renders diagnostics panel with counters, addresses, and backend reasons',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopHomeOverrides,
        child: const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 1. Dispatcher counters
    expect(find.text('Command Dispatcher'), findsOneWidget);
    expect(find.text('Applied'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('Denied'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Unsupported'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // 2. Service state and LAN addresses
    expect(find.text('Service & Network'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('192.168.1.100:41234'), findsOneWidget);
    expect(find.text('10.0.0.5:41234'), findsOneWidget);
    expect(find.text('test-device-id'), findsOneWidget);

    // 3. Backend availability and reasons
    expect(find.text('Backend Availability'), findsOneWidget);
    expect(find.text('Input injection'), findsOneWidget);
    expect(find.text('Clipboard sync'), findsOneWidget);
    expect(find.text('Media control'), findsOneWidget);
    expect(
      find.text(
        'RemoteLink needs Accessibility permission. Enable it in System Settings.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Media control is not supported on this platform'),
      findsOneWidget,
    );

    // 4. Connected devices
    expect(find.text('Connected Devices (1)'), findsOneWidget);
    expect(find.text('Pixel 8 Pro'), findsOneWidget);
    expect(find.textContaining('192.168.1.50'), findsOneWidget);
    expect(find.textContaining('12.5 ms'), findsOneWidget);

    // 5. System logs
    expect(find.text('System Logs'), findsOneWidget);
    expect(find.textContaining('desktop service started'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('can navigate to diagnostics from home screen', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopHomeOverrides,
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final diagnosticsButton = find.byTooltip('Diagnostics');
    expect(diagnosticsButton, findsOneWidget);

    await tester.tap(diagnosticsButton);
    await tester.pumpAndSettle();

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Command Dispatcher'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('192.168.1.100:41234'), findsOneWidget);
    expect(
      find.text(
        'RemoteLink needs Accessibility permission. Enable it in System Settings.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('copies full diagnostics report and logs to clipboard',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopHomeOverrides,
        child: const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Tap "Copy All"
    final copyAllButton = find.text('Copy All');
    expect(copyAllButton, findsOneWidget);
    await tester.tap(copyAllButton);
    await tester.pump();

    expect(find.text('Full diagnostics copied to clipboard'), findsOneWidget);

    // Tap "Copy Logs"
    final copyLogsButton = find.text('Copy Logs');
    expect(copyLogsButton, findsOneWidget);
    await tester.tap(copyLogsButton);
    await tester.pump();

    expect(find.textContaining('Copied 4 log records'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters logs by log level', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopHomeOverrides,
        child: const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Showing 4 of 4'), findsOneWidget);

    // Open dropdown and select Error
    await tester.tap(find.text('All Levels'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Error (≥ error)').last);
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 4'), findsOneWidget);
    expect(find.textContaining('permission missing error'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
