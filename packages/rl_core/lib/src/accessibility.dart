/// How security-critical values are described to assistive technology.
///
/// This lives in `rl_core` rather than in either app because the phone and the
/// desktop show the *same* six pairing digits, and a screen-reader user
/// compares what the two devices say. If the apps worded that differently, the
/// comparison the handshake depends on would be comparing two descriptions
/// rather than two numbers. One implementation, used by both, is the point.
library;

const List<String> _digitWords = <String>[
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
];

/// The spoken form of one character, or the character itself if it is not a
/// digit.
String spokenDigit(String character) {
  if (character.length != 1) return character;
  final code = character.codeUnitAt(0) - 0x30;
  if (code < 0 || code > 9) return character;
  return _digitWords[code];
}

/// [digits] as words a screen reader announces one at a time.
///
/// `'482159'` becomes `'four, eight, two, one, five, nine'`.
///
/// The words matter and so do the commas. Handed the bare string, screen
/// readers announce it as a single quantity — "four hundred and eighty-two
/// thousand, one hundred and fifty-nine" — which cannot be compared digit by
/// digit against another device saying the same thing its own way. Spelling
/// each digit as a word and separating them with commas forces the per-digit
/// reading and a pause between each, which is the granularity the comparison
/// needs.
String spokenDigits(String digits) =>
    digits.split('').map(spokenDigit).join(', ');

/// Describes one digit and its position, for stepping through them one by one.
///
/// Position is included because a user who lands on a digit mid-sequence
/// otherwise has no way to know which one they are hearing, and "the third
/// digit differs" is the report that identifies a relay attack.
String spokenDigitPosition(String digits, int index) =>
    'Digit ${index + 1} of ${digits.length}: ${spokenDigit(digits[index])}';

/// [digits] split into groups so the eye can hold its place.
///
/// Visual only — the grouping is deliberately not part of the spoken form,
/// where the commas already do that job.
String groupedDigits(String digits, {int groupSize = 3}) {
  if (groupSize <= 0) return digits;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && i % groupSize == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
