/// Native desktop integration for RemoteLink.
///
/// Everything here is `dart:ffi` rather than a Flutter platform channel. The
/// reasoning is latency: a `MethodChannel` round trip costs roughly 50 to 150
/// microseconds because it hops to the platform thread and back through a
/// message codec, whereas an FFI call into `SendInput` or `CGEventPost` is a
/// direct call costing tens of nanoseconds. At 240 Hz input that difference is
/// the gap between a cursor that tracks the finger and one that visibly lags.
/// It also means these packages are testable from `dart test` with no Flutter
/// engine.
library;

import 'dart:io';

import 'package:rl_core/rl_core.dart';

import 'src/brightness_backend.dart';
import 'src/input_backend.dart';
import 'src/macos/macos_brightness.dart';
import 'src/macos/macos_clipboard.dart';
import 'src/macos/macos_input.dart';
import 'src/macos/macos_media.dart';
import 'src/macos/macos_system_info.dart';
import 'src/media_backend.dart';
import 'src/system_info_backend.dart';
import 'src/windows/win32_brightness.dart';
import 'src/windows/win32_clipboard.dart';
import 'src/windows/win32_input.dart';
import 'src/windows/win32_system_info.dart';

export 'src/brightness_backend.dart';
export 'src/input_backend.dart';
export 'src/keymap.dart';
export 'src/macos/coreaudio_ffi.dart';
export 'src/macos/macos_brightness.dart';
export 'src/macos/macos_clipboard.dart';
export 'src/macos/macos_input.dart';
export 'src/macos/macos_media.dart';
export 'src/macos/macos_system_info.dart';
export 'src/media_backend.dart';
export 'src/system_info_backend.dart';
export 'src/windows/win32_brightness.dart';
export 'src/windows/win32_clipboard.dart';
export 'src/windows/win32_input.dart';
export 'src/windows/win32_system_info.dart';

/// Chooses the backend for the running platform.
///
/// Selection happens at run time rather than through conditional imports so
/// that both implementations stay in one binary and both compile on every
/// platform's analyzer run. That trade — a slightly larger binary — buys the
/// guarantee that a change to the Windows backend cannot silently break on a
/// macOS developer's machine, which is exactly the failure mode conditional
/// imports produce.
abstract final class NativeBackends {
  /// Builds the input backend, or an unsupported stub with a reason.
  static InputBackend createInput() {
    final log = Log.scoped('native.factory');
    try {
      if (Platform.isWindows) return Win32InputBackend();
      if (Platform.isMacOS) return MacosInputBackend();
      return UnsupportedInputBackend(
        'input injection is not implemented on ${Platform.operatingSystem}',
      );
    } on ArgumentError catch (e) {
      // Thrown by DynamicLibrary.open when a system library is missing — an
      // unusual but real situation on stripped or sandboxed systems.
      log.error('could not load native input libraries', error: e);
      return const UnsupportedInputBackend(
        'native input libraries could not be loaded',
      );
    }
  }

  /// Builds the clipboard backend, or an unsupported stub.
  static ClipboardBackend createClipboard() {
    final log = Log.scoped('native.factory');
    try {
      if (Platform.isWindows) return Win32ClipboardBackend();
      if (Platform.isMacOS) return MacosClipboardBackend();
      return const UnsupportedClipboardBackend();
    } on ArgumentError catch (e) {
      log.error('could not load native clipboard libraries', error: e);
      return const UnsupportedClipboardBackend();
    }
  }

  /// Builds the media backend, or an unsupported stub.
  ///
  /// Windows has an equivalent in `GlobalSystemMediaTransportControls`, which
  /// is a WinRT interface rather than a flat C export and therefore needs more
  /// than `DynamicLibrary.lookupFunction`. Until that is written, Windows gets
  /// the stub and the desktop simply does not advertise media control — which
  /// is why capability negotiation exists.
  static MediaBackend createMedia() {
    final log = Log.scoped('native.factory');
    try {
      if (Platform.isMacOS) return MacosMediaBackend();
      return const UnsupportedMediaBackend();
    } on ArgumentError catch (e) {
      log.error('could not load native media libraries', error: e);
      return const UnsupportedMediaBackend();
    }
  }

  /// Builds the brightness backend, or an unsupported stub.
  static BrightnessBackend createBrightness() {
    final log = Log.scoped('native.factory');
    try {
      if (Platform.isMacOS) return MacosBrightnessBackend();
      if (Platform.isWindows) return Win32BrightnessBackend();
      return const UnsupportedBrightnessBackend(
        'brightness is not supported on this platform',
      );
    } on ArgumentError catch (e) {
      log.error('could not load native brightness libraries', error: e);
      return const UnsupportedBrightnessBackend(
        'native brightness libraries could not be loaded',
      );
    }
  }

  /// Builds the system info backend, or an unsupported stub.
  static SystemInfoBackend createSystemInfo() {
    final log = Log.scoped('native.factory');
    try {
      if (Platform.isWindows) return Win32SystemInfoBackend();
      if (Platform.isMacOS) return MacosSystemInfoBackend();
      return const UnsupportedSystemInfoBackend(
        'system info is not implemented on this platform',
      );
    } on ArgumentError catch (e) {
      log.error('could not load native system info libraries', error: e);
      return const UnsupportedSystemInfoBackend(
        'native system info libraries could not be loaded',
      );
    }
  }

  /// Which platform this build is running on, in protocol terms.
  static PlatformKind get currentPlatform {
    if (Platform.isWindows) return PlatformKind.windows;
    if (Platform.isMacOS) return PlatformKind.macos;
    if (Platform.isLinux) return PlatformKind.linux;
    if (Platform.isAndroid) return PlatformKind.android;
    if (Platform.isIOS) return PlatformKind.ios;
    return PlatformKind.unknown;
  }
}
