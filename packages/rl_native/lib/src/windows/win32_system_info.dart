// ignore_for_file: camel_case_types, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../system_info_backend.dart';

// ── Win32 Structs ────────────────────────────────────────────────────────────

final class SYSTEM_POWER_STATUS extends Struct {
  @Uint8()
  external int acLineStatus;

  @Uint8()
  external int batteryFlag;

  @Uint8()
  external int batteryLifePercent;

  @Uint8()
  external int systemStatusFlag;

  @Uint32()
  external int batteryLifeTime;

  @Uint32()
  external int batteryFullLifeTime;
}

final class MEMORYSTATUSEX extends Struct {
  @Uint32()
  external int dwLength;

  @Uint32()
  external int dwMemoryLoad;

  @Uint64()
  external int ullTotalPhys;

  @Uint64()
  external int ullAvailPhys;

  @Uint64()
  external int ullTotalPageFile;

  @Uint64()
  external int ullAvailPageFile;

  @Uint64()
  external int ullTotalVirtual;

  @Uint64()
  external int ullAvailVirtual;

  @Uint64()
  external int ullAvailExtendedVirtual;
}

final class FILETIME extends Struct {
  @Uint32()
  external int dwLowDateTime;

  @Uint32()
  external int dwHighDateTime;
}

// ── Win32 Typedefs ───────────────────────────────────────────────────────────

typedef _GetSystemPowerStatusNative = Int32 Function(
  Pointer<SYSTEM_POWER_STATUS> lpSystemPowerStatus,
);
typedef _GetSystemPowerStatusDart = int Function(
  Pointer<SYSTEM_POWER_STATUS> lpSystemPowerStatus,
);

typedef _GlobalMemoryStatusExNative = Int32 Function(
  Pointer<MEMORYSTATUSEX> lpBuffer,
);
typedef _GlobalMemoryStatusExDart = int Function(
  Pointer<MEMORYSTATUSEX> lpBuffer,
);

typedef _GetTickCount64Native = Uint64 Function();
typedef _GetTickCount64Dart = int Function();

typedef _GetSystemTimesNative = Int32 Function(
  Pointer<FILETIME> lpIdleTime,
  Pointer<FILETIME> lpKernelTime,
  Pointer<FILETIME> lpUserTime,
);
typedef _GetSystemTimesDart = int Function(
  Pointer<FILETIME> lpIdleTime,
  Pointer<FILETIME> lpKernelTime,
  Pointer<FILETIME> lpUserTime,
);

/// Windows host telemetry via Win32 flat C exports in kernel32.dll.
final class Win32SystemInfoBackend implements SystemInfoBackend {
  Win32SystemInfoBackend() : _kernel32 = DynamicLibrary.open('kernel32.dll') {
    _getSystemPowerStatus = _kernel32
        .lookupFunction<_GetSystemPowerStatusNative, _GetSystemPowerStatusDart>(
      'GetSystemPowerStatus',
    );
    _globalMemoryStatusEx = _kernel32
        .lookupFunction<_GlobalMemoryStatusExNative, _GlobalMemoryStatusExDart>(
      'GlobalMemoryStatusEx',
    );
    _getTickCount64 =
        _kernel32.lookupFunction<_GetTickCount64Native, _GetTickCount64Dart>(
      'GetTickCount64',
    );
    _getSystemTimes =
        _kernel32.lookupFunction<_GetSystemTimesNative, _GetSystemTimesDart>(
      'GetSystemTimes',
    );

    _powerStatusPtr = calloc<SYSTEM_POWER_STATUS>();
    _memoryStatusPtr = calloc<MEMORYSTATUSEX>();
    _idleTimePtr = calloc<FILETIME>();
    _kernelTimePtr = calloc<FILETIME>();
    _userTimePtr = calloc<FILETIME>();
  }

  final DynamicLibrary _kernel32;
  late final _GetSystemPowerStatusDart _getSystemPowerStatus;
  late final _GlobalMemoryStatusExDart _globalMemoryStatusEx;
  late final _GetTickCount64Dart _getTickCount64;
  late final _GetSystemTimesDart _getSystemTimes;

  late final Pointer<SYSTEM_POWER_STATUS> _powerStatusPtr;
  late final Pointer<MEMORYSTATUSEX> _memoryStatusPtr;
  late final Pointer<FILETIME> _idleTimePtr;
  late final Pointer<FILETIME> _kernelTimePtr;
  late final Pointer<FILETIME> _userTimePtr;

  int? _prevIdle;
  int? _prevKernel;
  int? _prevUser;

  @override
  bool get isAvailable => true;

  @override
  Future<SystemMetrics> metrics() async {
    final battery = _readBattery();
    final uptime = _readUptime();
    final memory = _readMemoryPercent();
    final cpu = _readCpuPercent();

    return SystemMetrics(
      batteryPercent: battery.percent,
      isCharging: battery.isCharging,
      uptimeSeconds: uptime,
      memoryPercent: memory,
      cpuPercent: cpu,
    );
  }

  ({int? percent, bool? isCharging}) _readBattery() {
    final status = _getSystemPowerStatus(_powerStatusPtr);
    if (status == 0) return (percent: null, isCharging: null);

    final power = _powerStatusPtr.ref;
    // batteryFlag == 128: No system battery
    // batteryLifePercent == 255: Unknown status
    if ((power.batteryFlag & 128) != 0 || power.batteryLifePercent == 255) {
      return (percent: null, isCharging: null);
    }

    final percent = power.batteryLifePercent.clamp(0, 100);
    // acLineStatus == 1: AC online, batteryFlag & 8: Charging
    final isCharging = power.acLineStatus == 1 || (power.batteryFlag & 8) != 0;
    return (percent: percent, isCharging: isCharging);
  }

  int? _readUptime() {
    final ticksMs = _getTickCount64();
    return ticksMs ~/ 1000;
  }

  double? _readMemoryPercent() {
    _memoryStatusPtr.ref.dwLength = sizeOf<MEMORYSTATUSEX>();
    final status = _globalMemoryStatusEx(_memoryStatusPtr);
    if (status == 0) return null;

    final mem = _memoryStatusPtr.ref;
    return mem.dwMemoryLoad.toDouble().clamp(0.0, 100.0);
  }

  double? _readCpuPercent() {
    final status = _getSystemTimes(_idleTimePtr, _kernelTimePtr, _userTimePtr);
    if (status == 0) return null;

    final idle = _fileTimeToUint64(_idleTimePtr.ref);
    final kernel = _fileTimeToUint64(_kernelTimePtr.ref);
    final user = _fileTimeToUint64(_userTimePtr.ref);

    double? result;
    if (_prevIdle != null && _prevKernel != null && _prevUser != null) {
      final deltaIdle = idle - _prevIdle!;
      final deltaKernel = kernel - _prevKernel!;
      final deltaUser = user - _prevUser!;
      final totalSys = deltaKernel + deltaUser;
      final totalBusy = totalSys - deltaIdle;
      if (totalSys > 0) {
        result = ((totalBusy / totalSys) * 100.0).clamp(0.0, 100.0);
      }
    }

    _prevIdle = idle;
    _prevKernel = kernel;
    _prevUser = user;
    return result;
  }

  int _fileTimeToUint64(FILETIME ft) =>
      (ft.dwHighDateTime << 32) | ft.dwLowDateTime;

  @override
  void dispose() {
    calloc
      ..free(_powerStatusPtr)
      ..free(_memoryStatusPtr)
      ..free(_idleTimePtr)
      ..free(_kernelTimePtr)
      ..free(_userTimePtr);
  }
}
