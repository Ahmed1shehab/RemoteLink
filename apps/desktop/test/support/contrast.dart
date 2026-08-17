import 'dart:math' as math;
import 'dart:ui';

/// WCAG 2.1 contrast maths, for asserting on the colours the app actually uses.
///
/// Small enough to duplicate in the phone app's test support rather than
/// widen `rl_core`'s remit: this is a test-only concern, and `rl_core` sits
/// beneath the whole repository (CONTRIBUTING §2).

/// WCAG 2.1 §1.4.3, the minimum for body text.
const double kMinimumContrast = 4.5;

/// WCAG 2.1 §1.4.3, the minimum for text at 18.66px bold or 24px regular.
const double kMinimumLargeTextContrast = 3.0;

/// Relative luminance, per the WCAG definition.
double _relativeLuminance(Color color) {
  double channel(double component) => component <= 0.03928
      ? component / 12.92
      : math.pow((component + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// Flattens [foreground] onto [background], honouring alpha.
///
/// Necessary because several colours in the app are drawn semi-transparent, and
/// measuring those as if they were opaque reports a contrast the user never
/// sees.
Color composite(Color foreground, Color background) {
  final alpha = foreground.a;
  return Color.from(
    alpha: 1,
    red: foreground.r * alpha + background.r * (1 - alpha),
    green: foreground.g * alpha + background.g * (1 - alpha),
    blue: foreground.b * alpha + background.b * (1 - alpha),
  );
}

/// The WCAG contrast ratio between two colours, from 1:1 to 21:1.
///
/// [foreground] is composited onto [background] first, so a translucent colour
/// is measured as it is seen.
double contrastRatio(Color foreground, Color background) {
  final a = _relativeLuminance(composite(foreground, background));
  final b = _relativeLuminance(background);
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}
