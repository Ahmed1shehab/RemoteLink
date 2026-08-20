import 'package:flutter/material.dart';

import 'motion.dart';

/// The desktop's colour scheme and the rules that keep it legible.
///
/// Pulled out of `main.dart` so `test/contrast_test.dart` can measure the
/// *same* schemes the app runs with. A contrast test against a scheme
/// constructed separately in the test file proves nothing about what ships.
///
/// The palette must match the phone's — see the mobile app's copy of this file
/// for why the two are separate at all.
/// The navy the logo is drawn on, and the colour the whole app is built from.
///
/// Sampled from `assets/brand/logo.png` rather than picked to taste: the mark
/// is a white monitor-and-phone glyph on this field, and the app that opens
/// underneath it should look like the icon the user tapped. What shipped before
/// was `#5B5CE2`, an indigo that appears nowhere in the artwork, so every
/// accent in both apps disagreed with the icon on the Dock and the home screen.
const Color kBrandNavy = Color(0xFF1B2438);

/// The other half of the mark.
const Color kBrandWhite = Color(0xFFFFFFFF);

/// Light: navy ink and navy accents on white paper.
///
/// Written out rather than generated with `ColorScheme.fromSeed`. Material's
/// tonal palette takes the hue and discards the rest, so seeding it with the
/// navy produced a mid-blue at the tones the roles actually use — a scheme in
/// the right family and the wrong key, which is the failure the seed was
/// supposed to prevent. Every pair below is measured by `test/contrast_test.dart`
/// against the 4.5:1 minimum in both themes.
const ColorScheme _light = ColorScheme(
  brightness: Brightness.light,
  primary: kBrandNavy,
  onPrimary: kBrandWhite,
  primaryContainer: Color(0xFFD7E0EF),
  onPrimaryContainer: Color(0xFF101827),
  secondary: Color(0xFF3B4761),
  onSecondary: kBrandWhite,
  secondaryContainer: Color(0xFFDFE5F0),
  onSecondaryContainer: Color(0xFF161E2E),
  tertiary: Color(0xFF2F5480),
  onTertiary: kBrandWhite,
  tertiaryContainer: Color(0xFFD6E4F5),
  onTertiaryContainer: Color(0xFF0E2942),
  error: Color(0xFFB3261E),
  onError: kBrandWhite,
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: kBrandWhite,
  onSurface: Color(0xFF111827),
  onSurfaceVariant: Color(0xFF4A5568),
  surfaceContainerLowest: kBrandWhite,
  surfaceContainerLow: Color(0xFFF7F9FC),
  surfaceContainer: Color(0xFFF1F4F9),
  surfaceContainerHigh: Color(0xFFE9EDF5),
  surfaceContainerHighest: Color(0xFFE1E7F1),
  outline: Color(0xFF6B7688),
  outlineVariant: Color(0xFFC8D0DE),
  inverseSurface: kBrandNavy,
  onInverseSurface: Color(0xFFF1F4F9),
  inversePrimary: Color(0xFFB6C8E6),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// Dark: white ink on the logo's own navy.
///
/// The surfaces are the brand colour here, so `primary` cannot also be the
/// navy — it would vanish into the page. It becomes a light tint of the same
/// hue, which is what Material expects of a dark scheme and keeps filled
/// buttons legible without introducing a second colour family.
const ColorScheme _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFB6C8E6),
  onPrimary: Color(0xFF121E33),
  primaryContainer: Color(0xFF2A3852),
  onPrimaryContainer: Color(0xFFD9E3F5),
  secondary: Color(0xFFB2BED4),
  onSecondary: kBrandNavy,
  secondaryContainer: Color(0xFF333F55),
  onSecondaryContainer: Color(0xFFDCE4F2),
  tertiary: Color(0xFF9FC2E8),
  onTertiary: Color(0xFF0E2942),
  tertiaryContainer: Color(0xFF2B4763),
  onTertiaryContainer: Color(0xFFD3E4F8),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Color(0xFF111A2B),
  onSurface: Color(0xFFE7ECF5),
  onSurfaceVariant: Color(0xFFB3BDCE),
  surfaceContainerLowest: Color(0xFF0A101C),
  surfaceContainerLow: Color(0xFF161F32),
  surfaceContainer: Color(0xFF1A2539),
  surfaceContainerHigh: Color(0xFF212D43),
  surfaceContainerHighest: Color(0xFF28354D),
  outline: Color(0xFF8894A8),
  outlineVariant: Color(0xFF414D63),
  inverseSurface: Color(0xFFE7ECF5),
  onInverseSurface: kBrandNavy,
  inversePrimary: Color(0xFF3B4761),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// The page behind the cards, a shade off the card surface in both themes.
const Color _lightCanvas = Color(0xFFF4F6FA);
const Color _darkCanvas = Color(0xFF0B121F);

ColorScheme remoteLinkColorScheme(Brightness brightness) =>
    brightness == Brightness.dark ? _dark : _light;

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
    scaffoldBackgroundColor: dark ? _darkCanvas : _lightCanvas,
    canvasColor: dark ? _darkCanvas : _lightCanvas,
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
      // The brand navy in the light theme, where a snack bar is meant to read
      // as a dark slab against the page; a raised surface in the dark theme,
      // where a darker slab would disappear into it.
      backgroundColor:
          dark ? scheme.surfaceContainerHighest : scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: dark ? scheme.onSurface : scheme.onInverseSurface,
      ),
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
