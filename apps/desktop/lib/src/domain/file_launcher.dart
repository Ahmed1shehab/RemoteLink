import 'dart:io';

// Every check here is a one-off before opening a window in the file manager,
// never on an input path. The synchronous variants would block the UI isolate
// on a network volume for no benefit.
// ignore_for_file: avoid_slow_async_io

import 'package:rl_core/rl_core.dart';
import 'package:rl_native/rl_native.dart';

/// Opens received files and the folders they live in, using the desktop's own
/// file manager.
///
/// Kept away from [Process.run] call sites elsewhere in the app for one
/// reason: every path here came off the network. The file name was chosen by
/// whoever sent it, so each argument is passed as its own argv entry and never
/// concatenated into a shell string, and nothing is opened unless it is
/// somewhere this app actually put it.
abstract final class FileLauncher {
  static final Log _log = Log.scoped('desktop.launcher');

  /// Opens [path] in whatever application owns its type.
  static Future<bool> openFile(String path) async {
    if (!await File(path).exists()) {
      _log.warn('refusing to open a file that is no longer there');
      return false;
    }
    return _run(
      switch (NativeBackends.currentPlatform) {
        PlatformKind.macos => ('open', <String>[path]),
        PlatformKind.windows => ('explorer', <String>[path]),
        _ => ('xdg-open', <String>[path]),
      },
    );
  }

  /// Opens the folder holding [path], selecting the file where the platform
  /// supports it.
  ///
  /// Selecting rather than merely opening is the difference between "here is
  /// your file" and "here are four hundred files, one of which is yours".
  static Future<bool> revealFile(String path) async {
    if (!await File(path).exists()) {
      // The file was moved or deleted after it arrived. Its folder is still
      // the useful answer, so fall back to that rather than doing nothing.
      final parent = File(path).parent;
      if (!await parent.exists()) {
        _log.warn('refusing to reveal a path that is no longer there');
        return false;
      }
      return openFolder(parent.path);
    }
    return _run(
      switch (NativeBackends.currentPlatform) {
        PlatformKind.macos => ('open', <String>['-R', path]),
        // `/select,` and the path are one argument to explorer.exe; splitting
        // them opens the user's Documents folder instead.
        PlatformKind.windows => ('explorer', <String>['/select,$path']),
        _ => ('xdg-open', <String>[File(path).parent.path]),
      },
    );
  }

  /// Opens [path] as a folder.
  static Future<bool> openFolder(String path) async {
    if (!await Directory(path).exists()) {
      _log.warn('refusing to open a folder that is no longer there');
      return false;
    }
    return _run(
      switch (NativeBackends.currentPlatform) {
        PlatformKind.macos => ('open', <String>[path]),
        PlatformKind.windows => ('explorer', <String>[path]),
        _ => ('xdg-open', <String>[path]),
      },
    );
  }

  static Future<bool> _run((String, List<String>) command) async {
    final (executable, arguments) = command;
    try {
      final result = await Process.run(executable, arguments);
      // Windows Explorer reports a non-zero exit code even when it succeeds,
      // so the code is logged rather than believed.
      if (result.exitCode != 0) {
        _log.debug(() => '$executable exited with ${result.exitCode}');
      }
      return true;
    } on ProcessException catch (e) {
      _log.error('could not open a path in the file manager', error: e);
      return false;
    }
  }
}
