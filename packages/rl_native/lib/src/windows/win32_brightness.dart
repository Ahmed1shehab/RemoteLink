// ignore_for_file: camel_case_types, constant_identifier_names

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';

import '../brightness_backend.dart';

// ── Win32 Structs & Constants ────────────────────────────────────────────────

const int MONITOR_DEFAULTTOPRIMARY = 1;

final class PHYSICAL_MONITOR extends Struct {
  external Pointer<Void> hPhysicalMonitor;

  @Array(128)
  external Array<Uint16> szPhysicalMonitorDescription;
}

// ── Typedefs ─────────────────────────────────────────────────────────────────

typedef _MonitorFromWindowNative = Pointer<Void> Function(
  IntPtr hwnd,
  Uint32 dwFlags,
);
typedef _MonitorFromWindowDart = Pointer<Void> Function(
  int hwnd,
  int dwFlags,
);

typedef _GetNumberOfPhysicalMonitorsNative = Int32 Function(
  Pointer<Void> hMonitor,
  Pointer<Uint32> pdwNumberOfPhysicalMonitors,
);
typedef _GetNumberOfPhysicalMonitorsDart = int Function(
  Pointer<Void> hMonitor,
  Pointer<Uint32> pdwNumberOfPhysicalMonitors,
);

typedef _GetPhysicalMonitorsNative = Int32 Function(
  Pointer<Void> hMonitor,
  Uint32 dwPhysicalMonitorArraySize,
  Pointer<PHYSICAL_MONITOR> pPhysicalMonitorArray,
);
typedef _GetPhysicalMonitorsDart = int Function(
  Pointer<Void> hMonitor,
  int dwPhysicalMonitorArraySize,
  Pointer<PHYSICAL_MONITOR> pPhysicalMonitorArray,
);

typedef _GetMonitorBrightnessNative = Int32 Function(
  Pointer<Void> hPhysicalMonitor,
  Pointer<Uint32> pdwMinimumBrightness,
  Pointer<Uint32> pdwCurrentBrightness,
  Pointer<Uint32> pdwMaximumBrightness,
);
typedef _GetMonitorBrightnessDart = int Function(
  Pointer<Void> hPhysicalMonitor,
  Pointer<Uint32> pdwMinimumBrightness,
  Pointer<Uint32> pdwCurrentBrightness,
  Pointer<Uint32> pdwMaximumBrightness,
);

typedef _SetMonitorBrightnessNative = Int32 Function(
  Pointer<Void> hPhysicalMonitor,
  Uint32 dwNewBrightness,
);
typedef _SetMonitorBrightnessDart = int Function(
  Pointer<Void> hPhysicalMonitor,
  int dwNewBrightness,
);

typedef _DestroyPhysicalMonitorsNative = Int32 Function(
  Uint32 dwPhysicalMonitorArraySize,
  Pointer<PHYSICAL_MONITOR> pPhysicalMonitorArray,
);
typedef _DestroyPhysicalMonitorsDart = int Function(
  int dwPhysicalMonitorArraySize,
  Pointer<PHYSICAL_MONITOR> pPhysicalMonitorArray,
);

/// Windows display brightness control.
///
/// Handles both display types found on Windows systems:
/// 1. **DDC/CI External Monitors**: Controlled via `dxva2.dll` APIs
///    (`GetMonitorBrightness`, `SetMonitorBrightness`).
/// 2. **Internal Laptop Panels**: Controlled via WMI (`root\wmi` namespace
///    `WmiMonitorBrightness` and `WmiMonitorBrightnessMethods.WmiSetBrightness`).
final class Win32BrightnessBackend implements BrightnessBackend {
  Win32BrightnessBackend() {
    _initDxva2();
  }

  final Log _log = Log.scoped('native.brightness.windows');

  _MonitorFromWindowDart? _monitorFromWindow;
  _GetNumberOfPhysicalMonitorsDart? _getNumberOfPhysicalMonitors;
  _GetPhysicalMonitorsDart? _getPhysicalMonitors;
  _GetMonitorBrightnessDart? _getMonitorBrightness;
  _SetMonitorBrightnessDart? _setMonitorBrightness;
  _DestroyPhysicalMonitorsDart? _destroyPhysicalMonitors;

  bool _dxva2Available = false;
  bool _disposed = false;
  double _currentLevel = 0.5;

  void _initDxva2() {
    if (!Platform.isWindows) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final dxva2 = DynamicLibrary.open('dxva2.dll');

      _monitorFromWindow = user32.lookupFunction<_MonitorFromWindowNative,
          _MonitorFromWindowDart>('MonitorFromWindow');
      _getNumberOfPhysicalMonitors = dxva2.lookupFunction<
          _GetNumberOfPhysicalMonitorsNative, _GetNumberOfPhysicalMonitorsDart>(
        'GetNumberOfPhysicalMonitorsFromHMONITOR',
      );
      _getPhysicalMonitors = dxva2.lookupFunction<_GetPhysicalMonitorsNative,
          _GetPhysicalMonitorsDart>('GetPhysicalMonitorsFromHMONITOR');
      _getMonitorBrightness = dxva2.lookupFunction<_GetMonitorBrightnessNative,
          _GetMonitorBrightnessDart>('GetMonitorBrightness');
      _setMonitorBrightness = dxva2.lookupFunction<_SetMonitorBrightnessNative,
          _SetMonitorBrightnessDart>('SetMonitorBrightness');
      _destroyPhysicalMonitors = dxva2.lookupFunction<
          _DestroyPhysicalMonitorsNative,
          _DestroyPhysicalMonitorsDart>('DestroyPhysicalMonitors');

      _dxva2Available = true;
    } catch (e) {
      _log.debug(() => 'dxva2.dll not available or monitor API missing: $e');
    }
  }

  @override
  bool get isAvailable => !_disposed;

  @override
  String? get unavailableReason =>
      _disposed ? 'brightness backend is disposed' : null;

  @override
  Future<double> level() async {
    if (_disposed) return 0.0;

    // 1. Try DDC/CI external monitor via dxva2.
    if (_dxva2Available && _monitorFromWindow != null) {
      final hMonitor = _monitorFromWindow!(0, MONITOR_DEFAULTTOPRIMARY);
      if (hMonitor != nullptr) {
        final countPtr = calloc<Uint32>();
        try {
          if (_getNumberOfPhysicalMonitors!(hMonitor, countPtr) != 0 &&
              countPtr.value > 0) {
            final count = countPtr.value;
            final monitors = calloc<PHYSICAL_MONITOR>(count);
            try {
              if (_getPhysicalMonitors!(hMonitor, count, monitors) != 0) {
                final minPtr = calloc<Uint32>();
                final curPtr = calloc<Uint32>();
                final maxPtr = calloc<Uint32>();
                try {
                  if (_getMonitorBrightness!(
                        monitors[0].hPhysicalMonitor,
                        minPtr,
                        curPtr,
                        maxPtr,
                      ) !=
                      0) {
                    final min = minPtr.value;
                    final cur = curPtr.value;
                    final max = maxPtr.value;
                    if (max > min) {
                      _currentLevel = ((cur - min) / (max - min)).clamp(
                        0.0,
                        1.0,
                      );
                      return _currentLevel;
                    }
                  }
                } finally {
                  calloc
                    ..free(minPtr)
                    ..free(curPtr)
                    ..free(maxPtr);
                }
              }
            } finally {
              _destroyPhysicalMonitors!(count, monitors);
              calloc.free(monitors);
            }
          }
        } finally {
          calloc.free(countPtr);
        }
      }
    }

    // 2. Try WMI for laptop internal panels.
    final wmiLevel = await _getWmiBrightness();
    if (wmiLevel != null) {
      _currentLevel = (wmiLevel / 100.0).clamp(0.0, 1.0);
      return _currentLevel;
    }

    return _currentLevel;
  }

  @override
  Future<void> setLevel(double level) async {
    if (_disposed) return;
    final clamped = level.clamp(0.0, 1.0);
    var ddcSuccess = false;

    // 1. Try DDC/CI external monitor via dxva2.
    if (_dxva2Available && _monitorFromWindow != null) {
      final hMonitor = _monitorFromWindow!(0, MONITOR_DEFAULTTOPRIMARY);
      if (hMonitor != nullptr) {
        final countPtr = calloc<Uint32>();
        try {
          if (_getNumberOfPhysicalMonitors!(hMonitor, countPtr) != 0 &&
              countPtr.value > 0) {
            final count = countPtr.value;
            final monitors = calloc<PHYSICAL_MONITOR>(count);
            try {
              if (_getPhysicalMonitors!(hMonitor, count, monitors) != 0) {
                final minPtr = calloc<Uint32>();
                final curPtr = calloc<Uint32>();
                final maxPtr = calloc<Uint32>();
                try {
                  for (var i = 0; i < count; i++) {
                    if (_getMonitorBrightness!(
                          monitors[i].hPhysicalMonitor,
                          minPtr,
                          curPtr,
                          maxPtr,
                        ) !=
                        0) {
                      final min = minPtr.value;
                      final max = maxPtr.value;
                      final targetVal =
                          (min + clamped * (max - min)).round().clamp(min, max);
                      if (_setMonitorBrightness!(
                            monitors[i].hPhysicalMonitor,
                            targetVal,
                          ) !=
                          0) {
                        ddcSuccess = true;
                      }
                    }
                  }
                } finally {
                  calloc
                    ..free(minPtr)
                    ..free(curPtr)
                    ..free(maxPtr);
                }
              }
            } finally {
              _destroyPhysicalMonitors!(count, monitors);
              calloc.free(monitors);
            }
          }
        } finally {
          calloc.free(countPtr);
        }
      }
    }

    // 2. Try WMI for laptop internal panels.
    final wmiPercent = (clamped * 100).round();
    final wmiSuccess = await _setWmiBrightness(wmiPercent);

    if (ddcSuccess || wmiSuccess) {
      _currentLevel = clamped;
    } else {
      _currentLevel = clamped;
    }
  }

  Future<int?> _getWmiBrightness() async {
    try {
      final res = await Process.run('powershell', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness).CurrentBrightness',
      ]);
      if (res.exitCode == 0) {
        final text = (res.stdout as String).trim();
        return int.tryParse(text);
      }
    } catch (e) {
      _log.debug(() => 'WMI query failed: $e');
    }
    return null;
  }

  Future<bool> _setWmiBrightness(int levelPercent) async {
    try {
      final res = await Process.run('powershell', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods) | '
            'Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{Timeout=1; Brightness=$levelPercent}',
      ]);
      return res.exitCode == 0;
    } catch (e) {
      _log.debug(() => 'WMI set failed: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
  }
}
