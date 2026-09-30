import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

export '../../l10n/app_localizations.dart';

/// Extension providing convenient access to [AppLocalizations] from [BuildContext].
extension AppLocalizationsX on BuildContext {
  /// The [AppLocalizations] instance for the current widget context.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(const Locale('en'));
}

/// Resolves the current [AppLocalizations] outside of a [BuildContext] (such as
/// from root event listeners or background services), matching the system's
/// preferred locale with fallback to English.
AppLocalizations currentAppLocalizations([Locale? locale]) {
  final target = locale ??
      PlatformDispatcher.instance.locales.firstOrNull ??
      const Locale('en');
  try {
    return lookupAppLocalizations(target);
  } on FlutterError {
    return lookupAppLocalizations(const Locale('en'));
  }
}

/// Wraps [text] in Unicode First Strong Isolate (FSI `\u2068`) and
/// Pop Directional Isolate (PDI `\u2069`) characters so that numbers, file paths,
/// IP addresses, hostnames, SAS codes, and shortcuts do not reorder when embedded
/// in an RTL sentence.
String bidiIsolate(String text) => '\u2068$text\u2069';
