import 'dart:io';

import 'package:rl_core/rl_core.dart';

import 'desktop_preferences.dart';

/// The reverse-DNS name of the login item, and the plist's filename on macOS.
///
/// Kept as it is through the rename to "Remote Link": it is an identifier the
/// OS already has on file, and changing it leaves the old login item registered
/// with nothing to remove it.
const String kAutoStartLabel = 'com.example.remotelinkDesktop';

/// Registers the companion to start when the user logs in.
///
/// ## Why this is not a package
///
/// `launch_at_startup` was used first and threw `MissingPluginException` on
/// macOS: at the pinned version it has no macOS implementation at all, so the
/// call compiled, ran, and silently did nothing — the worst possible outcome
/// for a feature whose entire job is to happen without the user watching.
///
/// The underlying mechanisms are small enough that owning them is cheaper than
/// depending on someone else's wrapper:
///
/// * **macOS** — a LaunchAgent property list in `~/Library/LaunchAgents`. This
///   is the documented mechanism, it needs no entitlement, and `launchctl`
///   picks it up at the next login without a reboot.
/// * **Windows** — a value under the `Run` key in `HKCU`. Per-user, so it needs
///   no elevation.
///
/// Both are plain file or command operations, so this is pure `dart:io` and
/// carries no plugin registration to go missing.
final class AutoStart {
  AutoStart({
    required this.label,
    required this.executablePath,
    Directory? launchAgentsDirectory,
  }) : _launchAgents = launchAgentsDirectory;

  /// Reverse-DNS identifier, also the plist filename on macOS.
  final String label;

  final String executablePath;

  /// Where the macOS LaunchAgent goes.
  ///
  /// Injectable only so tests are not obliged to write into the developer's own
  /// `~/Library/LaunchAgents` — a suite that registers a login item on the
  /// machine that runs it is a suite nobody runs twice.
  final Directory? _launchAgents;

  final Log _log = Log.scoped('desktop.autostart');

  /// Flag passed to the launched copy so it starts without a window.
  static const String minimisedFlag = '--minimised';

  File get _agentFile => File(
        '${_launchAgents?.path ?? '${Platform.environment['HOME']}'
            '/Library/LaunchAgents'}/$label.plist',
      );

  /// Whether login registration is currently in place.
  Future<bool> isEnabled() async {
    if (Platform.isMacOS) return _agentFile.existsSync();
    if (Platform.isWindows) {
      final result = await Process.run('reg', <String>[
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        label,
      ]);
      return result.exitCode == 0;
    }
    return false;
  }

  Future<void> enable() async {
    try {
      if (Platform.isMacOS) {
        await _writeLaunchAgent();
      } else if (Platform.isWindows) {
        await Process.run('reg', <String>[
          'add',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          label,
          '/t',
          'REG_SZ',
          '/d',
          '"$executablePath" $minimisedFlag',
          '/f',
        ]);
      } else {
        return;
      }
      _log.info('registered to start at login');
    } on Object catch (e) {
      // A managed device can forbid login items by policy. Worth saying, never
      // worth failing to start over.
      _log.warn('could not register to start at login', error: e);
    }
  }

  Future<void> disable() async {
    try {
      if (Platform.isMacOS) {
        if (_agentFile.existsSync()) await _agentFile.delete();
      } else if (Platform.isWindows) {
        await Process.run('reg', <String>[
          'delete',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          label,
          '/f',
        ]);
      }
    } on Object catch (e) {
      _log.warn('could not remove the login item', error: e);
    }
  }

  Future<void> _writeLaunchAgent() async {
    final directory = _agentFile.parent;
    if (!directory.existsSync()) await directory.create(recursive: true);

    // Written fresh every time rather than only when absent: `flutter run`
    // rebuilds to a new path on every launch, and a plist pointing at a binary
    // that no longer exists is worse than none — launchd reports a failure at
    // every login.
    await _agentFile.writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$executablePath</string>
    <string>$minimisedFlag</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <!-- Not KeepAlive: quitting from the tray must actually quit, not be undone
       by launchd restarting the process a second later. -->
  <key>KeepAlive</key>
  <false/>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
''', flush: true);
  }
}

/// Brings the login item into line with what the user last chose.
///
/// Called on every launch, and it has to be: `flutter run` and every update put
/// the executable at a new path, and a login item pointing at a binary that has
/// moved fails at each login with no way for the user to find out why.
/// Rewriting it is the only way for "on" to keep meaning on.
///
/// The subtlety is the first launch. Doing this unconditionally — which is what
/// shipped — meant a user who turned start-at-login off had it turned back on
/// the next time they opened the app, silently, forever. So an unrecorded
/// preference means "never asked", and only that case registers on its own;
/// after that the stored answer wins, including when the answer is no and a
/// stale login item needs removing.
///
/// Takes the two actions rather than an [AutoStart] so it can be tested without
/// a home directory to write into: what is worth testing here is the decision,
/// and the decision is the part that was wrong.
Future<bool> reconcileAutoStart({
  required DesktopPreferences preferences,
  required Future<void> Function() enable,
  required Future<void> Function() disable,
}) async {
  final wanted = preferences.boolean(PreferenceKeys.startAtLogin, orElse: true);
  if (!preferences.contains(PreferenceKeys.startAtLogin)) {
    await preferences.setBoolean(PreferenceKeys.startAtLogin, value: wanted);
  }

  if (wanted) {
    await enable();
  } else {
    await disable();
  }
  return wanted;
}
