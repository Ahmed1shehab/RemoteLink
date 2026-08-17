import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/theme.dart';

import 'support/contrast.dart';

/// Measures the colour pairs the desktop app actually draws text with, in both
/// themes.
///
/// The schemes come from `lib/src/app/theme.dart` — the ones `main.dart` hands
/// to `MaterialApp`. A contrast test against a scheme built in the test file
/// would pass regardless of what ships.
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

      checkPair('body text on the page', scheme.onSurface, scheme.surface);
      checkPair(
        'secondary text on the page',
        scheme.onSurfaceVariant,
        scheme.surface,
      );

      // The pairing code and the device list sit on cards.
      checkPair(
        'text on a card',
        scheme.onSurface,
        scheme.surfaceContainerLow,
      );

      // The permission banner, which is the loudest thing in the window.
      checkPair(
        'the permission banner',
        scheme.onErrorContainer,
        scheme.errorContainer,
      );

      // Transfer status chips.
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

      final success = successColors(scheme);
      checkPair('a completed chip', success.onContainer, success.container);

      // The log viewer, which is monospaced 12px — the smallest text either app
      // draws, and the place a marginal colour hurts most.
      checkPair('a log line', scheme.onSurface, scheme.surface);
      checkPair('an error log level', scheme.error, scheme.surface);
      checkPair('a warning log level', warningColor(scheme), scheme.surface);
      checkPair('an info log level', scheme.primary, scheme.surface);
    });
  }

  group('the regressions this suite exists for', () {
    test('Colors.orange as a log level really does fail', () {
      // What the WARN rows measured before `warningColor` replaced them.
      // Material's orange is tuned to sit on white as a *fill*, not as text.
      expect(
        contrastRatio(
          Colors.orange,
          remoteLinkColorScheme(Brightness.light).surface,
        ),
        lessThan(kMinimumContrast),
      );
    });

    test('Colors.green fails on the light surface, and only there', () {
      // What the old "Completed" chip measured. Note which theme: Material's
      // green is a mid-light tone, so it is the light theme it fails in.
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
  });
}
