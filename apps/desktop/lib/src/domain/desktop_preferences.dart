import 'dart:convert';
import 'dart:io';

import 'package:rl_core/rl_core.dart';

/// The handful of choices the user makes about the app itself.
///
/// Deliberately not `shared_preferences`: this is one small JSON file beside the
/// identity key and the trust store, which are already plain files in the same
/// directory, and a plugin that stores data in a *different* place on each
/// platform makes "where is my configuration" a question with three answers.
///
/// Every read is from memory. The file is written whole on each change, which
/// for a document measured in bytes is simpler than merging and cannot leave
/// two keys disagreeing about which write came last.
final class DesktopPreferences {
  DesktopPreferences._(this._file, this._values);

  /// Reads the file, or starts empty if there is not one yet.
  ///
  /// A damaged file is treated as an absent one rather than as a failure to
  /// start: a corrupt settings file must never be the reason a service the user
  /// depends on refuses to come up. It is logged, and the defaults apply.
  static Future<DesktopPreferences> open(File file) async {
    final log = Log.scoped('desktop.preferences');
    if (!file.existsSync()) return DesktopPreferences._(file, <String, Object?>{});
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('settings file is not an object');
      }
      return DesktopPreferences._(file, Map<String, Object?>.of(decoded));
    } on Object catch (error) {
      log.warn('could not read the settings file, using defaults',
          error: error);
      return DesktopPreferences._(file, <String, Object?>{});
    }
  }

  final File _file;
  final Map<String, Object?> _values;

  /// Whether the key has ever been written.
  ///
  /// The difference between "off" and "never asked" is the whole of the
  /// start-at-login decision: the first launch turns it on, and every launch
  /// after that leaves the user's answer alone.
  bool contains(String key) => _values.containsKey(key);

  bool boolean(String key, {required bool orElse}) {
    final value = _values[key];
    return value is bool ? value : orElse;
  }

  Future<void> setBoolean(String key, {required bool value}) async {
    _values[key] = value;
    await _flush();
  }

  Future<void> _flush() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_values),
      flush: true,
    );
  }
}

/// Keys, named once so a typo cannot silently create a second setting.
abstract final class PreferenceKeys {
  static const String startAtLogin = 'startAtLogin';
}
