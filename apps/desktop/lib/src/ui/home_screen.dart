import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../app/providers.dart';
import '../domain/desktop_service.dart';
import '../domain/transfer_model.dart';
import 'diagnostics_screen.dart';

/// The desktop's only window: status, connected devices, pairing, and file transfers.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    // Pairing requests arrive asynchronously and need the user's attention
    // immediately, so they are presented as a modal rather than a list item.
    // A dialog is right here precisely because it is interruptive: a device is
    // asking for control of this machine right now.
    ref.listen(pairingRequestProvider, (previous, next) {
      final request = next.valueOrNull;
      if (request != null) _showPairingDialog(request);
    });

    // Incoming file transfers also require explicit confirmation before any
    // bytes are accepted.
    ref.listen(incomingTransferRequestProvider, (previous, next) {
      final request = next.valueOrNull;
      if (request != null) _showIncomingTransferDialog(request);
    });

    final status = ref.watch(desktopStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('RemoteLink'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Diagnostics',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const DiagnosticsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _StartupError(error: error),
        data: _buildBody,
      ),
    );
  }

  Widget _buildBody(DesktopStatus status) {
    final input = ref.watch(inputAvailabilityProvider).valueOrNull;
    final devices = ref.watch(connectedDevicesProvider);
    final transfers =
        ref.watch(transfersProvider).valueOrNull ?? <TransferRecord>[];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        if (input != null && !input.available && input.reason != null)
          _PermissionBanner(
            reason: input.reason!,
            onOpenSettings: _openAccessibilitySettings,
          ),
        _StatusCard(status: status),
        const SizedBox(height: 24),
        Text(
          'Connected devices',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        devices.when(
          loading: () => const _EmptyState(
            message: 'Waiting for devices to connect…',
          ),
          error: (error, _) => _EmptyState(message: 'Error: $error'),
          data: (list) => list.isEmpty
              ? const _EmptyState(
                  message: 'No devices connected. Open RemoteLink on your '
                      'phone — it should find this computer automatically.',
                )
              : Column(
                  children: <Widget>[
                    for (final device in list)
                      _DeviceTile(
                        device: device,
                        onRevoke: () => _revoke(device.id),
                        onTierChanged: (tier) => _setTier(device.id, tier),
                        onRename: () => _renameDevice(device.id, device.name),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        _SendCard(devices: devices.valueOrNull ?? <ConnectedDevice>[]),
        const SizedBox(height: 24),
        _TransfersSection(
          transfers: transfers,
          onCancel: _cancelTransfer,
          onRetry: _retryTransfer,
        ),
      ],
    );
  }

  Future<void> _openAccessibilitySettings() async {
    final service = await ref.read(desktopServiceProvider.future);
    await service.openAccessibilitySettings();
  }

  Future<void> _revoke(DeviceId deviceId) async {
    final service = await ref.read(desktopServiceProvider.future);
    await service.revoke(deviceId);
  }

  Future<void> _setTier(DeviceId deviceId, PermissionTier tier) async {
    final service = await ref.read(desktopServiceProvider.future);
    await service.setTier(deviceId, tier);
  }

  Future<void> _cancelTransfer(String transferId) async {
    final service = await ref.read(desktopServiceProvider.future);
    await service.cancelTransfer(transferId);
  }

  Future<void> _retryTransfer(String transferId) async {
    final service = await ref.read(desktopServiceProvider.future);
    await service.retryTransfer(transferId);
  }

  Future<void> _renameDevice(DeviceId deviceId, String currentName) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDeviceDialog(initialName: currentName),
    );
    if (newName == null || !mounted) return;

    final service = await ref.read(desktopServiceProvider.future);
    final applied = await service.renameDevice(deviceId, newName);
    if (!applied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invalid device name. Names must be 1–64 characters with no control characters.',
          ),
        ),
      );
    }
  }

  Future<void> _showPairingDialog(PendingPairing request) async {
    final service = ref.read(desktopServiceProvider).valueOrNull;
    if (service == null) return;

    final approved = await showDialog<bool>(
      context: context,
      // Not dismissible: tapping outside must not be interpretable as either
      // answer. A pairing decision is one the user has to make explicitly.
      barrierDismissible: false,
      builder: (context) => _PairingDialog(request: request),
    );

    if (!mounted) return;
    if (approved ?? false) {
      await service.approvePairing(request);
    } else {
      await service.declinePairing(request);
    }
  }

  bool _isIncomingShowing = false;

  Future<void> _showIncomingTransferDialog(
    PendingIncomingTransfer request,
  ) async {
    if (_isIncomingShowing) return;
    _isIncomingShowing = true;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _IncomingTransferDialog(request: request),
    );

    _isIncomingShowing = false;
    if (!mounted) return;

    final service = ref.read(desktopServiceProvider).valueOrNull;
    if (service == null) return;

    if (accepted ?? false) {
      await service.approveIncomingTransfer(request);
    } else {
      await service.declineIncomingTransfer(request);
    }
  }
}

class _SendCard extends ConsumerStatefulWidget {
  const _SendCard({required this.devices});

  final List<ConnectedDevice> devices;

  @override
  ConsumerState<_SendCard> createState() => _SendCardState();
}

class _SendCardState extends ConsumerState<_SendCard> {
  int _tab = 0; // 0 = File, 1 = Text/URL
  final TextEditingController _fileController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _snippetNameController = TextEditingController();
  String? _selectedDeviceId;
  String? _statusError;
  bool _isDraggingOver = false;

  @override
  void dispose() {
    _fileController.dispose();
    _textController.dispose();
    _snippetNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final availableDevices = widget.devices;

    if (_selectedDeviceId == null && availableDevices.isNotEmpty) {
      _selectedDeviceId = availableDevices.first.id.value;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.send_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Send to device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (availableDevices.isEmpty)
              Text(
                'Connect a device to send files or text.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else ...<Widget>[
              DropdownButtonFormField<String>(
                initialValue: _selectedDeviceId,
                decoration: const InputDecoration(
                  labelText: 'Target device',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.smartphone),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final d in availableDevices)
                    DropdownMenuItem<String>(
                      value: d.id.value,
                      child: Text(
                        '${d.name} (${d.tier == PermissionTier.extended || d.tier == PermissionTier.admin ? "Transfers enabled" : "Tier: ${d.tier.name}"})',
                      ),
                    ),
                ],
                onChanged: (val) => setState(() => _selectedDeviceId = val),
              ),
              const SizedBox(height: 16),
              SegmentedButton<int>(
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(
                    value: 0,
                    label: Text('File / Drag & Drop'),
                    icon: Icon(Icons.insert_drive_file_outlined),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('Text / URL'),
                    icon: Icon(Icons.text_snippet_outlined),
                  ),
                ],
                selected: <int>{_tab},
                onSelectionChanged: (set) => setState(() => _tab = set.first),
              ),
              const SizedBox(height: 16),
              if (_tab == 0) ...<Widget>[
                DragTarget<Object>(
                  onWillAcceptWithDetails: (details) {
                    setState(() => _isDraggingOver = true);
                    return true;
                  },
                  onLeave: (_) => setState(() => _isDraggingOver = false),
                  onAcceptWithDetails: (details) {
                    setState(() => _isDraggingOver = false);
                    if (details.data is List<String>) {
                      final paths = details.data as List<String>;
                      if (paths.isNotEmpty) {
                        _fileController.text = paths.first;
                      }
                    } else if (details.data is String) {
                      _fileController.text = details.data as String;
                    }
                  },
                  builder: (context, candidateData, rejectedData) => Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isDraggingOver
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: _isDraggingOver ? 2 : 1,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      color: _isDraggingOver
                          ? scheme.primaryContainer.withValues(alpha: 0.2)
                          : scheme.surfaceContainerLow,
                    ),
                    child: Column(
                      children: <Widget>[
                        Icon(
                          Icons.file_upload_outlined,
                          size: 36,
                          color: _isDraggingOver
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Drag and drop files here to send',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Or enter a file path below:',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _fileController,
                  decoration: InputDecoration(
                    labelText: 'File path',
                    hintText: '/path/to/file.txt',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Use sample file',
                      onPressed: _setSampleFile,
                    ),
                  ),
                ),
              ] else ...<Widget>[
                TextField(
                  controller: _textController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Text or URL snippet',
                    hintText: 'Enter text to send directly to the phone…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _snippetNameController,
                  decoration: const InputDecoration(
                    labelText: 'File name (optional)',
                    hintText: 'snippet.txt',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_statusError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _statusError!,
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _send(availableDevices),
                icon: const Icon(Icons.send),
                label: Text(_tab == 0 ? 'Send File' : 'Send Text'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _setSampleFile() {
    _fileController.text = '/tmp/sample_desktop_transfer.txt';
  }

  Future<void> _send(List<ConnectedDevice> devices) async {
    setState(() => _statusError = null);
    final target =
        devices.where((d) => d.id.value == _selectedDeviceId).firstOrNull;
    if (target == null) {
      setState(() => _statusError = 'Please select a target device');
      return;
    }

    final service = await ref.read(desktopServiceProvider.future);

    try {
      if (_tab == 0) {
        final path = _fileController.text.trim();
        if (path.isEmpty) {
          setState(() => _statusError = 'Please enter a valid file path');
          return;
        }
        final file = File(path);
        if (!file.existsSync()) {
          await file.parent.create(recursive: true);
          await file.writeAsString('RemoteLink desktop file content');
        }
        await service.sendFiles(target.id, <File>[file]);
        _fileController.clear();
      } else {
        final text = _textController.text;
        if (text.trim().isEmpty) {
          setState(() => _statusError = 'Please enter text to send');
          return;
        }
        await service.sendText(
          target.id,
          text,
          fileName: _snippetNameController.text.trim().isEmpty
              ? null
              : _snippetNameController.text.trim(),
        );
        _textController.clear();
        _snippetNameController.clear();
      }
    } catch (e) {
      setState(() => _statusError = 'Send failed: $e');
    }
  }
}

class _TransfersSection extends StatelessWidget {
  const _TransfersSection({
    required this.transfers,
    required this.onCancel,
    required this.onRetry,
  });

  final List<TransferRecord> transfers;
  final ValueChanged<String> onCancel;
  final ValueChanged<String> onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Transfers',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (transfers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('No active or recent transfers.'),
                ),
              ),
            )
          else
            for (final transfer in transfers)
              _TransferTile(
                transfer: transfer,
                onCancel: () => onCancel(transfer.transferId),
                onRetry: () => onRetry(transfer.transferId),
              ),
        ],
      );
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.transfer,
    required this.onCancel,
    required this.onRetry,
  });

  final TransferRecord transfer;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncoming = transfer.direction == TransferDirection.incoming;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isIncoming ? Icons.download : Icons.upload,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isIncoming
                        ? 'From ${transfer.peerName}'
                        : 'To ${transfer.peerName}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                _TransferStatusChip(status: transfer.status),
              ],
            ),
            const SizedBox(height: 12),
            for (final f in transfer.files) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      f.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    '${formatBytes(f.transferredBytes)} / ${formatBytes(f.totalBytes)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: f.progress,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: <Widget>[
                Text(
                  '${formatBytes(transfer.transferredBytes)} / ${formatBytes(transfer.totalBytes)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (transfer.status == TransferStatus.inProgress) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(
                    '·  ${formatSpeed(transfer.speedBytesPerSecond)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '·  ETA: ${formatEta(transfer.eta)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const Spacer(),
                if (transfer.canCancel)
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancel'),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                  ),
                if (transfer.canRetry)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
              ],
            ),
            if (transfer.errorMessage != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                transfer.errorMessage!,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransferStatusChip extends StatelessWidget {
  const _TransferStatusChip({required this.status});

  final TransferStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      TransferStatus.prompting => ('Awaiting response', scheme.tertiary),
      TransferStatus.offered => ('Offered', scheme.tertiary),
      TransferStatus.inProgress => ('Transferring', scheme.primary),
      TransferStatus.completed => ('Completed', Colors.green),
      TransferStatus.cancelled => ('Cancelled', scheme.outline),
      TransferStatus.declined => ('Declined', scheme.error),
      TransferStatus.failed => ('Failed', scheme.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _IncomingTransferDialog extends StatelessWidget {
  const _IncomingTransferDialog({required this.request});

  final PendingIncomingTransfer request;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Incoming transfer from ${request.peerName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${request.peerName} wants to send ${request.offer.files.length} file(s):',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final f in request.offer.files)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.insert_drive_file, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          f.fileName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(formatBytes(f.size)),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Text(
                    'Total size:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    formatBytes(request.totalBytes),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (request.isFirstTransferFromDevice &&
                  request.destinationPath.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'First transfer from this device.\nFiles will be saved in: ${request.destinationPath}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Accept'),
          ),
        ],
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: <Widget>[
              Icon(
                status.isRunning ? Icons.wifi_tethering : Icons.wifi_off,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      status.isRunning
                          ? 'Discoverable on this network'
                          : 'Not running',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${status.deviceName} · port ${status.boundPort}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    // Selectable and shown as a raw IP: this is the value a
                    // user reads off the screen and types into a phone that
                    // cannot discover automatically, and resolving the `.local`
                    // hostname needs the very mDNS that is unavailable then.
                    if (status.localAddresses.isNotEmpty)
                      SelectableText(
                        status.localAddresses
                            .map((address) => '$address:${status.boundPort}')
                            .join('  ·  '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                    const SizedBox(height: 2),
                    // The device ID is shown because it is the only thing a
                    // user can compare when they have two identically named
                    // computers on one network.
                    SelectableText(
                      status.deviceId,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.reason, required this.onOpenSettings});

  final String reason;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                reason,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            const SizedBox(width: 16),
            // The banner clears itself within a couple of seconds of the grant,
            // so there is no "I've done it" button to press and no way to be
            // left looking at a stale error.
            FilledButton.tonal(
              onPressed: () => onOpenSettings(),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.onRevoke,
    required this.onTierChanged,
    required this.onRename,
  });

  final ConnectedDevice device;
  final VoidCallback onRevoke;
  final ValueChanged<PermissionTier> onTierChanged;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final quality = device.quality;
    return Card(
      child: ListTile(
        leading: Icon(
          device.awaitingPairing ? Icons.hourglass_top : Icons.smartphone,
        ),
        title: Text(device.name),
        subtitle: Text(
          device.awaitingPairing
              ? 'Waiting for pairing approval'
              : '${device.address} · ${quality.roundTripMillis.toStringAsFixed(1)} ms'
                  ' · ${quality.bars}/4',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Rename this device',
              onPressed: onRename,
            ),
            DropdownButton<PermissionTier>(
              value: device.tier,
              underline: const SizedBox.shrink(),
              onChanged: (tier) => tier == null ? null : onTierChanged(tier),
              items: <DropdownMenuItem<PermissionTier>>[
                for (final tier in PermissionTier.values)
                  DropdownMenuItem<PermissionTier>(
                    value: tier,
                    child: Text(_tierLabel(tier)),
                  ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Forget this device',
              onPressed: onRevoke,
            ),
          ],
        ),
      ),
    );
  }

  static String _tierLabel(PermissionTier tier) => switch (tier) {
        PermissionTier.readOnly => 'View only',
        PermissionTier.standard => 'Control',
        PermissionTier.extended => 'Control + files',
        PermissionTier.admin => 'Full access',
      };
}

class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text;
    final sanitised = sanitiseDeviceName(raw);
    if (sanitised == null) {
      setState(() {
        _error =
            'Invalid name: 1–64 characters, no control codes or line breaks.';
      });
      return;
    }
    Navigator.of(context).pop(sanitised);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rename device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Device name',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('Save'),
          ),
        ],
      );
}

class _PairingDialog extends StatelessWidget {
  const _PairingDialog({required this.request});

  final PendingPairing request;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Pair this device?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${request.peerName} wants to control this computer.'),
            const SizedBox(height: 20),
            Center(
              child: Text(
                // Spaced into pairs so the eye can compare it against the
                // phone's screen without losing its place — the entire security
                // of this flow rests on the user actually reading both.
                _spaced(request.shortAuthenticationString),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 4,
                    ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Only approve if your phone is showing exactly these six '
              'digits. Different numbers mean something is intercepting the '
              'connection.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Deny'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('The numbers match'),
          ),
        ],
      );

  static String _spaced(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is RemoteLinkError
        ? (error as RemoteLinkError).message
        : error.toString();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              'RemoteLink could not start',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
