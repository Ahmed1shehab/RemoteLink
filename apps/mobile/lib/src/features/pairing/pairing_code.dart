import 'package:flutter/material.dart';
import 'package:rl_core/rl_core.dart';

/// The six pairing digits, shown to the eye and to a screen reader.
///
/// ## Why this is a widget and not a `Text`
///
/// Comparing these digits against the other device is the entire defence
/// against a machine-in-the-middle. They were drawn as a single `Text` holding
/// `'482 159'`, which screen readers announce as one quantity — "four hundred
/// and eighty-two, one hundred and fifty-nine". Two devices reading their codes
/// that way cannot be compared digit by digit, and a relay attack only has to
/// make the *numbers* differ, not the sentences.
///
/// So the code is exposed three ways at once, all derived from the same string:
///
/// * The container announces the whole code as separated words — "Security
///   code: four, eight, two, one, five, nine" — which is what someone hears on
///   landing on it, and is directly comparable with the other device.
/// * Each digit is its own node saying which position it is, so the code can be
///   stepped through one digit at a time. "The third one differs" is the report
///   that identifies an attack.
/// * The visible grouping is unchanged.
///
/// The wording lives in `rl_core` so the phone and the desktop cannot drift
/// apart — see [spokenDigits].
class PairingCodeDisplay extends StatelessWidget {
  const PairingCodeDisplay({
    required this.digits,
    this.textStyle,
    this.groupSize = 3,
    super.key,
  });

  /// The short authentication string, derived locally from the shared secret.
  final String digits;

  final TextStyle? textStyle;

  /// How many digits per visual group. Spacing only; the spoken form separates
  /// every digit regardless.
  final int groupSize;

  @override
  Widget build(BuildContext context) {
    final style = textStyle ??
        Theme.of(context).textTheme.displayMedium?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 6,
            );

    return Semantics(
      container: true,
      // Keeps the per-digit nodes below rather than merging them into this one,
      // which is what makes stepping through the code possible.
      explicitChildNodes: true,
      label: 'Security code: ${spokenDigits(digits)}',
      child: FittedBox(
        // Scales down only. At an ordinary text size nothing happens; at 200%
        // the code shrinks to fit instead of overflowing. Clipping is not an
        // option here in a way it is nowhere else in the app — half a code
        // compares equal to a different half a code.
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < digits.length; i++) ...<Widget>[
              if (i > 0 && i % groupSize == 0) const SizedBox(width: 20),
              Semantics(
                label: spokenDigitPosition(digits, i),
                // Replaces the bare character, which a reader would otherwise
                // announce alongside the position.
                excludeSemantics: true,
                child: Text(digits[i], style: style),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
