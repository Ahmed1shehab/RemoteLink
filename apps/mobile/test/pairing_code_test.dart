import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/pairing/pairing_code.dart';

import 'support/semantics.dart';

/// The six digits are the whole defence against a machine-in-the-middle, and a
/// screen-reader user has to be able to compare them against the computer's
/// screen digit by digit.
///
/// These assertions are about *how* the code is announced, not merely that it
/// is. Announced as one number it is technically accessible and useless: "four
/// hundred and eighty-two thousand, one hundred and fifty-nine" cannot be
/// checked against the same number spoken by a different voice on a different
/// device without holding six digits in your head in a form neither device
/// gave you.
void main() {
  Widget wrap(String digits) => MaterialApp(
        home: Scaffold(body: Center(child: PairingCodeDisplay(digits: digits))),
      );

  testWidgets('announces the whole code as separated digit words',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap('482159'));
    await tester.pump();

    expectAnnouncedAs(
      tester,
      'Security code: four, eight, two, one, five, nine',
    );

    handle.dispose();
  });

  testWidgets('never announces the digits as a single number', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap('482159'));
    await tester.pump();

    // The regression this whole widget exists to prevent. A node whose label
    // is '482 159' or '482159' is one a screen reader reads as a quantity.
    final labels = semanticsLabels(tester);
    expect(labels, isNot(contains('482 159')));
    expect(labels, isNot(contains('482159')));

    // Nothing announced anywhere may contain a run of two adjacent digits,
    // which is the shape that gets read as a number.
    for (final label in labels) {
      expect(
        RegExp(r'\d\d').hasMatch(label),
        isFalse,
        reason: 'the label "$label" contains adjacent digits, which a screen '
            'reader will announce as one number',
      );
    }

    handle.dispose();
  });

  testWidgets('exposes each digit as its own node, with its position',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap('482159'));
    await tester.pump();

    // So the code can be stepped through one digit at a time. "The third one
    // differs" is the report that identifies a relay attack; without positions
    // the user can only say "they don't match" and cannot say where.
    expectAnnouncedAs(tester, 'Digit 1 of 6: four');
    expectAnnouncedAs(tester, 'Digit 2 of 6: eight');
    expectAnnouncedAs(tester, 'Digit 3 of 6: two');
    expectAnnouncedAs(tester, 'Digit 4 of 6: one');
    expectAnnouncedAs(tester, 'Digit 5 of 6: five');
    expectAnnouncedAs(tester, 'Digit 6 of 6: nine');

    handle.dispose();
  });

  testWidgets('keeps repeated digits distinct', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap('111111'));
    await tester.pump();

    // A code of six identical digits is as likely as any other, and it is the
    // one where a reader that collapses or skips repeats is most dangerous:
    // '111111' and '11111' sound identical and are different codes.
    expectAnnouncedAs(
      tester,
      'Security code: one, one, one, one, one, one',
    );
    for (var i = 1; i <= 6; i++) {
      expectAnnouncedAs(tester, 'Digit $i of 6: one');
    }

    handle.dispose();
  });

  testWidgets('the adjacent-digit check catches the markup this replaced',
      (tester) async {
    final handle = tester.ensureSemantics();

    // The old screen, reproduced exactly: one `Text` holding the grouped code.
    // Run the check above against it and it has to fail, or the check is
    // decoration. This is the same assertion, inverted.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('482 159'))),
      ),
    );
    await tester.pump();

    expect(
      semanticsLabels(tester).any((l) => RegExp(r'\d\d').hasMatch(l)),
      isTrue,
      reason: 'the old single-Text form must trip the adjacent-digit check; '
          'if it does not, the check cannot catch a regression either',
    );

    handle.dispose();
  });

  testWidgets('still shows the grouped digits to the eye', (tester) async {
    await tester.pumpWidget(wrap('482159'));
    await tester.pump();

    // The visual side is unchanged: six digits, grouped in threes. Fixing the
    // spoken form must not cost the sighted comparison.
    for (final digit in <String>['4', '8', '2', '1', '5', '9']) {
      expect(find.text(digit), findsOneWidget);
    }
  });

  testWidgets('does not clip or overflow at a large text size', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: Center(child: PairingCodeDisplay(digits: '482159')),
        ),
      ),
    );
    await tester.pump();

    // Half a code compares equal to a different half a code, so this is the one
    // place in the app where clipping is a security problem rather than a
    // cosmetic one.
    expect(tester.takeException(), isNull);
    for (final digit in <String>['4', '8', '2', '1', '5', '9']) {
      expect(find.text(digit), findsOneWidget);
    }
  });
}
