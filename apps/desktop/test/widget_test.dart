import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/brand.dart';
import 'package:remotelink_desktop/src/app/providers.dart';
import 'package:remotelink_desktop/src/ui/home_screen.dart';
import 'package:rl_core/rl_core.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('renders the stopped service with no connected devices',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopHomeOverrides,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Not running'), findsOneWidget);
    expect(find.text('Connected devices'), findsOneWidget);
    expect(
      find.text(
        'No devices connected. Open Remote Link on your phone — it should find '
        'this computer automatically.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  group('when the service will not start', () {
    Future<void> pumpWithStartupError(
      WidgetTester tester,
      RemoteLinkError error,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...desktopHomeOverrides,
            desktopStatusProvider.overrideWith((ref) =>
                Future<DesktopStatus>.error(error, StackTrace.current)),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a second copy is told so, not shown a port number',
        (tester) async {
      // The screen this replaces said "could not listen on port 47811" — a
      // number the user cannot act on — and offered no way out of the window
      // except Activity Monitor.
      await pumpWithStartupError(
        tester,
        const TransportError(
          'already_running',
          'Remote Link is already running on this computer',
          retryable: false,
        ),
      );

      expect(find.text('$kProductName is already running'), findsOneWidget);
      expect(find.textContaining('47811'), findsNothing);
      expect(find.byType(BrandMark), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Close this window'),
        findsOneWidget,
      );
    });

    testWidgets('any other failure still reports what went wrong',
        (tester) async {
      await pumpWithStartupError(
        tester,
        const TransportError('bind_failed', 'could not listen on port 47811'),
      );

      expect(find.text('$kProductName could not start'), findsOneWidget);
      expect(find.text('could not listen on port 47811'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Close this window'),
        findsNothing,
        reason: 'quitting is only the right answer for a duplicate copy',
      );
    });
  });
}
