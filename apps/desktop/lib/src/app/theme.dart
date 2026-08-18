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
const Color kSeedColor = Color(0xFF5B5CE2);

/// Material 3 derives every `on*` pair from the seed to meet 4.5:1, which is
/// why the app sticks to scheme roles instead of literal colours.
ColorScheme remoteLinkColorScheme(Brightness brightness) =>
    ColorScheme.fromSeed(seedColor: kSeedColor, brightness: brightness);

ThemeData remoteLinkTheme(Brightness brightness) {
  final scheme = remoteLinkColorScheme(brightness);
  final dark = brightness == Brightness.dark;
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0B0D14) : const Color(0xFFF6F7FB),
    canvasColor: dark ? const Color(0xFF0B0D14) : const Color(0xFFF6F7FB),
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall:
          base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge:
          base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(40, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(40, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(60, 42)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outlineVariant),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.55),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          dark ? scheme.surfaceContainerHighest : const Color(0xFF20222C),
      contentTextStyle:
          TextStyle(color: dark ? scheme.onSurface : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: dark ? scheme.surfaceContainerHighest : const Color(0xFF20222C),
        borderRadius: BorderRadius.circular(9),
      ),
      textStyle: TextStyle(color: dark ? scheme.onSurface : Colors.white),
    ),
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
