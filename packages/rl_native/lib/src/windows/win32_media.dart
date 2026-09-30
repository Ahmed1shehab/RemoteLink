import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../media_backend.dart';
import 'win32_ffi.dart';

const int _vkMediaNext = 0xb0;
const int _vkMediaPrevious = 0xb1;
const int _vkMediaStop = 0xb2;
const int _vkMediaPlayPause = 0xb3;

/// Returns the Windows hardware key for a transport command, if one exists.
///
/// Play and pause share a toggle key: Windows does not expose distinct global
/// keys for them. Seek, fast-forward, rewind, shuffle, and repeat have no
/// universal key either. Sending a different key for those actions would
/// surprise the user, so they are deliberately ignored until session control
/// is implemented.
int? windowsMediaVirtualKey(MediaAction action) => switch (action) {
      MediaAction.playPause ||
      MediaAction.play ||
      MediaAction.pause =>
        _vkMediaPlayPause,
      MediaAction.next => _vkMediaNext,
      MediaAction.previous => _vkMediaPrevious,
      MediaAction.stop => _vkMediaStop,
      MediaAction.seekForward ||
      MediaAction.seekBackward ||
      MediaAction.fastForward ||
      MediaAction.rewind ||
      MediaAction.shuffleToggle ||
      MediaAction.repeatToggle =>
        null,
    };

// The COM vtable signatures below use Pointer<Void> for `this` and HRESULT as
// Int32. The first three slots of every interface are IUnknown methods.
typedef _ReleaseNative = Uint32 Function(Pointer<Void>);
typedef _ReleaseDart = int Function(Pointer<Void>);
typedef _GetDefaultEndpointNative = Int32 Function(
    Pointer<Void>, Int32, Int32, Pointer<Pointer<Void>>);
typedef _GetDefaultEndpointDart = int Function(
    Pointer<Void>, int, int, Pointer<Pointer<Void>>);
typedef _ActivateNative = Int32 Function(Pointer<Void>, Pointer<GUID>, Uint32,
    Pointer<Void>, Pointer<Pointer<Void>>);
typedef _ActivateDart = int Function(
    Pointer<Void>, Pointer<GUID>, int, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _GetVolumeNative = Int32 Function(Pointer<Void>, Pointer<Float>);
typedef _GetVolumeDart = int Function(Pointer<Void>, Pointer<Float>);
typedef _SetVolumeNative = Int32 Function(Pointer<Void>, Float, Pointer<GUID>);
typedef _SetVolumeDart = int Function(Pointer<Void>, double, Pointer<GUID>);
typedef _GetMuteNative = Int32 Function(Pointer<Void>, Pointer<Int32>);
typedef _GetMuteDart = int Function(Pointer<Void>, Pointer<Int32>);
typedef _SetMuteNative = Int32 Function(Pointer<Void>, Int32, Pointer<GUID>);
typedef _SetMuteDart = int Function(Pointer<Void>, int, Pointer<GUID>);

int _slot(Pointer<Void> object, int index) =>
    object.cast<Pointer<IntPtr>>().value[index];

void _release(Pointer<Void> object) {
  if (object != nullptr) {
    Pointer<NativeFunction<_ReleaseNative>>.fromAddress(_slot(object, 2))
        .asFunction<_ReleaseDart>()(object);
  }
}

void _guid(Pointer<GUID> target, int a, int b, int c, List<int> tail) {
  target.ref
    ..Data1 = a
    ..Data2 = b
    ..Data3 = c;
  for (var i = 0; i < 8; i++) {
    target.ref.Data4[i] = tail[i];
  }
}

/// Windows transport keys and default output-device volume.
///
/// Media keys are sent as one down/up batch so the shell routes them to the
/// active media session just as it does a physical keyboard. Core Audio's
/// IAudioEndpointVolume provides actual master level and mute state; a local
/// estimate based on volume keys would drift when the user changes Windows'
/// slider or swaps output devices. Each volume operation reacquires the default
/// multimedia output, so device changes take effect without restarting.
///
/// No now-playing metadata is claimed: querying Windows media sessions needs
/// WinRT GlobalSystemMediaTransportControls, which is separate from these
/// system-wide transport keys.
final class WindowsMediaBackend implements MediaBackend {
  WindowsMediaBackend() : _bindings = Win32Bindings() {
    _batch = calloc<INPUT>(2);
    _coUninitialize = DynamicLibrary.open('ole32.dll')
        .lookupFunction<Void Function(), void Function()>('CoUninitialize');
  }

  final Win32Bindings _bindings;
  final Log _log = Log.scoped('native.media.win32');
  late final Pointer<INPUT> _batch;
  late final void Function() _coUninitialize;
  bool _disposed = false;

  @override
  bool get isAvailable => !_disposed;

  void _sendKey(int key) {
    for (var i = 0; i < 2; i++) {
      final input = _batch[i];
      input.type = INPUT_KEYBOARD;
      input.u.ki
        ..wVk = key
        ..wScan = 0
        ..dwFlags = KEYEVENTF_EXTENDEDKEY | (i == 1 ? KEYEVENTF_KEYUP : 0)
        ..time = 0
        ..dwExtraInfo = 0;
    }
    final sent = _bindings.sendInput(2, _batch, sizeOf<INPUT>());
    if (sent != 2) {
      _log.warn('SendInput accepted $sent of 2 media-key events',
          fields: <String, Object?>{'lastError': _bindings.getLastError()});
    }
  }

  @override
  Future<void> command(MediaAction action, {int seekSeconds = 10}) async {
    if (_disposed) return;
    final key = windowsMediaVirtualKey(action);
    if (key != null) _sendKey(key);
  }

  /// Opens the endpoint in the calling COM apartment and releases every object
  /// before returning. A volume call must not hold an IMMDevice across an
  /// `await`: the default device can change, and COM objects are apartment-bound.
  T? _withEndpoint<T>(T Function(Pointer<Void>) body) {
    if (_disposed) return null;
    final initialized = _bindings.coInitializeEx(nullptr, COINIT_MULTITHREADED);
    // RPC_E_CHANGED_MODE means this thread already has another apartment. It
    // can still call these interfaces, but must not balance someone else's init.
    if (initialized < 0 && initialized != -2147417850) return null;
    final mustUninitialize = initialized >= 0;
    final enumerator = calloc<Pointer<Void>>();
    final device = calloc<Pointer<Void>>();
    final endpoint = calloc<Pointer<Void>>();
    final clsid = calloc<GUID>();
    final iidEnumerator = calloc<GUID>();
    final iidVolume = calloc<GUID>();
    try {
      _guid(clsid, 0xbcde0395, 0xe52f, 0x467c,
          <int>[0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e]);
      _guid(iidEnumerator, 0xa95664d2, 0x9614, 0x4f35,
          <int>[0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6]);
      _guid(iidVolume, 0x5cdf2c82, 0x841e, 0x4546,
          <int>[0x97, 0x22, 0x0c, 0xf7, 0x40, 0x78, 0x22, 0x9a]);
      if (_bindings.coCreateInstance(
              clsid, nullptr, CLSCTX_INPROC_SERVER, iidEnumerator, enumerator) <
          0) {
        return null;
      }
      // eRender = 0, eMultimedia = 1.
      if (Pointer<NativeFunction<_GetDefaultEndpointNative>>.fromAddress(
                      _slot(enumerator.value, 4))
                  .asFunction<_GetDefaultEndpointDart>()(
              enumerator.value, 0, 1, device) <
          0) {
        return null;
      }
      if (Pointer<NativeFunction<_ActivateNative>>.fromAddress(
                      _slot(device.value, 3))
                  .asFunction<_ActivateDart>()(device.value, iidVolume,
              CLSCTX_INPROC_SERVER, nullptr, endpoint) <
          0) {
        return null;
      }
      return body(endpoint.value);
    } finally {
      _release(endpoint.value);
      _release(device.value);
      _release(enumerator.value);
      calloc.free(iidVolume);
      calloc.free(iidEnumerator);
      calloc.free(clsid);
      calloc.free(endpoint);
      calloc.free(device);
      calloc.free(enumerator);
      if (mustUninitialize) _coUninitialize();
    }
  }

  @override
  Future<VolumeState> volume() async =>
      _withEndpoint<VolumeState?>((endpoint) {
        final level = calloc<Float>();
        final mute = calloc<Int32>();
        try {
          final levelResult =
              Pointer<NativeFunction<_GetVolumeNative>>.fromAddress(
                      _slot(endpoint, 9))
                  .asFunction<_GetVolumeDart>()(endpoint, level);
          final muteResult =
              Pointer<NativeFunction<_GetMuteNative>>.fromAddress(
                      _slot(endpoint, 15))
                  .asFunction<_GetMuteDart>()(endpoint, mute);
          if (levelResult < 0 || muteResult < 0) {
            return null;
          }
          return VolumeState(level: level.value, muted: mute.value != 0);
        } finally {
          calloc.free(mute);
          calloc.free(level);
        }
      }) ??
      const VolumeState(level: 0, muted: false);

  @override
  Future<void> setVolume(double level) async {
    _withEndpoint((endpoint) {
      final result = Pointer<NativeFunction<_SetVolumeNative>>.fromAddress(
                  _slot(endpoint, 7))
              .asFunction<_SetVolumeDart>()(
          endpoint, level.clamp(0.0, 1.0), nullptr);
      if (result < 0) _log.warn('Core Audio rejected volume change: $result');
    });
  }

  @override
  Future<void> setMuted({required bool muted}) async {
    _withEndpoint((endpoint) {
      final result = Pointer<NativeFunction<_SetMuteNative>>.fromAddress(
              _slot(endpoint, 14))
          .asFunction<_SetMuteDart>()(endpoint, muted ? 1 : 0, nullptr);
      if (result < 0) _log.warn('Core Audio rejected mute change: $result');
    });
  }

  @override
  Future<NowPlaying?> nowPlaying() async => null;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    calloc.free(_batch);
  }
}
