import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/theme.dart';

import 'support/contrast.dart';

/// Measures the colour pairs the phone app actually draws text with, in both
/// themes.
///
/// The schemes come from `lib/src/app/theme.dart` — the ones `main.dart` hands
/// to `MaterialApp`. A contrast test against a scheme built in the test file
/// would pass regardless of what ships.
///
/// Only pairs the app really uses are listed. A blanket sweep of every
/// combination in a `ColorScheme` would fail on pairs nothing puts together
/// (`onPrimary` on `surface`), and a test that has to be argued with is a test
/// that gets deleted.
void main() {
  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      final scheme = remoteLinkColorScheme(brightness);

      void checkPair(String what, Color foreground, Color background) {
        test('$what meets 4.5:1', () {
          final ratio = contrastRatio(foreground, background);
          expect(
            ratio,
            greaterThanOrEqualTo(kMinimumContrast),
            reason: '$what is ${ratio.toStringAsFixed(2)}:1 in the '
                '${brightness.name} theme, below the 4.5:1 minimum.',
          );
        });
      }

      // Body text everywhere.
      checkPair('body text on the page', scheme.onSurface, scheme.surface);
      checkPair(
        'secondary text on the page',
        scheme.onSurfaceVariant,
        scheme.surface,
      );

      // The touchpad's instructions and the keyboard transcript's placeholder.
      // Both were drawn at 60% alpha; both are the only text on their surface.
      checkPair(
        'secondary text on a raised surface',
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      );
      checkPair(
        'secondary text on a low surface',
        scheme.onSurfaceVariant,
        scheme.surfaceContainerLow,
      );

      // Keycaps, resting and held.
      checkPair(
        'a resting keycap label',
        scheme.onSurface,
        scheme.surfaceContainerHighest,
      );
      checkPair('a held keycap label', scheme.onPrimary, scheme.primary);

      // Status chips on both apps' transfer lists.
      checkPair(
        'an in-progress chip',
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      );
      checkPair(
        'an awaiting chip',
        scheme.onTertiaryContainer,
        scheme.tertiaryContainer,
      );
      checkPair(
        'a failed chip',
        scheme.onErrorContainer,
        scheme.errorContainer,
      );

      // Link-styled and error-styled text drawn straight onto a surface.
      checkPair(
          'the Clear link', scheme.primary, scheme.surfaceContainerHighest);
      checkPair('error text', scheme.error, scheme.surface);

      // The one hard-coded pair, and the reason it is hard-coded: Material 3
      // has no success role, so there was nothing to reach for but a literal.
      final success = successColors(scheme);
      checkPair(
        'a completed chip',
        success.onContainer,
        success.container,
      );
    });
  }

  group('the regression this suite exists for', () {
    test('Colors.green fails on the light surface, and only there', () {
      // What the old "Completed" chip measured, kept as a test rather than a
      // comment so the number cannot rot — and so that anyone reaching for
      // `Colors.green` again sees why not.
      //
      // Note which theme. Material's green is a mid-light tone, so it is the
      // *light* theme it fails in, not the dark one. Guessing that round the
      // wrong way is how a status colour gets "fixed" in the theme nobody was
      // having trouble with.
      expect(
        contrastRatio(
          Colors.green,
          remoteLinkColorScheme(Brightness.light).surface,
        ),
        lessThan(kMinimumContrast),
      );
      expect(
        contrastRatio(
          Colors.green,
          remoteLinkColorScheme(Brightness.dark).surface,
        ),
        greaterThan(kMinimumContrast),
      );
    });

    test('a 60% alpha label on a raised surface really does fail', () {
      // The touchpad instructions and the transcript placeholder, as they were.
      final light = remoteLinkColorScheme(Brightness.light);
      final ratio = contrastRatio(
        light.onSurfaceVariant.withValues(alpha: 0.6),
        light.surfaceContainerHighest,
      );
      expect(ratio, lessThan(kMinimumContrast));
    });
  });
}
