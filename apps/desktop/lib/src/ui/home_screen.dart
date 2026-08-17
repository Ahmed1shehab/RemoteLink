import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../domain/desktop_service.dart';
import '../domain/transfer_model.dart';
import 'clipboard_history_panel.dart';
import 'diagnostics_screen.dart';
import 'pairing_code.dart';

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

    // Permission elevation requests also require explicit user confirmation.
    ref.listen(permissionRequestProvider, (previous, next) {
      final request = next.valueOrNull;
      if (request != null) _showPermissionRequestDialog(request);
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

    // Tab order is pinned to the order the sections are read in, rather than
    // left to the default policy.
    //
    // The default is geometric, and this window is a single column only until
    // it is not: the permission banner appears and disappears, the device list
    // grows, and each device row ends in a cluster of a button, a dropdown, and
    // another button. Under the reading-order policy the focus jumped between
    // the send card and the device rows once a banner pushed the layout down,
    // which on a page whose controls revoke access and change permission tiers
    // is worse than merely confusing.
    final screenViewers =
        ref.watch(screenViewersProvider).valueOrNull ?? const <String>[];
    final screenCapture =
        ref.watch(screenCaptureAvailabilityProvider).valueOrNull;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          // Above the permission banner and everything else. This is the one
          // thing on this window that says the screen is leaving the machine,
          // and it is worth nothing if it is below the fold.
          if (screenViewers.isNotEmpty)
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: _ScreenSharingBanner(
                viewers: screenViewers,
                onStop: _stopAllScreenStreams,
              ),
            ),
          if (input != null && !input.available && input.reason != null)
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _PermissionBanner(
                reason: input.reason!,
                onOpenSettings: _openAccessibilitySettings,
              ),
            ),
          // Screen Recording is a separate grant in a separate pane, and
          // without a banner of its own there was nothing anywhere in the app
          // saying why screen sharing did not appear on the phone. The button
          // simply never showed up and the reason lived only in a log line.
          if (screenCapture != null && !screenCapture.available)
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _PermissionBanner(
                reason: screenCapture.reason ??
                    'RemoteLink needs Screen Recording permission before it '
                        'can share this screen.',
                onOpenSettings: _openScreenRecordingSettings,
                severity: _BannerSeverity.advisory,
              ),
            ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: _StatusCard(
              status: status,
              screenCaptureReady: screenCapture?.available ?? false,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Connected devices',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: devices.when(
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
                            onRename: () =>
                                _renameDevice(device.id, device.name),
                            onClipboardSyncChanged: (enabled) =>
                                _setClipboardSync(device.id, enabled),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child:
                _SendCard(devices: devices.valueOrNull ?? <ConnectedDevice>[]),
          ),
          const SizedBox(height: 24),
          FocusTraversalOrder(
            order: const NumericFocusOrder(5),
            child: _TransfersSection(
              transfers: transfers,
              onCancel: _cancelTransfer,
              onRetry: _retryTransfer,
            ),
          ),
          const SizedBox(height: 24),
          const FocusTraversalOrder(
            order: NumericFocusOrder(6),
            child: ClipboardHistoryPanel(),
          ),
        ],
      ),
    );
  }

  Future<void> _openAccessibilitySettings() async {
    final service = await ref.read(desktopServiceProvider.future);
    await service.openAccessibilitySettings();
  }

  Future<void> _openScreenRecordingSettings() async {
    final service = await ref.read(desktopServiceProvider.future);
    await service.openScreenRecordingSettings();
  }

  Future<void> _stopAllScreenStreams() async {
    final service = await ref.read(desktopServiceProvider.future);
    for (final device in service.devices) {
      await service.stopScreenStreamFor(device.id);
    }
  }

  Future<void> _revoke(DeviceId deviceId) async {
    final service = await ref.read(desktopServiceProvider.future);
    await service.revoke(deviceId);
  }

  Future<void> _setTier(DeviceId deviceId, PermissionTier tier) async {
    final service = await ref.read(desktopServiceProvider.future);
    await service.setTier(deviceId, tier);
  }

  Future<void> _setClipboardSync(DeviceId deviceId, bool enabled) async {
    final service = await ref.read(desktopServiceProvider.future);
    await service.setPeerClipboardSync(deviceId, enabled);
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
      builder: (context) => PairingDialog(
        peerName: request.peerName,
        shortAuthenticationString: request.shortAuthenticationString,
      ),
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

  bool _isPermissionRequestShowing = false;

  Future<void> _showPermissionRequestDialog(
    PendingPermissionRequest request,
  ) async {
    if (_isPermissionRequestShowing) return;
    _isPermissionRequestShowing = true;

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PermissionRequestDialog(
        peerName: request.peerName,
        requestedTier: request.requestedTier,
        currentTier: request.currentTier,
        justification: request.justification,
      ),
    );

    _isPermissionRequestShowing = false;
    if (!mounted) return;

    final service = ref.read(desktopServiceProvider).valueOrNull;
    if (service == null) return;

    if (approved ?? false) {
      await service.approvePermissionRequest(request);
    } else {
      await service.declinePermissionRequest(request);
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
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _snippetNameController = TextEditingController();

  /// Files chosen in the dialog or dropped on the window, in order.
  final List<File> _picked = <File>[];
  bool _isPicking = false;

  String? _selectedDeviceId;
  String? _statusError;
  bool _isDraggingOver = false;

  @override
  void dispose() {
    _textController.dispose();
    _snippetNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final availableDevices = widget.devices;

    // Re-checked against the current list every build, not just filled in when
    // null. A phone that disconnects leaves its id selected here, and
    // `DropdownButtonFormField` asserts when its value names no item — which
    // takes down this whole card, and with it the send controls, the transfer
    // list, and the clipboard panel below. Holding a stale id is the normal
    // course of events: devices come and go while this window stays open.
    final selectedStillPresent =
        availableDevices.any((d) => d.id.value == _selectedDeviceId);
    if (!selectedStillPresent) {
      _selectedDeviceId =
          availableDevices.isEmpty ? null : availableDevices.first.id.value;
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
                // `DropTarget`, not Flutter's `DragTarget`: the latter only
                // receives drags that began inside this app, so the zone that
                // used to be here looked identical and accepted nothing from
                // Finder or Explorer.
                DropTarget(
                  onDragEntered: (_) => setState(() => _isDraggingOver = true),
                  onDragExited: (_) => setState(() => _isDraggingOver = false),
                  onDragDone: (details) => _addDropped(details.files),
                  child: Container(
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
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed:
                              _isPicking ? null : () => unawaited(_pick()),
                          icon: const Icon(Icons.folder_open),
                          label: Text(
                            _picked.isEmpty ? 'Choose files' : 'Add more files',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_picked.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  for (final file in _picked)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.description,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              file.uri.pathSegments.last,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Remove ${file.uri.pathSegments.last}',
                            onPressed: () =>
                                setState(() => _picked.remove(file)),
                          ),
                        ],
                      ),
                    ),
                ],
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

  /// Adds dropped entries, ignoring directories and anything already listed.
  ///
  /// A dropped folder arrives as one `XFile` whose path is the directory. The
  /// transfer engine sends files, so expanding a folder would be a recursive
  /// walk with its own size and symlink questions — out of scope here, and
  /// silently sending nothing would be worse than saying so.
  void _addDropped(List<XFile> dropped) {
    final directories = <String>[];
    setState(() {
      _isDraggingOver = false;
      for (final entry in dropped) {
        if (FileSystemEntity.isDirectorySync(entry.path)) {
          directories.add(entry.name);
          continue;
        }
        if (_picked.any((f) => f.path == entry.path)) continue;
        _picked.add(File(entry.path));
      }
      _statusError = directories.isEmpty
          ? null
          : 'Folders cannot be sent yet: ${directories.join(", ")}';
    });
  }

  Future<void> _pick() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _statusError = null;
    });
    try {
      final chosen = await openFiles();
      if (!mounted) return;
      setState(() {
        for (final entry in chosen) {
          if (_picked.any((f) => f.path == entry.path)) continue;
          _picked.add(File(entry.path));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusError = 'Could not open the file dialog: $e');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
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
        if (_picked.isEmpty) {
          setState(() => _statusError = 'Choose at least one file to send');
          return;
        }
        // Re-checked here rather than trusted from pick time: a file can be
        // moved or deleted between choosing it and pressing Send, and the
        // transfer engine's failure for a missing file is far less clear than
        // this one.
        final missing = _picked.where((f) => !f.existsSync()).toList();
        if (missing.isNotEmpty) {
          setState(() {
            _picked.removeWhere(missing.contains);
            _statusError = missing.length == 1
                ? '${missing.first.uri.pathSegments.last} is no longer there.'
                : '${missing.length} files are no longer there.';
          });
          return;
        }
        await service.sendFiles(target.id, List<File>.of(_picked));
        setState(_picked.clear);
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
    final success = successColors(scheme);

    // Container/on-container pairs rather than one colour drawn at 15% alpha
    // behind itself. The old scheme failed contrast twice over: `Colors.green`
    // measured about 2.7:1 on the light theme's surface, and every status drew
    // its text in the same hue as its own background.
    final (label, background, foreground) = switch (status) {
      TransferStatus.prompting => (
          'Awaiting response',
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      TransferStatus.offered => (
          'Offered',
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      TransferStatus.inProgress => (
          'Transferring',
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      TransferStatus.completed => (
          'Completed',
          success.container,
          success.onContainer,
        ),
      TransferStatus.cancelled => (
          'Cancelled',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      TransferStatus.declined => (
          'Declined',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      TransferStatus.failed => (
          'Failed',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
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
          // Decline holds the initial focus, for the same reason Deny does on
          // the pairing dialog: this appears unprompted, and accepting writes
          // files someone else chose onto this machine.
          TextButton(
            autofocus: true,
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

class PermissionRequestDialog extends StatelessWidget {
  const PermissionRequestDialog({
    required this.peerName,
    required this.requestedTier,
    required this.currentTier,
    this.justification,
    super.key,
  });

  final String peerName;
  final PermissionTier requestedTier;
  final PermissionTier currentTier;
  final String? justification;

  static String _tierTitle(PermissionTier tier) => switch (tier) {
        PermissionTier.readOnly => 'View Only',
        PermissionTier.standard => 'Control',
        PermissionTier.extended => 'Control + File Transfer',
        PermissionTier.admin => 'Administrator (Full Access)',
      };

  // These are read by someone deciding whether to hand over their machine, so
  // they have to match `PermissionTier.allows` exactly. "Screen stream" used to
  // be listed under View Only and was left behind when streaming moved up to
  // Control — a dialog that overstates what a tier grants is worse than no
  // dialog, because it is trusted.
  static String _tierExplanation(PermissionTier tier) => switch (tier) {
        PermissionTier.readOnly =>
          'Allows viewing system status, media state, and the display layout — '
              'but not the contents of the screen.',
        PermissionTier.standard =>
          'Allows sending keyboard and mouse input, synchronizing clipboard, '
              'controlling media, and viewing this screen.',
        PermissionTier.extended =>
          'Allows transferring files, launching applications, and running pre-registered commands.',
        PermissionTier.admin =>
          'Allows controlling power (shutdown, restart, sleep, lock) and managing paired devices.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Permission elevation request'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: <TextSpan>[
                  TextSpan(
                    text: peerName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' is requesting '),
                  TextSpan(
                    text: _tierTitle(requestedTier),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: requestedTier == PermissionTier.admin
                          ? colorScheme.error
                          : colorScheme.primary,
                    ),
                  ),
                  const TextSpan(text: ' access to this computer.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'What this allows:',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tierExplanation(requestedTier),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (justification != null && justification!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                'Message from device:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '“$justification”',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            if (requestedTier == PermissionTier.admin) ...<Widget>[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.warning_amber_rounded,
                    color: colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Admin access allows restarting or shutting down your machine and discarding unsaved work.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        // Deny holds initial focus so pressing Enter/Space denies by default.
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Deny'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, this.screenCaptureReady = false});

  final DesktopStatus status;

  /// Whether this machine can currently share its screen.
  final bool screenCaptureReady;

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
                    // Screen sharing is started from the phone and has no
                    // control on this window at all, so with the permission
                    // granted the desktop said nothing about it whatsoever —
                    // and someone looking here for a "share screen" button
                    // found no button and no explanation of where it lives.
                    // The permission banner covers the not-granted case; this
                    // covers the far more confusing one where it works.
                    if (screenCaptureReady) ...<Widget>[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.screen_share_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Ready to share this screen — start it from the '
                              'phone, using the monitor button at the top of '
                              'its remote screen.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// Says, unmissably, that this screen is being watched — and by whom.
///
/// Screen streaming is the one capability here that runs continuously without
/// ever interrupting the user: pairing prompts, incoming transfers, and
/// permission elevation all stop and ask, while a stream starts because a
/// paired phone sent a message and then keeps going. This banner is what
/// replaces that prompt, so it is deliberately loud — error colouring rather
/// than a neutral chip — and it carries the control to end it, because the
/// person whose screen it is should not have to pick up the phone to stop it.
class _ScreenSharingBanner extends StatelessWidget {
  const _ScreenSharingBanner({required this.viewers, required this.onStop});

  final List<String> viewers;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = viewers.length == 1
        ? '${viewers.single} is watching this screen'
        : '${viewers.length} devices are watching this screen: '
            '${viewers.join(", ")}';

    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.screen_share, color: scheme.onErrorContainer),
            const SizedBox(width: 16),
            Expanded(
              // Announced as its own live region: a screen-reader user gets no
              // benefit from a visual banner, and this is exactly the kind of
              // state change they most need to hear about.
              child: Semantics(
                liveRegion: true,
                child: Text(
                  label,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.tonal(
              onPressed: () => onStop(),
              child: const Text('Stop sharing'),
            ),
          ],
        ),
      ),
    );
  }
}

/// How loudly a [_PermissionBanner] should present itself.
///
/// Accessibility is [blocking]: without it the app's whole reason for existing
/// does not work, and the phone's touchpad does nothing. Screen Recording is
/// [advisory] — everything else still works, one optional feature does not —
/// and painting both in error red would train the user to ignore the colour
/// that matters.
enum _BannerSeverity { blocking, advisory }

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({
    required this.reason,
    required this.onOpenSettings,
    this.severity = _BannerSeverity.blocking,
  });

  final String reason;
  final Future<void> Function() onOpenSettings;
  final _BannerSeverity severity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (severity) {
      _BannerSeverity.blocking => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.warning_amber_rounded,
        ),
      _BannerSeverity.advisory => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          Icons.info_outline,
        ),
    };

    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(icon, color: foreground),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                reason,
                style: TextStyle(color: foreground),
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
    required this.onClipboardSyncChanged,
  });

  final ConnectedDevice device;
  final VoidCallback onRevoke;
  final ValueChanged<PermissionTier> onTierChanged;
  final VoidCallback onRename;
  final ValueChanged<bool> onClipboardSyncChanged;

  @override
  Widget build(BuildContext context) {
    final quality = device.quality;
    final canSyncClipboard = device.tier.canSyncClipboard;

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
            Tooltip(
              message: canSyncClipboard
                  ? (device.clipboardSyncEnabled
                      ? 'Clipboard sync enabled'
                      : 'Clipboard sync disabled')
                  : 'Clipboard sync not permitted at current tier',
              child: Switch(
                value: canSyncClipboard && device.clipboardSyncEnabled,
                onChanged: canSyncClipboard
                    ? (val) => onClipboardSyncChanged(val)
                    : null,
              ),
            ),
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

/// Asks the user to confirm the six digits match the phone's.
///
/// Public, and taking the two strings rather than the [PendingPairing] it is
/// built from, so a test can drive the real dialog. The alternative — a private
/// widget behind a `ServerSession` — is a security-critical screen that cannot
/// be asserted on, and the assertions here are the point: what the digits
/// announce as, and which button the keyboard starts on.
class PairingDialog extends StatelessWidget {
  const PairingDialog({
    required this.peerName,
    required this.shortAuthenticationString,
    super.key,
  });

  final String peerName;

  /// Six digits the user compares against the phone's screen.
  final String shortAuthenticationString;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Pair this device?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('$peerName wants to control this computer.'),
            const SizedBox(height: 20),
            // Grouped for the eye and announced digit by digit — see
            // [PairingCodeDisplay]. The entire security of this flow rests on
            // the user actually comparing both screens, which means the code
            // has to arrive in a comparable form through whichever sense they
            // are using.
            Center(
              child: PairingCodeDisplay(digits: shortAuthenticationString),
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
          // Deny holds the initial focus, so Return approves nothing.
          //
          // Focus has to start somewhere in a modal, and on every other dialog
          // the convention is the affirmative button. Not here: this one is a
          // security decision, it appears unprompted the moment a stranger's
          // phone reaches the machine, and a user who hits Return on a dialog
          // they have not read yet must not thereby hand over control of their
          // computer. Denying is recoverable in a way approving is not — the
          // phone can simply ask again.
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Deny'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('The numbers match'),
          ),
        ],
      );
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
