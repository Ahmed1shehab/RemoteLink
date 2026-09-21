import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/input/touchpad_screen.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

Widget _buildTouchpad({bool connected = true}) {
  return ProviderScope(
    overrides: <Override>[
      identityProvider.overrideWith(
        (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
      ),
      clientStateProvider.overrideWith(
        (ref) => Stream<ClientState>.value(
          connected ? ClientState.connected : ClientState.idle,
        ),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: TouchpadSurfaceView(),
      ),
    ),
  );
}

void main() {
  testWidgets('TouchpadSurfaceView paints resting and dynamic dot layers',
      (tester) async {
    await tester.pumpWidget(_buildTouchpad(connected: true));
    await tester.pump();
    await tester.pump();

    expect(find.byType(TouchpadSurfaceView), findsOneWidget);
    // CustomPaint widgets for dot field and dynamic glow are present
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Touchpad handles touch drag and fade dissipation cleanly',
      (tester) async {
    await tester.pumpWidget(_buildTouchpad(connected: true));
    await tester.pump();
    await tester.pump();

    final center = tester.getCenter(find.byType(TouchpadSurfaceView));

    // Simulate pointer down and pan
    final gesture = await tester.startGesture(center, pointer: 1);
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Drag pointer
    await gesture.moveBy(const Offset(30, -20));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Another move
    await gesture.moveBy(const Offset(-10, 40));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Release pointer - starts fade dissipation
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Settle the fade-out animation
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Touchpad handles multi-touch gestures without exceptions',
      (tester) async {
    await tester.pumpWidget(_buildTouchpad(connected: true));
    await tester.pump();
    await tester.pump();

    final center = tester.getCenter(find.byType(TouchpadSurfaceView));

    // Two fingers down
    final finger1 =
        await tester.startGesture(center - const Offset(40, 0), pointer: 1);
    final finger2 =
        await tester.startGesture(center + const Offset(40, 0), pointer: 2);
    await tester.pump();

    // Move both fingers (scroll gesture)
    await finger1.moveBy(const Offset(0, 30));
    await finger2.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Lift finger 1
    await finger1.up();
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Lift finger 2
    await finger2.up();
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
