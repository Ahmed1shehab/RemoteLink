import 'package:flutter/material.dart';

import 'motion.dart';

/// The app's colour scheme and the rules that keep it legible.
///
/// Pulled out of `main.dart` so `test/contrast_test.dart` can measure the
/// *same* schemes the app runs with. A contrast test against a scheme
/// constructed separately in the test file proves nothing about what ships.
///
/// The desktop app carries its own copy. That duplication is deliberate rather
/// than an oversight: `packages/` may not import Flutter (CONTRIBUTING §1), so
/// there is nowhere below `apps/` for a `ThemeData` to live, and inventing a
/// shared Flutter package to hold thirty lines of colour would be the larger
/// mistake. The seed is the thing that has to match, and it is one constant in
/// each.
const Color kSeedColor = Color(0xFF3D5AFE);

/// Material 3 derives every `on*` pair from the seed to meet 4.5:1, which is
/// why the app sticks to scheme roles instead of literal colours.
ColorScheme remoteLinkColorScheme(Brightness brightness) =>
    ColorScheme.fromSeed(seedColor: kSeedColor, brightness: brightness);

ThemeData remoteLinkTheme(Brightness brightness) {
  final scheme = remoteLinkColorScheme(brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    pageTransitionsTheme: reducedMotionAwarePageTransitions(),
  );
}

/// The one status colour Material 3 does not supply: "this finished".
///
/// `Colors.green` was used for it. Material's green is a mid-light tone: it
/// reads well on a dark surface and measures about 2.7:1 on a light one, so the
/// chip reporting that a transfer had finished was the one status nobody could
/// read in the default theme. These pairs are checked in both themes by
/// `test/contrast_test.dart`, which is the only reason to hard-code a colour at
/// all.
({Color container, Color onContainer}) successColors(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
        ? (
            container: const Color(0xFF05512A),
            onContainer: const Color(0xFFA9EFC3),
          )
        : (
            container: const Color(0xFFC7F0D4),
            onContainer: const Color(0xFF06522A),
          );

/// The largest text scale the rendered keyboard lays keycaps out at.
///
/// Not a cap on the user's setting — the rest of the app scales without limit.
/// A keycap is a fixed-size box by definition, though: past this point the
/// label is wider than the key however the row is divided, so beyond it the
/// label scales down to fit rather than clipping, and the keys grow instead.
/// A clipped key label is worse than a small one, because 'F11' cut to 'F1' is
/// a different key.
const double kKeyCapMaxTextScale = 1.3;

/// [TextScaler] for keycaps: the user's setting, capped.
TextScaler keyCapTextScaler(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: kKeyCapMaxTextScale);

/// How much larger the user has asked text to be, as a plain multiplier.
///
/// [TextScaler] is non-linear on newer platforms, so there is no factor to read
/// off it directly. Sampling it at a representative body size is the supported
/// way to size a *box* that has to hold text, which is the only thing this is
/// for. Never use it to scale a font: pass the scaler itself for that.
double textScaleFactorOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14;
