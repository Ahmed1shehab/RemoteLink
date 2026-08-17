import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/input/touchpad_screen.dart';
import 'package:remotelink_mobile/src/features/keyboard/hardware_keyboard_view.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart' as proto;
import 'package:rl_transport/rl_transport.dart';

/// The screens with fixed-size boxes, rendered at the text sizes the platform
/// settings actually offer.
///
/// A `RenderFlex` overflow is a thrown exception in a test build, so
/// `takeException()` is a real assertion here rather than a formality: these
/// fail on the code as it was.
///
/// 2.0 is not an arbitrary ceiling. iOS's largest accessibility text size is
/// about 3.1× body, Android's is 2.0×; 2.0 is where the rendered keyboard's
/// fixed keycaps and the touchpad's fixed 72px button row broke, and past 1.3
/// keycap labels are scaled down to fit by design (see `kKeyCapMaxTextScale`).
void main() {
  Widget scaled(Widget child, double scale) => MaterialApp(
        builder: (context, built) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: built!,
        ),
        home: Scaffold(body: child),
      );

  Widget keyboard() => HardwareKeyboardView(
        platform: PlatformKind.windows,
        modifiers: proto.Modifiers.none,
        capsLock: false,
        enabled: true,
        onKey: (_) {},
        onModifier: (_) {},
        onSwitchToText: () {},
      );

  Widget touchpad(WidgetTester tester, double scale) => ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
        ],
        child: scaled(const TouchpadSurfaceView(), scale),
      );

  for (final scale in <double>[1.0, 1.3, 1.6, 2.0]) {
    testWidgets('the rendered keyboard lays out at ${scale}x text',
        (tester) async {
      await tester.pumpWidget(scaled(keyboard(), scale));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the keyboard overflowed at ${scale}x text',
      );
    });

    testWidgets('the touchpad lays out at ${scale}x text', (tester) async {
      await tester.pumpWidget(touchpad(tester, scale));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the touchpad overflowed at ${scale}x text',
      );
    });

    testWidgets('the pointer controls lay out at ${scale}x text',
        (tester) async {
      await tester.pumpWidget(touchpad(tester, scale));
      await tester.pump();

      await tester.tap(find.byTooltip('Show pointer controls'));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the pointer controls overflowed at ${scale}x text',
      );
    });
  }

  testWidgets('every keycap is still present and legible at 2x text',
      (tester) async {
    await tester.pumpWidget(scaled(keyboard(), 2));
    await tester.pump();

    // Not merely "did not throw": the failure mode this guards against is a
    // label clipped to something that reads as a different key. 'F11' cut to
    // 'F1' sends a different keystroke, and there is no way to tell.
    for (final label in <String>['F11', 'F12', 'alt gr', 'esc', 'caps']) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: 'the "$label" keycap went missing at 2x text',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short window scrolls the keyboard rather than dropping a row',
      (tester) async {
    // A landscape phone at a large text size: not enough height for six rows
    // at a legible size. The bottom row is where the modifiers live, so losing
    // it silently is worse than scrolling.
    tester.view.physicalSize = const Size(1600, 620);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(scaled(keyboard(), 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('ctrl'), findsOneWidget);
  });
}
