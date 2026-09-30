import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../domain/desktop_service.dart';

export '../../l10n/app_localizations.dart';

/// Extension providing convenient access to [AppLocalizations] from [BuildContext].
extension AppLocalizationsX on BuildContext {
  /// The [AppLocalizations] instance for the current widget context.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(const Locale('en'));
}

/// Resolves the current [AppLocalizations] outside of a [BuildContext] (such as
/// from tray menus or background services), matching the system's preferred locale
/// with fallback to English.
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

/// Turns native backend diagnostics into user-facing copy without displaying raw backend text.
String describeNativeBackendReason(AppLocalizations l10n, String raw) {
  if (raw.startsWith('Remote Link needs Accessibility permission')) {
    return l10n.inputAccessibilityPermission;
  }
  if (raw.startsWith('Remote Link needs Screen Recording permission')) {
    return l10n.screenRecordingPermissionReason;
  }
  if (raw.startsWith('Media control is not supported')) {
    return l10n.backendMediaUnsupported(l10n.thisPlatform);
  }
  if (raw.startsWith('input injection is not implemented')) {
    return l10n.backendInputUnsupported(Platform.operatingSystem);
  }
  if (raw == 'native input libraries could not be loaded') {
    return l10n.backendInputLibrariesUnavailable;
  }
  return l10n.backendUnavailableGeneric;
}

String describeBackendFailure(AppLocalizations l10n, BackendFailure failure) =>
    switch (failure) {
      BackendFailure.accessibilityPermission =>
        l10n.inputAccessibilityPermission,
      BackendFailure.screenRecordingPermission =>
        l10n.screenRecordingPermissionReason,
      BackendFailure.inputUnsupported =>
        l10n.backendInputUnsupported(Platform.operatingSystem),
      BackendFailure.inputLibrariesUnavailable =>
        l10n.backendInputLibrariesUnavailable,
      BackendFailure.backendDisposed => l10n.backendUnavailableGeneric,
      BackendFailure.clipboardUnsupported =>
        l10n.backendClipboardUnsupported(Platform.operatingSystem),
      BackendFailure.clipboardUnavailable => l10n.backendClipboardUnavailable,
      BackendFailure.mediaUnsupported =>
        l10n.backendMediaUnsupported(Platform.operatingSystem),
      BackendFailure.mediaUnavailable => l10n.backendMediaUnavailable,
    };
