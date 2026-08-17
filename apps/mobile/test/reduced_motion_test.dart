import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/motion.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/app/theme.dart';
import 'package:remotelink_mobile/src/features/input/touchpad_screen.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

/// "Reduce Motion" on iOS, "Remove animations" on Android.
///
/// Flutter surfaces the setting but applies it to nothing, so every animation
/// has to opt in and each one is its own possible miss. These check the two
/// that move without being asked: the touchpad's state cross-fade and the
/// route transitions.
void main() {
  Widget touchpad({required bool disableAnimations}) => ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: const Scaffold(body: TouchpadSurfaceView()),
        ),
      );

  testWidgets('the touchpad surface still animates by default', (tester) async {
    await tester.pumpWidget(touchpad(disableAnimations: false));
    await tester.pump();

    // The other half of the assertion below: this has to be a real animation
    // for switching it off to mean anything.
    final animated = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(animated.duration, const Duration(milliseconds: 200));
  });

  testWidgets('the touchpad surface does not animate under reduced motion',
      (tester) async {
    await tester.pumpWidget(touchpad(disableAnimations: true));
    await tester.pump();

    final animated = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    // Zero rather than shorter: the setting asks for the animation to be
    // removed, not hurried.
    expect(animated.duration, Duration.zero);
  });

  test('every route transition honours the setting', () {
    // The largest movement in the app, and the one the framework will not drop
    // on its own. Wrapping every platform's builder rather than listing the
    // ones we happen to ship on means a new target platform cannot arrive with
    // an unwrapped transition.
    final builders =
        remoteLinkTheme(Brightness.light).pageTransitionsTheme.builders;

    expect(builders, isNotEmpty);
    for (final entry in builders.entries) {
      expect(
        entry.value,
        isA<ReducedMotionPageTransitionsBuilder>(),
        reason: '${entry.key} would still animate under reduced motion',
      );
    }
  });

  test('the wrapper is applied to the dark theme too', () {
    final builders =
        remoteLinkTheme(Brightness.dark).pageTransitionsTheme.builders;
    for (final entry in builders.entries) {
      expect(entry.value, isA<ReducedMotionPageTransitionsBuilder>());
    }
  });

  testWidgets('the setting reaches widget code through the extension',
      (tester) async {
    // What `_ConnectionBar` reads to decide between an indeterminate bar and a
    // still one. The bar itself is private to the control screen, which builds
    // five tabs at once and several other progress indicators with it, so this
    // asserts the signal rather than pattern-matching on which spinner is
    // whose.
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Text('${context.prefersReducedMotion}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('true'), findsOneWidget);
  });
}
