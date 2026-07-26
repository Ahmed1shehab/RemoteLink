// ignore_for_file: constant_identifier_names
//
// CoreAudio constants keep Apple's four-character-code spelling so they can be
// checked against `AudioHardware.h` directly.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Builds a CoreAudio four-character code, e.g. `'dOut'`.
int _fourCC(String code) {
  assert(code.length == 4, 'four-character codes are exactly four characters');
  return (code.codeUnitAt(0) << 24) |
      (code.codeUnitAt(1) << 16) |
      (code.codeUnitAt(2) << 8) |
      code.codeUnitAt(3);
}

/// `kAudioObjectSystemObject`.
const int kAudioObjectSystemObject = 1;

/// `AudioObjectPropertyAddress`: selector, scope, element.
final class AudioObjectPropertyAddress extends Struct {
  @Uint32()
  external int selector;

  @Uint32()
  external int scope;

  @Uint32()
  external int element;
}

typedef _GetPropertyDataNative = Int32 Function(
  Uint32 objectId,
  Pointer<AudioObjectPropertyAddress> address,
  Uint32 qualifierDataSize,
  Pointer<Void> qualifierData,
  Pointer<Uint32> dataSize,
  Pointer<Void> data,
);
typedef _GetPropertyDataDart = int Function(
  int objectId,
  Pointer<AudioObjectPropertyAddress> address,
  int qualifierDataSize,
  Pointer<Void> qualifierData,
  Pointer<Uint32> dataSize,
  Pointer<Void> data,
);

/// Answers "is this Mac playing audio right now?".
///
/// ## Why this exists
///
/// macOS has no public API for "what is playing" — `MediaRemote` was closed to
/// unentitled processes in 15.4. But it does expose whether the output device
/// is *running*, which is a different and much cruder question that CoreAudio
/// answers happily.
///
/// That single bit is what makes browser playback reportable. A browser can be
/// asked for its tab title over AppleScript, but not whether that tab is making
/// noise; combining "audio is active" with "the front tab is called X" gives a
/// confident answer for the common case — the user is watching one thing — and
/// avoids the failure this replaces, where the phone said "nothing playing"
/// during a YouTube video.
///
/// It is a heuristic and is treated as one: it cannot tell *which* application
/// is producing sound, so a dedicated player is always asked first.
final class CoreAudioBindings {
  CoreAudioBindings()
      : _library = DynamicLibrary.open(
          '/System/Library/Frameworks/CoreAudio.framework/CoreAudio',
        ) {
    _getPropertyData =
        _library.lookupFunction<_GetPropertyDataNative, _GetPropertyDataDart>(
      'AudioObjectGetPropertyData',
    );
    _address = calloc<AudioObjectPropertyAddress>();
    _size = calloc<Uint32>();
    _result = calloc<Uint32>();
  }

  final DynamicLibrary _library;
  late final _GetPropertyDataDart _getPropertyData;

  late final Pointer<AudioObjectPropertyAddress> _address;
  late final Pointer<Uint32> _size;
  late final Pointer<Uint32> _result;

  static final int _defaultOutputDevice = _fourCC('dOut');
  static final int _isRunningSomewhere = _fourCC('gone');
  static final int _scopeGlobal = _fourCC('glob');

  /// True when the default output device is in use by any process.
  bool get isAudioActive {
    final deviceId = _queryUint32(
      kAudioObjectSystemObject,
      _defaultOutputDevice,
    );
    if (deviceId == null || deviceId == 0) return false;

    // `kAudioDevicePropertyDeviceIsRunningSomewhere` is the whole point: it
    // reports the device running for *anyone*, not just this process.
    return (_queryUint32(deviceId, _isRunningSomewhere) ?? 0) != 0;
  }

  int? _queryUint32(int objectId, int selector) {
    _address.ref
      ..selector = selector
      ..scope = _scopeGlobal
      ..element = 0;
    _size.value = sizeOf<Uint32>();
    _result.value = 0;

    final status = _getPropertyData(
      objectId,
      _address,
      0,
      nullptr,
      _size,
      _result.cast<Void>(),
    );
    return status == 0 ? _result.value : null;
  }

  void dispose() {
    calloc
      ..free(_address)
      ..free(_size)
      ..free(_result);
  }
}
