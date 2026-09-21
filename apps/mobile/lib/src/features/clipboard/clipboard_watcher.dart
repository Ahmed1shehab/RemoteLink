import 'dart:async';

import 'package:flutter/services.dart';
import 'package:rl_core/rl_core.dart';

/// Tells this phone when its own clipboard changed, without reading it.
///
/// The distinction is the entire reason this exists. Both mobile platforms
/// punish reading the clipboard — iOS 16 puts a permission alert in front of
/// it, Android 12 shows a toast naming the app that was read — so polling the
/// *contents* to notice a change costs one interruption per poll. Both
/// platforms will, however, tell you the clipboard changed for free: Android
/// through `OnPrimaryClipChangedListener`, Apple through the pasteboard's
/// change counter, neither of which exposes a single byte of content.
///
/// So the shape is: listen for free, read once, at the moment there is
/// something new to read. That is one interruption per copy — which the user
/// is already expecting to have happened — rather than one per second.
abstract interface class ClipboardWatcher {
  /// Fires once per clipboard change while something is listening.
  ///
  /// Listening is what starts the platform watcher and cancelling is what stops
  /// it, so a subscription held only while the app is in the foreground is also
  /// a watcher that only runs then. That is not an optimisation: Android will
  /// not let a background app read the clipboard at all, so a watcher running
  /// there would report changes nobody could act on.
  Stream<void> get changes;
}

/// The real one, backed by the platform code in the runner for each OS.
final class PlatformClipboardWatcher implements ClipboardWatcher {
  const PlatformClipboardWatcher();

  static const EventChannel _channel =
      EventChannel('com.remotelink.app/clipboard_changes');

  static final Log _log = Log.scoped('mobile.clipboard.watcher');

  @override
  Stream<void> get changes =>
      _channel.receiveBroadcastStream().map((_) {}).handleError(
        (Object error) {
          // A platform with no watcher in its runner, or an engine that has
          // not registered one yet. Automatic sync is what degrades here, not
          // the app: the foreground-resume read and the Send button both still
          // work, so this is worth a line in the log and nothing louder.
          _log.debug(() => 'no clipboard watcher on this platform: $error');
        },
      );
}

/// A watcher that never fires, for tests and for anywhere the real one has no
/// business running.
final class InertClipboardWatcher implements ClipboardWatcher {
  const InertClipboardWatcher();

  @override
  Stream<void> get changes => const Stream<void>.empty();
}
