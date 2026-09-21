import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/splash_screen.dart';
import 'package:remotelink_mobile/src/app/theme.dart';

import 'support/fakes.dart';

void main() {
  Widget app({required bool disableAnimations}) => ProviderScope(
        overrides: mobileDeviceListOverrides(discoveryOperational: true),
        child: MaterialApp(
          theme: remoteLinkTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: const LaunchScreen(),
        ),
      );

  testWidgets('hands over to the device list after the launch cap', (
    tester,
  ) async {
    await tester.pumpWidget(app(disableAnimations: false));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    expect(find.text('Devices'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('launch-screen-overlay')),
        findsNothing);
  });

  testWidgets('reduced motion hands over without starting an animation', (
    tester,
  ) async {
    await tester.pumpWidget(app(disableAnimations: true));
    await tester.pump();

    expect(find.text('Devices'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('launch-screen-overlay')),
        findsNothing);
  });
}
