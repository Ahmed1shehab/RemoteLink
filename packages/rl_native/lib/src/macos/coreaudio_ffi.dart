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

typedef _SetPropertyDataNative = Int32 Function(
  Uint32 objectId,
  Pointer<AudioObjectPropertyAddress> address,
  Uint32 qualifierDataSize,
  Pointer<Void> qualifierData,
  Uint32 dataSize,
  Pointer<Void> data,
);
typedef _SetPropertyDataDart = int Function(
  int objectId,
  Pointer<AudioObjectPropertyAddress> address,
  int qualifierDataSize,
  Pointer<Void> qualifierData,
  int dataSize,
  Pointer<Void> data,
);

typedef _HasPropertyNative = Uint8 Function(
  Uint32 objectId,
  Pointer<AudioObjectPropertyAddress> address,
);
typedef _HasPropertyDart = int Function(
  int objectId,
  Pointer<AudioObjectPropertyAddress> address,
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
    _setPropertyData =
        _library.lookupFunction<_SetPropertyDataNative, _SetPropertyDataDart>(
      'AudioObjectSetPropertyData',
    );
    _hasProperty =
        _library.lookupFunction<_HasPropertyNative, _HasPropertyDart>(
      'AudioObjectHasProperty',
    );
    _address = calloc<AudioObjectPropertyAddress>();
    _size = calloc<Uint32>();
    _result = calloc<Uint32>();
    _float = calloc<Float>();
  }

  final DynamicLibrary _library;
  late final _GetPropertyDataDart _getPropertyData;
  late final _SetPropertyDataDart _setPropertyData;
  late final _HasPropertyDart _hasProperty;

  late final Pointer<AudioObjectPropertyAddress> _address;
  late final Pointer<Uint32> _size;
  late final Pointer<Uint32> _result;
  late final Pointer<Float> _float;

  static final int _defaultOutputDevice = _fourCC('dOut');
  static final int _isRunningSomewhere = _fourCC('gone');
  static final int _scopeGlobal = _fourCC('glob');
  static final int _scopeOutput = _fourCC('outp');

  /// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`.
  ///
  /// The one selector that behaves the way a volume slider expects. Real
  /// devices differ wildly: some carry a main volume on element 0, some only
  /// per-channel volumes on elements 1 and 2, and some — HDMI, most USB
  /// interfaces — carry none at all. This is CoreAudio's own abstraction over
  /// that, and it is what the keyboard's volume keys drive.
  static final int _virtualMainVolume = _fourCC('vmvc');

  /// `kAudioDevicePropertyVolumeScalar`, used per channel when the above is
  /// absent.
  static final int _volumeScalar = _fourCC('volm');

  /// `kAudioDevicePropertyMute`.
  static final int _mute = _fourCC('mute');

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

  /// The default output device, or null when there is none.
  int? get _outputDevice {
    final id = _queryUint32(kAudioObjectSystemObject, _defaultOutputDevice);
    return (id == null || id == 0) ? null : id;
  }

  /// System output volume, 0…1, or null when the device exposes no control.
  ///
  /// Replaces `osascript -e 'get volume settings'`. That call is an Apple
  /// event, so on macOS 10.14 and later it is gated behind the Automation
  /// permission — and when the permission is missing it does not fail loudly,
  /// it fails as an exit code the caller reads as "volume is 0". The phone's
  /// slider sat at 0% and nothing anywhere said why. CoreAudio needs no
  /// permission at all.
  double? get volume {
    final device = _outputDevice;
    if (device == null) return null;

    final main = _queryFloat32(device, _virtualMainVolume, _scopeOutput, 0);
    if (main != null) return main.clamp(0.0, 1.0);

    // No main control. Devices in this shape carry one volume per channel, so
    // the loudest channel is the honest answer to "how loud is it".
    double? loudest;
    for (final channel in const <int>[1, 2]) {
      final value = _queryFloat32(device, _volumeScalar, _scopeOutput, channel);
      if (value == null) continue;
      loudest = loudest == null ? value : (value > loudest ? value : loudest);
    }
    return loudest?.clamp(0.0, 1.0);
  }

  /// Sets the system output volume. Returns whether anything accepted it.
  bool setVolume(double level) {
    final device = _outputDevice;
    if (device == null) return false;
    final clamped = level.clamp(0.0, 1.0).toDouble();

    if (_writeFloat32(device, _virtualMainVolume, _scopeOutput, 0, clamped)) {
      return true;
    }
    var wrote = false;
    for (final channel in const <int>[1, 2]) {
      if (_writeFloat32(
          device, _volumeScalar, _scopeOutput, channel, clamped)) {
        wrote = true;
      }
    }
    return wrote;
  }

  /// Whether output is muted, or null when the device has no mute control.
  bool? get isMuted {
    final device = _outputDevice;
    if (device == null) return null;
    final value = _queryUint32(device, _mute, scope: _scopeOutput);
    return value == null ? null : value != 0;
  }

  /// Mutes or unmutes output. Returns whether anything accepted it.
  bool setMuted({required bool muted}) {
    final device = _outputDevice;
    if (device == null) return false;

    _address.ref
      ..selector = _mute
      ..scope = _scopeOutput
      ..element = 0;
    if (_hasProperty(device, _address) == 0) return false;

    _result.value = muted ? 1 : 0;
    return _setPropertyData(
          device,
          _address,
          0,
          nullptr,
          sizeOf<Uint32>(),
          _result.cast<Void>(),
        ) ==
        0;
  }

  double? _queryFloat32(int objectId, int selector, int scope, int element) {
    _address.ref
      ..selector = selector
      ..scope = scope
      ..element = element;
    // Asked before reading rather than relying on the read's status code:
    // a device without the property returns an error that is indistinguishable
    // from a device that has it and failed, and the fallback path needs to
    // tell those apart.
    if (_hasProperty(objectId, _address) == 0) return null;

    _size.value = sizeOf<Float>();
    _float.value = 0;
    final status = _getPropertyData(
      objectId,
      _address,
      0,
      nullptr,
      _size,
      _float.cast<Void>(),
    );
    return status == 0 ? _float.value : null;
  }

  bool _writeFloat32(
    int objectId,
    int selector,
    int scope,
    int element,
    double value,
  ) {
    _address.ref
      ..selector = selector
      ..scope = scope
      ..element = element;
    if (_hasProperty(objectId, _address) == 0) return false;

    _float.value = value;
    return _setPropertyData(
          objectId,
          _address,
          0,
          nullptr,
          sizeOf<Float>(),
          _float.cast<Void>(),
        ) ==
        0;
  }

  int? _queryUint32(int objectId, int selector, {int? scope}) {
    _address.ref
      ..selector = selector
      ..scope = scope ?? _scopeGlobal
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
      ..free(_result)
      ..free(_float);
  }
}
