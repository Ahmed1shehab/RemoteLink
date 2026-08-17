import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/ui/home_screen.dart';
import 'package:remotelink_desktop/src/ui/pairing_code.dart';

import 'support/fakes.dart';
import 'support/semantics.dart';

/// The desktop side of RL-703: the pairing dialog's digits, where the keyboard
/// starts in a dialog, and the window's tab order.
void main() {
  group('the pairing code', () {
    Widget wrap(String digits) => MaterialApp(
          home: Scaffold(
            body: Center(child: PairingCodeDisplay(digits: digits)),
          ),
        );

    testWidgets('announces the whole code as separated digit words',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap('482159'));
      await tester.pump();

      // Word for word what the phone says. Both sides format it with
      // `spokenDigits` from `rl_core` precisely so that a user comparing the
      // two by ear is comparing the codes and not two turns of phrase.
      expectAnnouncedAs(
        tester,
        'Security code: four, eight, two, one, five, nine',
      );

      handle.dispose();
    });

    testWidgets('never announces the digits as a single number',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap('482159'));
      await tester.pump();

      for (final label in semanticsLabels(tester)) {
        expect(
          RegExp(r'\d\d').hasMatch(label),
          isFalse,
          reason: 'the label "$label" contains adjacent digits, which a screen '
              'reader announces as one number',
        );
      }

      handle.dispose();
    });

    testWidgets('exposes each digit as its own node, with its position',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap('482159'));
      await tester.pump();

      expectAnnouncedAs(tester, 'Digit 1 of 6: four');
      expectAnnouncedAs(tester, 'Digit 3 of 6: two');
      expectAnnouncedAs(tester, 'Digit 6 of 6: nine');

      handle.dispose();
    });
  });

  group('the pairing dialog', () {
    testWidgets('shows the code accessibly inside the real dialog',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PairingDialog(
              peerName: 'Ahmed’s phone',
              shortAuthenticationString: '482159',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Pair this device?'), findsOneWidget);
      expect(find.text('Ahmed’s phone wants to control this computer.'),
          findsOneWidget);
      expectAnnouncedAs(
        tester,
        'Security code: four, eight, two, one, five, nine',
      );

      handle.dispose();
    });

    testWidgets('starts the keyboard on Deny, not on approve', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PairingDialog(
              peerName: 'Ahmed’s phone',
              shortAuthenticationString: '482159',
            ),
          ),
        ),
      );
      await tester.pump();

      // The dialog appears unprompted the moment a stranger's phone reaches
      // this machine. Whichever button holds focus is the one a stray Return
      // presses, so it must not be the one that hands over control.
      final deny = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Deny'),
          matching: find.byType(TextButton),
        ),
      );
      expect(deny.autofocus, isTrue);

      final approve = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('The numbers match'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(approve.autofocus, isFalse);
    });

    testWidgets('Return on the untouched dialog denies', (tester) async {
      bool? answer;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  answer = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const PairingDialog(
                      peerName: 'Ahmed’s phone',
                      shortAuthenticationString: '482159',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Nothing has been read and nothing has been compared: pressing Return
      // here has to be the safe answer. Denying is recoverable — the phone
      // simply asks again — and approving is not.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(answer, isFalse);
    });

    testWidgets('Tab reaches the approve button', (tester) async {
      bool? answer;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  answer = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const PairingDialog(
                      peerName: 'Ahmed’s phone',
                      shortAuthenticationString: '482159',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Safe by default must not mean unreachable: the user who *has* compared
      // the digits still has to be able to approve without a mouse.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(answer, isTrue);
    });
  });

  group('the home screen', () {
    testWidgets('pins tab order to the order the page is read in',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: desktopHomeOverrides,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The body declares an explicit order rather than relying on the
      // geometric default, which reshuffled when the permission banner
      // appeared and pushed everything down.
      final group = tester.widget<FocusTraversalGroup>(
        find.byType(FocusTraversalGroup).last,
      );
      expect(group.policy, isA<OrderedTraversalPolicy>());

      // The declared order has to agree with where the sections actually are.
      // A section added in the wrong place in the list would still tab in
      // numeric order — silently, and only noticeably with a screen reader or
      // a keyboard.
      final orders = <(double, double)>[];
      for (final element in find.byType(FocusTraversalOrder).evaluate()) {
        final widget = element.widget as FocusTraversalOrder;
        final order = widget.order as NumericFocusOrder;
        orders.add((tester.getTopLeft(find.byWidget(widget)).dy, order.order));
      }

      expect(orders, isNotEmpty);
      final byPosition = orders.toList()..sort((a, b) => a.$1.compareTo(b.$1));
      final byOrder = orders.toList()..sort((a, b) => a.$2.compareTo(b.$2));
      expect(
        byPosition.map((e) => e.$2).toList(),
        byOrder.map((e) => e.$2).toList(),
        reason: 'the declared focus order does not match the visual order',
      );
    });

    testWidgets('the toolbar control is reachable and named', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: desktopHomeOverrides,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expectAnnouncedAs(tester, 'Diagnostics');

      handle.dispose();
    });
  });
}
