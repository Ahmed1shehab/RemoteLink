import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';

import '../brightness_backend.dart';
import 'coregraphics_ffi.dart';

/// `NSEventTypeSystemDefined`.
const int _nsEventTypeSystemDefined = 14;

/// Subtype 8 marks an event from the auxiliary (media/brightness) key hardware.
const int _auxKeySubtype = 8;

// `NX_KEYTYPE_*` from IOKit's `ev_keymap.h`.
const int _nxKeyBrightnessUp = 2;
const int _nxKeyBrightnessDown = 3;

typedef _Id = Pointer<Void>;
typedef _Sel = Pointer<Void>;

typedef _GetClassNative = _Id Function(Pointer<Utf8>);
typedef _GetClassDart = _Id Function(Pointer<Utf8>);

typedef _SelNative = _Sel Function(Pointer<Utf8>);
typedef _SelDart = _Sel Function(Pointer<Utf8>);

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

typedef _DisplayServicesGetBrightnessNative = Int32 Function(
  Uint32 display,
  Pointer<Float> brightness,
);
typedef _DisplayServicesGetBrightnessDart = int Function(
  int display,
  Pointer<Float> brightness,
);

typedef _DisplayServicesSetBrightnessNative = Int32 Function(
  Uint32 display,
  Float brightness,
);
typedef _DisplayServicesSetBrightnessDart = int Function(
  int display,
  double brightness,
);

/// macOS display brightness control.
///
/// ## Implementation strategy
///
/// 1. **Primary path (HID Media Keys via `CGEvent`)**:
///    Synthesises hardware brightness keys (`NX_KEYTYPE_BRIGHTNESS_UP` = 2,
///    `NX_KEYTYPE_BRIGHTNESS_DOWN` = 3) as `NSEventTypeSystemDefined` events
///    with subtype 8, converted to `CGEvent` and posted to `kCGHIDEventTap`.
///    This routes through macOS display brightness management identically to
///    the keyboard brightness keys on Apple hardware.
///
/// 2. **Direct Level APIs (`DisplayServices`)**:
///    Attempts to dynamically bind private `DisplayServicesGetBrightness` and
///    `DisplayServicesSetBrightness` from `DisplayServices.framework` to read
///    and set absolute float levels (`0.0`–`1.0`) when accessible.
///
/// 3. **AppleScript Fallback**:
///    Falls back to `osascript` key codes 144 (brightness up) and 145
///    (brightness down) when CGEvent posting is unavailable.
final class MacosBrightnessBackend implements BrightnessBackend {
  MacosBrightnessBackend() : _bindings = CoreGraphicsBindings() {
    _objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
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
    _brightnessPtr = calloc<Float>();

    _initDisplayServices();
  }

  final CoreGraphicsBindings _bindings;
  final Log _log = Log.scoped('native.brightness.macos');

  late final DynamicLibrary _objc;
  late final _OtherEventDart _otherEvent;
  late final _MsgSend0Dart _send0;
  late final _Id _nsEvent;
  late final _Sel _selOtherEvent;
  late final _Sel _selCgEvent;

  late final Pointer<CGPoint> _zero;
  late final Pointer<Float> _brightnessPtr;

  _DisplayServicesGetBrightnessDart? _dsGetBrightness;
  _DisplayServicesSetBrightnessDart? _dsSetBrightness;

  bool _disposed = false;
  bool _brightnessKeysFailed = false;
  double _currentLevel = 0.5;

  void _initDisplayServices() {
    try {
      final dsLib = DynamicLibrary.open(
        '/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices',
      );
      _dsGetBrightness = dsLib.lookupFunction<
          _DisplayServicesGetBrightnessNative,
          _DisplayServicesGetBrightnessDart>('DisplayServicesGetBrightness');
      _dsSetBrightness = dsLib.lookupFunction<
          _DisplayServicesSetBrightnessNative,
          _DisplayServicesSetBrightnessDart>('DisplayServicesSetBrightness');
    } catch (e) {
      _log.debug(() => 'DisplayServices private API unavailable: $e');
    }
  }

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

  @override
  String? get unavailableReason =>
      _disposed ? 'brightness backend is disposed' : null;

  void _postBrightnessKey(int keyCode) {
    if (_brightnessKeysFailed) return;

    for (final down in <bool>[true, false]) {
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
        _brightnessKeysFailed = true;
        _log.warn('could not construct a brightness key event');
        return;
      }

      final cgEvent = _send0(event, _selCgEvent);
      if (cgEvent == nullptr) continue;
      _bindings.post(kCGHIDEventTap, cgEvent);
    }
  }

  Future<void> _osascriptKey(int keyCode) async {
    try {
      await Process.run('osascript', <String>[
        '-e',
        'tell application "System Events" to key code $keyCode',
      ]);
    } on ProcessException catch (e) {
      _log.debug(
        () => 'osascript key code $keyCode failed: ${e.message}',
      );
    }
  }

  @override
  Future<double> level() async {
    if (_dsGetBrightness != null) {
      try {
        final display = _bindings.mainDisplayId();
        final res = _dsGetBrightness!(display, _brightnessPtr);
        if (res == 0) {
          _currentLevel = _brightnessPtr.value.clamp(0.0, 1.0);
        }
      } catch (e) {
        _log.debug(() => 'failed to query DisplayServices brightness: $e');
      }
    }
    return _currentLevel;
  }

  @override
  Future<void> setLevel(double level) async {
    final clamped = level.clamp(0.0, 1.0);
    var directSetSucceeded = false;

    if (_dsSetBrightness != null) {
      try {
        final display = _bindings.mainDisplayId();
        final res = _dsSetBrightness!(display, clamped);
        if (res == 0) {
          directSetSucceeded = true;
          _currentLevel = clamped;
        }
      } catch (e) {
        _log.debug(() => 'failed to set DisplayServices brightness: $e');
      }
    }

    if (!directSetSucceeded) {
      // Step delta approximation (macOS standard brightness step is 1/16).
      final delta = clamped - _currentLevel;
      final stepCount = (delta / 0.0625).round();

      if (stepCount > 0) {
        for (var i = 0; i < stepCount; i++) {
          if (!_brightnessKeysFailed) {
            _postBrightnessKey(_nxKeyBrightnessUp);
          } else {
            await _osascriptKey(144);
          }
        }
      } else if (stepCount < 0) {
        for (var i = 0; i < stepCount.abs(); i++) {
          if (!_brightnessKeysFailed) {
            _postBrightnessKey(_nxKeyBrightnessDown);
          } else {
            await _osascriptKey(145);
          }
        }
      }
      _currentLevel = clamped;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    calloc
      ..free(_zero)
      ..free(_brightnessPtr);
  }
}
