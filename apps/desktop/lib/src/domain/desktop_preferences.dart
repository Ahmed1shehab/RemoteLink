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
  ///
  /// Synchronous, unlike the write. The document is a few dozen bytes read once
  /// during startup, so the await buys nothing measurable — and it costs
  /// something real: awaited file I/O inside a widget test deadlocks, because
  /// `flutter_test` runs on a fake clock that never advances the real event
  /// loop. A settings screen that cannot be tested is worse than a startup that
  /// blocks for a microsecond.
  static DesktopPreferences open(File file) {
    final log = Log.scoped('desktop.preferences');
    if (!file.existsSync()) {
      return DesktopPreferences._(file, <String, Object?>{});
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
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

  /// The stored string for [key], or null when unset or of the wrong type.
  ///
  /// Null rather than an `orElse` parameter, unlike [boolean]. The one string
  /// setting is a folder path, and its default is not a constant — it is
  /// whatever the OS calls the Downloads folder on this machine, which has to
  /// be resolved asynchronously. Returning null lets the caller decide that,
  /// instead of every caller passing the same computed fallback in.
  String? string(String key) {
    final value = _values[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  Future<void> setString(String key, String value) async {
    _values[key] = value;
    await _flush();
  }

  /// Forgets [key], so its default applies again.
  ///
  /// Distinct from writing the default in: [contains] is what tells "never
  /// chosen" apart from "chosen, and happens to match the default", and the
  /// download folder needs that difference to keep following a Downloads
  /// folder the user moves.
  Future<void> remove(String key) async {
    if (!_values.containsKey(key)) return;
    _values.remove(key);
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

  /// Absolute path of the folder incoming files are saved into.
  ///
  /// Absent until the user picks one, and absence means "wherever this machine
  /// keeps Downloads" rather than a path frozen at first launch. That matters
  /// on Windows, where the Downloads folder can be moved after the fact: a
  /// stored default would go on pointing at the old location, and the user
  /// would have to re-choose a folder they never chose in the first place.
  static const String downloadDirectory = 'downloadDirectory';
}
