import 'dart:io';

import 'package:rl_core/rl_core.dart';

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
  AutoStart({required this.label, required this.executablePath});

  /// Reverse-DNS identifier, also the plist filename on macOS.
  final String label;

  final String executablePath;

  final Log _log = Log.scoped('desktop.autostart');

  /// Flag passed to the launched copy so it starts without a window.
  static const String minimisedFlag = '--minimised';

  File get _agentFile => File(
        '${Platform.environment['HOME']}/Library/LaunchAgents/$label.plist',
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
