import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../system_info_backend.dart';

// ── Mach & BSD Structs ───────────────────────────────────────────────────────

final class TimevalStruct extends Struct {
  @Int64()
  external int tvSec;

  @Int32()
  external int tvUsec;

  @Int32()
  external int padding;
}

final class VMStatistics64 extends Struct {
  @Uint32()
  external int freeCount;

  @Uint32()
  external int activeCount;

  @Uint32()
  external int inactiveCount;

  @Uint32()
  external int wireCount;

  @Uint64()
  external int zeroFillCount;

  @Uint64()
  external int reactivations;

  @Uint64()
  external int pageins;

  @Uint64()
  external int pageouts;

  @Uint64()
  external int faults;

  @Uint64()
  external int cowFaults;

  @Uint64()
  external int lookups;

  @Uint64()
  external int hits;

  @Uint64()
  external int purges;

  @Uint32()
  external int purgeableCount;

  @Uint32()
  external int speculativeCount;

  @Uint64()
  external int decompressions;

  @Uint64()
  external int compressions;

  @Uint64()
  external int swapins;

  @Uint64()
  external int swapouts;

  @Uint32()
  external int compressorPageCount;

  @Uint32()
  external int throttledCount;

  @Uint32()
  external int externalPageCount;

  @Uint32()
  external int internalPageCount;

  @Uint64()
  external int totalUncompressedPagesInCompressor;
}

final class HostCpuLoadInfo extends Struct {
  @Uint32()
  external int user;

  @Uint32()
  external int system;

  @Uint32()
  external int idle;

  @Uint32()
  external int nice;
}

// ── Native typedefs ──────────────────────────────────────────────────────────

typedef _SysctlByNameNative = Int32 Function(
  Pointer<Utf8> name,
  Pointer<Void> oldp,
  Pointer<Size> oldlenp,
  Pointer<Void> newp,
  Size newlen,
);
typedef _SysctlByNameDart = int Function(
  Pointer<Utf8> name,
  Pointer<Void> oldp,
  Pointer<Size> oldlenp,
  Pointer<Void> newp,
  int newlen,
);

typedef _MachHostSelfNative = Uint32 Function();
typedef _MachHostSelfDart = int Function();

typedef _HostStatistics64Native = Int32 Function(
  Uint32 hostPort,
  Int32 flavor,
  Pointer<Void> hostInfoOut,
  Pointer<Uint32> hostInfoOutCnt,
);
typedef _HostStatistics64Dart = int Function(
  int hostPort,
  int flavor,
  Pointer<Void> hostInfoOut,
  Pointer<Uint32> hostInfoOutCnt,
);

typedef _HostStatisticsNative = Int32 Function(
  Uint32 hostPort,
  Int32 flavor,
  Pointer<Void> hostInfoOut,
  Pointer<Uint32> hostInfoOutCnt,
);
typedef _HostStatisticsDart = int Function(
  int hostPort,
  int flavor,
  Pointer<Void> hostInfoOut,
  Pointer<Uint32> hostInfoOutCnt,
);

/// macOS host telemetry via sysctl, Mach host statistics, and pmset.
final class MacosSystemInfoBackend implements SystemInfoBackend {
  MacosSystemInfoBackend()
      : _libSystem = DynamicLibrary.open('/usr/lib/libSystem.B.dylib') {
    _sysctlByName =
        _libSystem.lookupFunction<_SysctlByNameNative, _SysctlByNameDart>(
      'sysctlbyname',
    );
    _machHostSelf =
        _libSystem.lookupFunction<_MachHostSelfNative, _MachHostSelfDart>(
      'mach_host_self',
    );
    _hostStatistics64 = _libSystem
        .lookupFunction<_HostStatistics64Native, _HostStatistics64Dart>(
      'host_statistics64',
    );
    _hostStatistics =
        _libSystem.lookupFunction<_HostStatisticsNative, _HostStatisticsDart>(
      'host_statistics',
    );

    _boottimeName = 'kern.boottime'.toNativeUtf8();
    _memsizeName = 'hw.memsize'.toNativeUtf8();
    _pagesizeName = 'hw.pagesize'.toNativeUtf8();

    _timevalPtr = calloc<TimevalStruct>();
    _sizePtr = calloc<Size>();
    _uint64Ptr = calloc<Uint64>();
    _int32Ptr = calloc<Int32>();
    _uint32CountPtr = calloc<Uint32>();
    _vmStatPtr = calloc<VMStatistics64>();
    _cpuLoadPtr = calloc<HostCpuLoadInfo>();
  }

  final DynamicLibrary _libSystem;
  late final _SysctlByNameDart _sysctlByName;
  late final _MachHostSelfDart _machHostSelf;
  late final _HostStatistics64Dart _hostStatistics64;
  late final _HostStatisticsDart _hostStatistics;

  late final Pointer<Utf8> _boottimeName;
  late final Pointer<Utf8> _memsizeName;
  late final Pointer<Utf8> _pagesizeName;

  late final Pointer<TimevalStruct> _timevalPtr;
  late final Pointer<Size> _sizePtr;
  late final Pointer<Uint64> _uint64Ptr;
  late final Pointer<Int32> _int32Ptr;
  late final Pointer<Uint32> _uint32CountPtr;
  late final Pointer<VMStatistics64> _vmStatPtr;
  late final Pointer<HostCpuLoadInfo> _cpuLoadPtr;

  static const int _hostVmInfo64 = 4;
  static const int _hostVmInfo64Count = 38;
  static const int _hostCpuLoadInfo = 3;
  static const int _hostCpuLoadInfoCount = 4;

  int? _prevUser;
  int? _prevSystem;
  int? _prevIdle;
  int? _prevNice;

  @override
  bool get isAvailable => true;

  @override
  Future<SystemMetrics> metrics() async {
    final battery = await _readBattery();
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

  int? _readUptime() {
    _sizePtr.value = sizeOf<TimevalStruct>();
    final status = _sysctlByName(
      _boottimeName,
      _timevalPtr.cast(),
      _sizePtr,
      nullptr,
      0,
    );
    if (status != 0) return null;
    final bootSec = _timevalPtr.ref.tvSec;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uptime = nowSec - bootSec;
    return uptime >= 0 ? uptime : 0;
  }

  double? _readMemoryPercent() {
    // Total physical memory
    _sizePtr.value = sizeOf<Uint64>();
    var status = _sysctlByName(
      _memsizeName,
      _uint64Ptr.cast(),
      _sizePtr,
      nullptr,
      0,
    );
    if (status != 0) return null;
    final totalBytes = _uint64Ptr.value;
    if (totalBytes == 0) return null;

    // Page size
    _sizePtr.value = sizeOf<Int32>();
    status = _sysctlByName(
      _pagesizeName,
      _int32Ptr.cast(),
      _sizePtr,
      nullptr,
      0,
    );
    final pageSize =
        status == 0 && _int32Ptr.value > 0 ? _int32Ptr.value : 4096;

    // VM statistics
    _uint32CountPtr.value = _hostVmInfo64Count;
    final host = _machHostSelf();
    final vmStatus = _hostStatistics64(
      host,
      _hostVmInfo64,
      _vmStatPtr.cast(),
      _uint32CountPtr,
    );
    if (vmStatus != 0) return null;

    final stat = _vmStatPtr.ref;
    final usedPages =
        stat.activeCount + stat.wireCount + stat.compressorPageCount;
    final usedBytes = usedPages * pageSize;
    return ((usedBytes / totalBytes) * 100.0).clamp(0.0, 100.0);
  }

  double? _readCpuPercent() {
    _uint32CountPtr.value = _hostCpuLoadInfoCount;
    final host = _machHostSelf();
    final status = _hostStatistics(
      host,
      _hostCpuLoadInfo,
      _cpuLoadPtr.cast(),
      _uint32CountPtr,
    );
    if (status != 0) return null;

    final info = _cpuLoadPtr.ref;
    final user = info.user;
    final system = info.system;
    final idle = info.idle;
    final nice = info.nice;

    double? result;
    if (_prevUser != null &&
        _prevSystem != null &&
        _prevIdle != null &&
        _prevNice != null) {
      final deltaUser = user - _prevUser!;
      final deltaSys = system - _prevSystem!;
      final deltaIdle = idle - _prevIdle!;
      final deltaNice = nice - _prevNice!;
      final total = deltaUser + deltaSys + deltaIdle + deltaNice;
      if (total > 0) {
        result = (((deltaUser + deltaSys + deltaNice) / total) * 100.0)
            .clamp(0.0, 100.0);
      }
    } else {
      final total = user + system + idle + nice;
      if (total > 0) {
        result = (((user + system + nice) / total) * 100.0).clamp(0.0, 100.0);
      }
    }

    _prevUser = user;
    _prevSystem = system;
    _prevIdle = idle;
    _prevNice = nice;

    return result;
  }

  Future<({int? percent, bool? isCharging})> _readBattery() async {
    try {
      final result = await Process.run('pmset', const <String>['-g', 'batt']);
      if (result.exitCode != 0) return (percent: null, isCharging: null);
      final output = result.stdout as String;
      final match = RegExp(r'(\d+)%').firstMatch(output);
      if (match == null) return (percent: null, isCharging: null);
      final percent = int.tryParse(match.group(1)!);
      if (percent == null) return (percent: null, isCharging: null);

      bool isCharging = false;
      if (output.contains('discharging')) {
        isCharging = false;
      } else if (output.contains('charging') ||
          output.contains('charged') ||
          output.contains('AC attached') ||
          output.contains("'AC Power'")) {
        isCharging = true;
      }
      return (percent: percent, isCharging: isCharging);
    } catch (_) {
      return (percent: null, isCharging: null);
    }
  }

  @override
  void dispose() {
    calloc
      ..free(_boottimeName)
      ..free(_memsizeName)
      ..free(_pagesizeName)
      ..free(_timevalPtr)
      ..free(_sizePtr)
      ..free(_uint64Ptr)
      ..free(_int32Ptr)
      ..free(_uint32CountPtr)
      ..free(_vmStatPtr)
      ..free(_cpuLoadPtr);
  }
}
