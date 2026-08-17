import 'package:rl_core/rl_core.dart';
import 'package:test/test.dart';

void main() {
  group('spokenDigits', () {
    test('spells each digit as a word so none is read as a quantity', () {
      expect(spokenDigits('482159'), 'four, eight, two, one, five, nine');
    });

    test('never emits the bare digit run a screen reader would merge', () {
      // The failure this guards against is the whole reason the function
      // exists: '482159' announced as one number cannot be compared position
      // by position against the other device. So the output must contain no
      // digit characters at all.
      expect(RegExp(r'\d').hasMatch(spokenDigits('482159')), isFalse);
    });

    test('keeps repeated digits distinct rather than collapsing them', () {
      expect(spokenDigits('000000'), 'zero, zero, zero, zero, zero, zero');
    });

    test('handles the empty string without inventing a digit', () {
      expect(spokenDigits(''), '');
    });

    test('passes non-digits through rather than mapping them to a word', () {
      expect(spokenDigits('4a2'), 'four, a, two');
    });
  });

  group('spokenDigitPosition', () {
    test('names the position so a mid-sequence landing is unambiguous', () {
      expect(spokenDigitPosition('482159', 0), 'Digit 1 of 6: four');
      expect(spokenDigitPosition('482159', 5), 'Digit 6 of 6: nine');
    });

    test('positions are one-based, matching how a user counts them', () {
      expect(spokenDigitPosition('482159', 2), startsWith('Digit 3 of 6'));
    });
  });

  group('groupedDigits', () {
    test('groups in threes by default', () {
      expect(groupedDigits('482159'), '482 159');
    });

    test('honours a different group size', () {
      expect(groupedDigits('482159', groupSize: 2), '48 21 59');
    });

    test('a non-positive group size leaves the digits alone', () {
      expect(groupedDigits('482159', groupSize: 0), '482159');
    });

    test('does not pad a partial trailing group', () {
      expect(groupedDigits('48215'), '482 15');
    });
  });
}
