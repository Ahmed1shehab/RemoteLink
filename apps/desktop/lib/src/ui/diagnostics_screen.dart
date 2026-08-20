import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../app/providers.dart';
import '../app/theme.dart';

/// Diagnostics panel displaying service status, dispatcher counters,
/// backend availability with failure reasons, connected peers, and logs.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  LogLevel? _selectedLevel;
  StreamSubscription<LogRecord>? _logSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sink = ref.read(memoryLogSinkProvider);
      _logSubscription = sink.stream.listen((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diagnosticsAsync = ref.watch(desktopDiagnosticsProvider);
    final memorySink = ref.watch(memoryLogSinkProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: <Widget>[
          diagnosticsAsync.maybeWhen(
            data: (info) => FilledButton.tonalIcon(
              onPressed: () => _copyFullReport(context, info, memorySink),
              icon: const Icon(Icons.copy_all, size: 18),
              label: const Text('Copy All'),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: diagnosticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load diagnostics: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
        data: (info) => _buildContent(context, info, memorySink),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    DiagnosticsInfo info,
    MemoryLogSink memorySink,
  ) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'System health',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Network, permissions, connected devices, and live logs.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              _ServiceStatusCard(status: info.serviceStatus),
              const SizedBox(height: 16),
              _DispatcherCountersCard(counters: info.dispatcherCounters),
              const SizedBox(height: 16),
              _BackendsCard(backends: info.backends),
              const SizedBox(height: 16),
              _ConnectedDevicesCard(devices: info.devices),
              const SizedBox(height: 16),
              _LogViewerCard(
                records: memorySink.records,
                selectedLevel: _selectedLevel,
                onLevelSelected: (level) =>
                    setState(() => _selectedLevel = level),
                onCopyLogs: () => _copyLogs(context, memorySink.records),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copyFullReport(
    BuildContext context,
    DiagnosticsInfo info,
    MemoryLogSink memorySink,
  ) {
    final buffer = StringBuffer();
    final now = DateTime.now().toUtc().toIso8601String();

    buffer.writeln('=== Remote Link Desktop Diagnostics ===');
    buffer.writeln('Generated: $now');
    buffer.writeln();

    buffer.writeln('--- Service & Network ---');
    buffer.writeln(
        'State: ${info.serviceStatus.isRunning ? "Running" : "Stopped"}');
    buffer.writeln('Device Name: ${info.serviceStatus.deviceName}');
    buffer.writeln('Device ID: ${info.serviceStatus.deviceId}');
    buffer.writeln('Bound Port: ${info.serviceStatus.boundPort}');
    buffer.writeln('LAN Addresses:');
    if (info.serviceStatus.localAddresses.isEmpty) {
      buffer.writeln('  (none detected)');
    } else {
      for (final addr in info.serviceStatus.localAddresses) {
        buffer.writeln('  - $addr:${info.serviceStatus.boundPort}');
      }
    }
    buffer.writeln();

    buffer.writeln('--- Command Dispatcher ---');
    buffer.writeln('Applied: ${info.dispatcherCounters.applied}');
    buffer.writeln('Denied: ${info.dispatcherCounters.denied}');
    buffer.writeln('Unsupported: ${info.dispatcherCounters.unsupported}');
    buffer.writeln();

    buffer.writeln('--- Backends ---');
    _writeBackendReport(buffer, info.backends.input);
    _writeBackendReport(buffer, info.backends.clipboard);
    _writeBackendReport(buffer, info.backends.media);
    buffer.writeln();

    buffer.writeln('--- Connected Devices (${info.devices.length}) ---');
    if (info.devices.isEmpty) {
      buffer.writeln('No devices connected');
    } else {
      for (final device in info.devices) {
        buffer.writeln('- Name: ${device.name}');
        buffer.writeln('  Address: ${device.address}');
        buffer.writeln('  Tier: ${device.tier.name}');
        buffer
            .writeln('  RTT: ${device.roundTripMillis.toStringAsFixed(1)} ms');
        buffer.writeln('  Quality: ${device.qualityBars}/4 bars');
        if (device.awaitingPairing) {
          buffer.writeln('  Status: Awaiting pairing confirmation');
        }
      }
    }
    buffer.writeln();

    buffer
        .writeln('--- System Logs (${memorySink.records.length} records) ---');
    for (final record in memorySink.records) {
      buffer.writeln(record.toString());
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(content: Text('Full diagnostics copied to clipboard')),
    );
  }

  void _writeBackendReport(StringBuffer buffer, BackendDiagnostic backend) {
    buffer.write(
        '${backend.name}: ${backend.isAvailable ? "Available" : "Unavailable"}');
    if (!backend.isAvailable && backend.unavailableReason != null) {
      buffer.write(' (Reason: ${backend.unavailableReason})');
    }
    buffer.writeln();
  }

  void _copyLogs(BuildContext context, List<LogRecord> records) {
    final filtered = _selectedLevel == null
        ? records
        : records
            .where((r) => r.level.severity >= _selectedLevel!.severity)
            .toList();

    final text = filtered.map((r) => r.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Copied ${filtered.length} log records to clipboard'),
      ),
    );
  }
}

class _ServiceStatusCard extends StatelessWidget {
  const _ServiceStatusCard({required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.dns_outlined,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Service & Network',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: status.isRunning
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        status.isRunning
                            ? Icons.check_circle_outline
                            : Icons.pause_circle_outline,
                        size: 14,
                        color: status.isRunning
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        status.isRunning ? 'Running' : 'Stopped',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: status.isRunning
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow(context, 'Device Name', status.deviceName),
            const SizedBox(height: 6),
            _infoRow(context, 'Bound Port', 'Port ${status.boundPort}'),
            const SizedBox(height: 6),
            _infoRow(context, 'Device ID', status.deviceId, isMonospace: true),
            const SizedBox(height: 12),
            Text(
              'LAN Addresses for Phone Connection:',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            if (status.localAddresses.isEmpty)
              Text(
                'No LAN addresses detected',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  for (final address in status.localAddresses)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      child: SelectableText(
                        '$address:${status.boundPort}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    String label,
    String value, {
    bool isMonospace = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: isMonospace ? 'monospace' : null,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _DispatcherCountersCard extends StatelessWidget {
  const _DispatcherCountersCard({required this.counters});

  final DispatcherCounters counters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.speed_outlined,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Command Dispatcher',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _counterTile(
                    context,
                    label: 'Applied',
                    count: counters.applied,
                    color: colorScheme.primary,
                    icon: Icons.check_circle_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _counterTile(
                    context,
                    label: 'Denied',
                    count: counters.denied,
                    color: colorScheme.error,
                    icon: Icons.block_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _counterTile(
                    context,
                    label: 'Unsupported',
                    count: counters.unsupported,
                    color: colorScheme.outline,
                    icon: Icons.help_outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _counterTile(
    BuildContext context, {
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackendsCard extends StatelessWidget {
  const _BackendsCard({required this.backends});

  final BackendAvailability backends;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.extension_outlined,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Backend Availability',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _backendItem(context, backends.input, Icons.mouse_outlined),
            const Divider(height: 24),
            _backendItem(
                context, backends.clipboard, Icons.content_paste_outlined),
            const Divider(height: 24),
            _backendItem(context, backends.media, Icons.play_circle_outline),
          ],
        ),
      ),
    );
  }

  Widget _backendItem(
    BuildContext context,
    BackendDiagnostic backend,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                backend.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: backend.isAvailable
                    ? colorScheme.primaryContainer
                    : colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    backend.isAvailable
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 14,
                    color: backend.isAvailable
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    backend.isAvailable ? 'Available' : 'Unavailable',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: backend.isAvailable
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!backend.isAvailable &&
            backend.unavailableReason != null) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    backend.unavailableReason!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConnectedDevicesCard extends StatelessWidget {
  const _ConnectedDevicesCard({required this.devices});

  final List<DeviceDiagnostic> devices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.devices_outlined,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Connected Devices (${devices.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No devices connected.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              Column(
                children: <Widget>[
                  for (final device in devices) ...<Widget>[
                    _deviceTile(context, device),
                    if (device != devices.last) const Divider(height: 16),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(BuildContext context, DeviceDiagnostic device) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Icon(
          device.awaitingPairing ? Icons.hourglass_top : Icons.smartphone,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                device.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${device.address} · ${_tierLabel(device.tier)} · '
                '${device.roundTripMillis.toStringAsFixed(1)} ms · '
                '${device.qualityBars}/4 bars',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              // Named and explained rather than simply absent. Driving the
              // phone from here is a thing people ask for, and a feature that
              // is missing with no explanation is indistinguishable from one
              // that is broken.
              if (device.phoneControlBlocked != null) ...<Widget>[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.phonelink_off_outlined,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        device.phoneControlBlocked!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _tierLabel(PermissionTier tier) => switch (tier) {
        PermissionTier.readOnly => 'View only',
        PermissionTier.standard => 'Control',
        PermissionTier.extended => 'Control + apps',
        PermissionTier.admin => 'Full access',
      };
}

class _LogViewerCard extends StatelessWidget {
  const _LogViewerCard({
    required this.records,
    required this.selectedLevel,
    required this.onLevelSelected,
    required this.onCopyLogs,
  });

  final List<LogRecord> records;
  final LogLevel? selectedLevel;
  final ValueChanged<LogLevel?> onLevelSelected;
  final VoidCallback onCopyLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filteredRecords = selectedLevel == null
        ? records
        : records
            .where((r) => r.level.severity >= selectedLevel!.severity)
            .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.terminal_outlined,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'System Logs',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onCopyLogs,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Logs'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text(
                  'Filter Level:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<LogLevel?>(
                  value: selectedLevel,
                  underline: const SizedBox.shrink(),
                  onChanged: onLevelSelected,
                  items: const <DropdownMenuItem<LogLevel?>>[
                    DropdownMenuItem<LogLevel?>(
                      value: null,
                      child: Text('All Levels'),
                    ),
                    DropdownMenuItem<LogLevel?>(
                      value: LogLevel.trace,
                      child: Text('Trace (≥ trace)'),
                    ),
                    DropdownMenuItem<LogLevel?>(
                      value: LogLevel.debug,
                      child: Text('Debug (≥ debug)'),
                    ),
                    DropdownMenuItem<LogLevel?>(
                      value: LogLevel.info,
                      child: Text('Info (≥ info)'),
                    ),
                    DropdownMenuItem<LogLevel?>(
                      value: LogLevel.warn,
                      child: Text('Warn (≥ warn)'),
                    ),
                    DropdownMenuItem<LogLevel?>(
                      value: LogLevel.error,
                      child: Text('Error (≥ error)'),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'Showing ${filteredRecords.length} of ${records.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 320,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? colorScheme.surface
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: filteredRecords.isEmpty
                  ? Center(
                      child: Text(
                        'No logs recorded yet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredRecords.length,
                      itemBuilder: (context, index) {
                        final record = filteredRecords[index];
                        return _logRow(context, record);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logRow(BuildContext context, LogRecord record) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final levelColor = switch (record.level) {
      LogLevel.error => colorScheme.error,
      // `Colors.orange` is a mid-tone tuned for a white background and sat at
      // roughly 2:1 on the light surface this list is drawn on. See
      // [warningColor].
      LogLevel.warn => warningColor(colorScheme),
      LogLevel.info => colorScheme.primary,
      LogLevel.debug => colorScheme.onSurfaceVariant,
      LogLevel.trace => colorScheme.outline,
      LogLevel.off => colorScheme.outline,
    };

    final timeStr = record.time.toIso8601String().split('T').last;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText.rich(
        TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.4,
          ),
          children: <TextSpan>[
            TextSpan(
              text: '$timeStr ',
              style: TextStyle(color: colorScheme.outline),
            ),
            TextSpan(
              text: '[${record.level.name.toUpperCase().padRight(5)}] ',
              style: TextStyle(color: levelColor, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: '${record.scope}: ',
              style: TextStyle(color: colorScheme.onSurface),
            ),
            TextSpan(
              text: record.message,
              // `onSurface` rather than a hand-picked white/black pair: it is
              // the scheme's own guaranteed-contrast partner for the surface
              // this is painted on, in either theme.
              style: TextStyle(color: colorScheme.onSurface),
            ),
            if (record.fields.isNotEmpty)
              TextSpan(
                text:
                    ' ${record.fields.entries.map((e) => "${e.key}=${e.value}").join(" ")}',
                style: TextStyle(color: colorScheme.primary),
              ),
            if (record.error != null)
              TextSpan(
                text: ' error: ${record.error}',
                style: TextStyle(color: colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
