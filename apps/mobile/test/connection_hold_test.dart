import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/devices/connection_hold.dart';
import 'package:rl_transport/rl_transport.dart';

/// What the phone shows while a computer decides whether to let it in.
///
/// The screen matters as much as the gate does. A held session drops every
/// message outside the handshake and trust subsystems, so a phone that showed
/// nothing would show a touchpad that moves no cursor and a Send button whose
/// files go nowhere — and the user would have no way to learn that the answer
/// is on the other device.
void main() {
  Widget host(Stream<ClientState> states) => ProviderScope(
        overrides: <Override>[
          clientStateProvider.overrideWith((ref) => states),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WaitingForApprovalDialog()),
        ),
      );

  testWidgets('names the device being waited on and offers a way out',
      (tester) async {
    await tester.pumpWidget(
      host(Stream<ClientState>.value(ClientState.awaitingApproval)),
    );
    await tester.pump();

    expect(find.text('Waiting to be let in'), findsOneWidget);
    // No name has arrived from the peer and no target is set in this harness,
    // so the copy has to stand up without one rather than reading "null is
    // asking whether to allow this connection".
    expect(
      find.textContaining('asking whether to allow this connection'),
      findsOneWidget,
    );
    expect(find.text('Stop waiting'), findsOneWidget);
  });

  testWidgets('takes itself away when the wait ends', (tester) async {
    final states = StreamController<ClientState>.broadcast();
    addTearDown(states.close);

    // Pushed as a route, because popping itself is the behaviour under test and
    // a dialog built directly into the tree has nothing to pop.
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          clientStateProvider.overrideWith((ref) => states.stream),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const WaitingForApprovalDialog(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    states.add(ClientState.awaitingApproval);
    await tester.tap(find.text('open'));
    // Pumped by hand rather than settled: the dialog holds a spinner, and a
    // spinner never settles.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Waiting to be let in'), findsOneWidget);

    states.add(ClientState.connected);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Left up, it would sit over a connection that is now perfectly usable.
    expect(find.text('Waiting to be let in'), findsNothing);
  });
}
