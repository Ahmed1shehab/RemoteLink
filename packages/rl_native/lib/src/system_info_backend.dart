import 'package:meta/meta.dart';

/// System metrics read from the host OS.
@immutable
final class SystemMetrics {
  const SystemMetrics({
    this.batteryPercent,
    this.isCharging,
    this.cpuPercent,
    this.memoryPercent,
    this.uptimeSeconds,
  });

  /// 0–100, or `null` if the host has no battery or cannot read it.
  final int? batteryPercent;

  /// Whether the host is connected to power/charging.
  final bool? isCharging;

  /// CPU utilisation percentage (0.0–100.0), or `null` if unavailable.
  final double? cpuPercent;

  /// RAM utilisation percentage (0.0–100.0), or `null` if unavailable.
  final double? memoryPercent;

  /// System uptime in seconds, or `null` if unavailable.
  final int? uptimeSeconds;
}

/// Reads host telemetry (battery, load, memory, uptime).
abstract interface class SystemInfoBackend {
  bool get isAvailable;

  /// Collects current host metrics.
  Future<SystemMetrics> metrics();

  void dispose();
}

/// Fallback backend for unsupported platforms.
final class UnsupportedSystemInfoBackend implements SystemInfoBackend {
  const UnsupportedSystemInfoBackend([this.unavailableReason]);

  final String? unavailableReason;

  @override
  bool get isAvailable => false;

  @override
  Future<SystemMetrics> metrics() async => const SystemMetrics();

  @override
  void dispose() {}
}
