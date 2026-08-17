import 'package:flutter/material.dart';

import 'motion.dart';

/// The desktop's colour scheme and the rules that keep it legible.
///
/// Pulled out of `main.dart` so `test/contrast_test.dart` can measure the
/// *same* schemes the app runs with. A contrast test against a scheme
/// constructed separately in the test file proves nothing about what ships.
///
/// The seed must match the phone's — see the mobile app's copy of this file for
/// why the two are separate at all.
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
/// `test/contrast_test.dart`.
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

/// The other status colour Material 3 does not supply: "pay attention".
///
/// The log viewer drew warnings in `Colors.orange`, which is a mid-tone chosen
/// to sit on white and measures roughly 2:1 against the light surface the log
/// is actually painted on. Both values here are checked in both themes by
/// `test/contrast_test.dart`.
Color warningColor(ColorScheme scheme) => scheme.brightness == Brightness.dark
    ? const Color(0xFFFFB77C)
    : const Color(0xFF8A4B00);

/// How much larger the user has asked text to be, as a plain multiplier.
///
/// [TextScaler] is non-linear on newer platforms, so there is no factor to read
/// off it directly. Sampling it at a representative body size is the supported
/// way to size a *box* that has to hold text. Never use it to scale a font:
/// pass the scaler itself for that.
double textScaleFactorOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14;
