import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/ui/home_screen.dart';

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
}
