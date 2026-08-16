import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/devices/device_list_screen.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('renders the empty state when no computers are discovered',
      (tester) async {
    await _pumpDeviceList(tester, discoveryOperational: true);

    expect(find.text('Computers'), findsOneWidget);
    expect(find.text('Looking for computers'), findsOneWidget);
    expect(find.text('Connect by address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains when automatic discovery is unavailable',
      (tester) async {
    await _pumpDeviceList(tester, discoveryOperational: false);

    expect(
      find.text('This device can’t search automatically'),
      findsOneWidget,
    );
    expect(
      find.textContaining('iPhones need a special Apple permission'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDeviceList(
  WidgetTester tester, {
  required bool discoveryOperational,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: mobileDeviceListOverrides(
        discoveryOperational: discoveryOperational,
      ),
      child: const MaterialApp(home: DeviceListScreen()),
    ),
  );

  // Flush the overridden FutureProvider and the derived stream providers.
  await tester.pump();
  await tester.pump();
}
