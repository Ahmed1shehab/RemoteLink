import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/input/sensitivity_tutorial_dialog.dart';
import 'package:remotelink_mobile/src/features/input/touchpad_screen.dart';
import 'package:remotelink_mobile/src/features/settings/settings_screen.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

Widget _buildApp({
  bool tutorialSeen = true,
  Widget? home,
  SensitivityTutorialNotifier? notifier,
}) {
  final notif =
      notifier ?? SensitivityTutorialNotifier.forTesting(tutorialSeen);
  return ProviderScope(
    overrides: <Override>[
      identityProvider.overrideWith(
        (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
      ),
      clientStateProvider.overrideWith(
        (ref) => Stream<ClientState>.value(ClientState.connected),
      ),
      sensitivityTutorialSeenProvider.overrideWith(
        (ref) => notif,
      ),
    ],
    child: MaterialApp(
      home: home ?? const Scaffold(body: TouchpadSurfaceView()),
    ),
  );
}

void main() {
  testWidgets('SensitivityTutorialDialog renders content and steps',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        home: const Scaffold(
          body: SensitivityTutorialDialog(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Pointer Sensitivity'), findsWidgets);
    expect(find.text('Customise cursor speed'), findsOneWidget);
    expect(find.text('Open Settings'), findsWidgets);
    expect(find.text('Gestures & Scrolling'), findsOneWidget);
    expect(find.textContaining('Current sensitivity:'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('SensitivityTutorialDialog dismisses when Got it is pressed',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => SensitivityTutorialDialog.show(context, ref),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    expect(find.byType(SensitivityTutorialDialog), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.byType(SensitivityTutorialDialog), findsNothing);
  });

  testWidgets(
      'SensitivityTutorialDialog navigates to SettingsScreen when Open Settings is pressed',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => SensitivityTutorialDialog.show(context, ref),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    expect(find.byType(SensitivityTutorialDialog), findsOneWidget);

    final openSettingsFinder =
        find.widgetWithText(FilledButton, 'Open Settings');
    expect(openSettingsFinder, findsOneWidget);
    await tester.tap(openSettingsFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(SensitivityTutorialDialog), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('Touchpad button row includes sensitivity tutorial button',
      (tester) async {
    await tester.pumpWidget(_buildApp(tutorialSeen: true));
    await tester.pump();
    await tester.pump();

    final tutorialButton = find.byTooltip('Pointer sensitivity tutorial');
    expect(tutorialButton, findsOneWidget);

    await tester.tap(tutorialButton);
    await tester.pumpAndSettle();

    expect(find.byType(SensitivityTutorialDialog), findsOneWidget);
  });

  testWidgets(
      'Floating sensitivity banner appears when unseen and can be dismissed',
      (tester) async {
    final notifier = SensitivityTutorialNotifier.forTesting(false);
    await tester.pumpWidget(_buildApp(tutorialSeen: false, notifier: notifier));
    await tester.pump();
    await tester.pump();

    expect(find.text('Tap for tutorial or adjust in Settings'), findsOneWidget);
    expect(find.byTooltip('Dismiss hint'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss hint'));
    await tester.pumpAndSettle();

    expect(notifier.state, isTrue);
  });

  testWidgets('Floating sensitivity banner opens tutorial when tapped',
      (tester) async {
    await tester.pumpWidget(_buildApp(tutorialSeen: false));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Tap for tutorial or adjust in Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SensitivityTutorialDialog), findsOneWidget);
  });
}
