import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../media_backend.dart';
import 'coreaudio_ffi.dart';
import 'coregraphics_ffi.dart';

/// `NSEventTypeSystemDefined`.
const int _nsEventTypeSystemDefined = 14;

/// Subtype 8 marks an event from the auxiliary (media) key hardware.
const int _auxKeySubtype = 8;

// `NX_KEYTYPE_*` from IOKit's `ev_keymap.h`. These are the codes the physical
// media keys on an Apple keyboard emit.
const int _nxKeyPlay = 16;
const int _nxKeyNext = 17;
const int _nxKeyPrevious = 18;
const int _nxKeyFast = 19;
const int _nxKeyRewind = 20;

typedef _Id = Pointer<Void>;
typedef _Sel = Pointer<Void>;

typedef _GetClassNative = _Id Function(Pointer<Utf8>);
typedef _GetClassDart = _Id Function(Pointer<Utf8>);

typedef _SelNative = _Sel Function(Pointer<Utf8>);
typedef _SelDart = _Sel Function(Pointer<Utf8>);

/// `+[NSEvent otherEventWithType:location:modifierFlags:timestamp:windowNumber:
/// context:subtype:data1:data2:]`
///
/// Ten arguments including an `NSPoint` by value. Spelled out explicitly rather
/// than reused from a generic helper: `objc_msgSend` has no single signature,
/// and getting one wrong here corrupts registers rather than failing to build.
typedef _OtherEventNative = _Id Function(
  _Id target,
  _Sel selector,
  Int64 type,
  CGPoint location,
  Uint64 modifierFlags,
  Double timestamp,
  Int64 windowNumber,
  _Id context,
  Int16 subtype,
  Int64 data1,
  Int64 data2,
);
typedef _OtherEventDart = _Id Function(
  _Id target,
  _Sel selector,
  int type,
  CGPoint location,
  int modifierFlags,
  double timestamp,
  int windowNumber,
  _Id context,
  int subtype,
  int data1,
  int data2,
);

typedef _MsgSend0Native = _Id Function(_Id target, _Sel selector);
typedef _MsgSend0Dart = _Id Function(_Id target, _Sel selector);

/// macOS media and volume control.
///
/// ## Why media keys, not an app-specific script
///
/// Telling Music or Spotify directly via AppleScript works, but only for the
/// apps you enumerated — it does nothing for a browser, a podcast player, or
/// whatever the user actually has open. Synthesising the *hardware media key*
/// routes through the same path as pressing the key on the keyboard, so
/// whichever app currently owns playback responds, including ones that did not
/// exist when this was written.
///
/// The catch is that media keys are not Quartz events. They are
/// `NSEventTypeSystemDefined` events with subtype 8, constructed through
/// AppKit, and only then converted to a `CGEvent` for posting. That is why this
/// reaches for `objc_msgSend` rather than the `CGEventCreate*` family used for
/// mouse and keyboard.
///
/// ## How now-playing is resolved
///
/// There is no public API for "what is this Mac playing" — `MediaRemote` was
/// the private framework everyone used, and Apple closed it to unentitled
/// processes in macOS 15.4. So it is reconstructed in three steps, most
/// trustworthy first:
///
/// 1. **Spotify and Music**, over AppleScript. Real title, artist, album,
///    position, and play state. Believed absolutely when present.
/// 2. **Is the output device running at all?** CoreAudio answers this for the
///    whole system without saying who is responsible.
/// 3. **If audio is active but no dedicated player owns it**, read the front
///    tab of whichever browser is running. That is almost always the answer:
///    one video, one browser, one person watching it.
///
/// Step 3 is a heuristic and is why step 1 exists — a dedicated player is never
/// second-guessed. It replaces a worse behaviour: reporting "nothing playing"
/// while a YouTube video was clearly running, which is not a limitation the
/// user should be asked to accept.
final class MacosMediaBackend implements MediaBackend {
  MacosMediaBackend() : _bindings = CoreGraphicsBindings() {
    _objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
    // AppKit must be loaded for NSEvent to exist; opening it is what links the
    // class into the process.
    DynamicLibrary.open('/System/Library/Frameworks/AppKit.framework/AppKit');

    final getClass =
        _objc.lookupFunction<_GetClassNative, _GetClassDart>('objc_getClass');
    final selector =
        _objc.lookupFunction<_SelNative, _SelDart>('sel_registerName');

    _otherEvent = _objc
        .lookupFunction<_OtherEventNative, _OtherEventDart>('objc_msgSend');
    _send0 =
        _objc.lookupFunction<_MsgSend0Native, _MsgSend0Dart>('objc_msgSend');

    _nsEvent = _withCString('NSEvent', getClass);
    _selOtherEvent = _withCString(
      'otherEventWithType:location:modifierFlags:timestamp:windowNumber:'
      'context:subtype:data1:data2:',
      selector,
    );
    _selCgEvent = _withCString('CGEvent', selector);

    _zero = calloc<CGPoint>();
  }

  final CoreGraphicsBindings _bindings;
  final CoreAudioBindings _audio = CoreAudioBindings();
  final Log _log = Log.scoped('native.media.macos');

  late final DynamicLibrary _objc;
  late final _OtherEventDart _otherEvent;
  late final _MsgSend0Dart _send0;
  late final _Id _nsEvent;
  late final _Sel _selOtherEvent;
  late final _Sel _selCgEvent;

  /// Reused origin for every event. Media keys carry no location.
  late final Pointer<CGPoint> _zero;

  bool _disposed = false;
  bool _mediaKeysFailed = false;

  static T _withCString<T>(String value, T Function(Pointer<Utf8>) body) {
    final native = value.toNativeUtf8();
    try {
      return body(native);
    } finally {
      calloc.free(native);
    }
  }

  @override
  bool get isAvailable => !_disposed;

  /// Posts one media key press and release.
  void _postMediaKey(int keyCode) {
    if (_mediaKeysFailed) return;

    for (final down in <bool>[true, false]) {
      // The flags encode the key and its direction into one integer, which is
      // how the auxiliary-key hardware reports itself.
      final flags = down ? 0xa00 : 0xb00;
      final data1 = (keyCode << 16) | flags;

      final event = _otherEvent(
        _nsEvent,
        _selOtherEvent,
        _nsEventTypeSystemDefined,
        _zero.ref,
        flags,
        0,
        0,
        nullptr,
        _auxKeySubtype,
        data1,
        -1,
      );
      if (event == nullptr) {
        _mediaKeysFailed = true;
        _log.warn('could not construct a media key event');
        return;
      }

      // `-[NSEvent CGEvent]` returns an autoreleased CGEventRef. It is used
      // immediately and never stored, so no retain is needed — the lesson from
      // the clipboard backend applies to references kept across an event-loop
      // turn, which this is not.
      final cgEvent = _send0(event, _selCgEvent);
      if (cgEvent == nullptr) continue;
      _bindings.post(kCGHIDEventTap, cgEvent);
    }
  }

  @override
  Future<void> command(MediaAction action, {int seekSeconds = 10}) async {
    final key = switch (action) {
      MediaAction.playPause ||
      MediaAction.play ||
      MediaAction.pause =>
        _nxKeyPlay,
      MediaAction.stop => _nxKeyPlay,
      MediaAction.next => _nxKeyNext,
      MediaAction.previous => _nxKeyPrevious,
      MediaAction.fastForward || MediaAction.seekForward => _nxKeyFast,
      MediaAction.rewind || MediaAction.seekBackward => _nxKeyRewind,
      // Shuffle and repeat have no media key. Silently doing nothing is better
      // than mapping them onto a key that means something else.
      MediaAction.shuffleToggle || MediaAction.repeatToggle => null,
    };
    if (key == null) {
      _log.debug(() => 'no media key for ${action.name}');
      return;
    }
    _postMediaKey(key);
  }

  /// Runs an AppleScript and returns its trimmed output.
  ///
  /// Used for volume and metadata rather than a native API because the public
  /// alternatives are worse: CoreAudio volume control means enumerating devices
  /// and handling their channel layouts, for a value that changes when a human
  /// drags a slider. A 20 ms subprocess is the right trade here and would not
  /// be on the input path.
  Future<String?> _osascript(String script) async {
    try {
      final result = await Process.run('osascript', <String>['-e', script]);
      if (result.exitCode != 0) return null;
      return (result.stdout as String).trim();
    } on ProcessException catch (e) {
      _log.debug(() => 'osascript failed: ${e.message}');
      return null;
    }
  }

  @override
  Future<VolumeState> volume() async {
    final output = await _osascript(
      'set v to get volume settings\n'
      'return (output volume of v as text) & "," & '
      '(output muted of v as text)',
    );
    if (output == null) return const VolumeState(level: 0, muted: false);

    final parts = output.split(',');
    final level = double.tryParse(parts.first.trim()) ?? 0;
    return VolumeState(
      level: (level / 100).clamp(0.0, 1.0),
      muted: parts.length > 1 && parts[1].trim().toLowerCase() == 'true',
    );
  }

  @override
  Future<void> setVolume(double level) async {
    final percent = (level.clamp(0.0, 1.0) * 100).round();
    await _osascript('set volume output volume $percent');
  }

  @override
  Future<void> setMuted({required bool muted}) async {
    await _osascript('set volume ${muted ? 'with' : 'without'} output muted');
  }

  /// Browsers that expose their front tab over AppleScript.
  ///
  /// Firefox is absent because it has no usable AppleScript dictionary — it
  /// exposes neither tab titles nor URLs, so there is nothing to read.
  static const Map<String, ({String title, String url})> _browsers =
      <String, ({String title, String url})>{
    'Safari': (
      title: 'name of current tab of front window',
      url: 'URL of current tab of front window',
    ),
    // Every Chromium browser shares one dictionary, so the same script works
    // for all of them.
    'Google Chrome': (
      title: 'title of active tab of front window',
      url: 'URL of active tab of front window',
    ),
    'Arc': (
      title: 'title of active tab of front window',
      url: 'URL of active tab of front window',
    ),
    'Brave Browser': (
      title: 'title of active tab of front window',
      url: 'URL of active tab of front window',
    ),
    'Microsoft Edge': (
      title: 'title of active tab of front window',
      url: 'URL of active tab of front window',
    ),
    'Vivaldi': (
      title: 'title of active tab of front window',
      url: 'URL of active tab of front window',
    ),
  };

  Future<bool> _isRunning(String app) async {
    final running = await _osascript(
      'tell application "System Events" to return '
      '(exists (processes where name is "$app")) as text',
    );
    return running?.toLowerCase() == 'true';
  }

  /// Reads the front tab of whichever supported browser is running.
  ///
  /// Reported only when audio is actually active, because a browser being open
  /// says nothing about whether it is playing anything. The pairing of "the
  /// output device is running" with "the front tab is called X" is a heuristic,
  /// and it is right in the case that matters: one video, one browser, one
  /// person watching it.
  Future<NowPlaying?> _browserNowPlaying() async {
    for (final entry in _browsers.entries) {
      if (!await _isRunning(entry.key)) continue;

      final info = await _osascript(
        'tell application "${entry.key}"\n'
        '  if (count of windows) is 0 then return ""\n'
        '  return (${entry.value.title}) & "\\n" & (${entry.value.url})\n'
        'end tell',
      );
      if (info == null || info.isEmpty) continue;

      final lines = info.split('\n');
      final title = lines.first.trim();
      if (title.isEmpty) continue;

      // Browser titles are usually "Video name - YouTube". Splitting the site
      // off gives something to put where an artist would go, and leaves the
      // actual name as the headline.
      final host = lines.length > 1 ? _hostOf(lines[1]) : null;
      final separator = title.lastIndexOf(' - ');
      final hasSuffix = separator > 0 && separator > title.length - 32;

      return NowPlaying(
        isPlaying: true,
        title: hasSuffix ? title.substring(0, separator) : title,
        artist: hasSuffix ? title.substring(separator + 3) : (host ?? ''),
        album: '',
        source: entry.key,
      );
    }
    return null;
  }

  static String? _hostOf(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host.replaceFirst(RegExp('^www\\.'), '');
  }

  @override
  Future<NowPlaying?> nowPlaying() async {
    // Dedicated players are asked first and trusted absolutely: they report
    // real metadata and a real play state, where everything below is inference.
    //
    // Only applications already running are asked — `tell application "Spotify"`
    // would otherwise *launch* Spotify, which is a spectacular way to fail at
    // reading metadata.
    for (final player in <String>['Spotify', 'Music']) {
      if (!await _isRunning(player)) continue;

      final info = await _osascript('''
tell application "$player"
  if player state is stopped then return ""
  set t to name of current track
  set a to artist of current track
  set b to album of current track
  set p to player position
  set d to (duration of current track)
  return t & "\\n" & a & "\\n" & b & "\\n" & (p as text) & "\\n" & (d as text) & "\\n" & (player state as text)
end tell
''');
      if (info == null || info.isEmpty) continue;

      final lines = info.split('\n');
      if (lines.length < 6) continue;

      // Spotify reports duration in milliseconds, Music in seconds. Getting
      // this wrong makes a three-minute song look like a fifty-hour one.
      final rawDuration = double.tryParse(lines[4]) ?? 0;
      final duration = player == 'Spotify' ? rawDuration / 1000 : rawDuration;

      return NowPlaying(
        isPlaying: lines[5].toLowerCase().contains('playing'),
        title: lines[0],
        artist: lines[1],
        album: lines[2],
        source: player,
        positionSeconds: double.tryParse(lines[3]) ?? 0,
        durationSeconds: duration,
      );
    }

    // Nothing dedicated is playing. If the Mac is making noise at all, it is
    // almost certainly the browser — so report what it is showing rather than
    // claiming nothing is playing while a video runs.
    if (_audio.isAudioActive) return _browserNowPlaying();
    return null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _audio.dispose();
    calloc.free(_zero);
  }
}
