import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import 'transfer_controller.dart';
import 'transfer_model.dart';

/// Send & receive file and text transfer tab for mobile.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  int _selectedType = 0; // 0 = Text/URL, 1 = File, 2 = Photo
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _filePathController = TextEditingController();
  String? _selectedTargetId;
  String? _statusError;

  @override
  void dispose() {
    _textController.dispose();
    _customNameController.dispose();
    _filePathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transferState = ref.watch(transferControllerProvider);
    final controller = ref.read(transferControllerProvider.notifier);

    final clientState = ref.watch(clientStateProvider).valueOrNull;
    final isConnected = clientState == ClientState.connected;
    final connectedPeer = ref.watch(connectedPeerProvider).valueOrNull;

    final discoveredList = ref.watch(discoveredDevicesProvider).valueOrNull ??
        <DiscoveredDevice>[];
    final trustedList =
        ref.watch(trustedPeersProvider).valueOrNull ?? <TrustedPeer>[];

    // Combine targets into a deduplicated list
    final targetMap = <String, ({DeviceId id, String name, bool isLive})>{};
    for (final d in discoveredList) {
      targetMap[d.id.value] = (
        id: d.id,
        name: d.name,
        isLive: true,
      );
    }
    for (final p in trustedList) {
      targetMap.putIfAbsent(
        p.id.value,
        () => (id: p.id, name: p.name, isLive: false),
      );
    }
    if (connectedPeer != null) {
      targetMap[connectedPeer.id.value] = (
        id: connectedPeer.id,
        name: connectedPeer.name,
        isLive: true,
      );
    }

    final targets = targetMap.values.toList();
    if (_selectedTargetId == null && targets.isNotEmpty) {
      if (connectedPeer != null) {
        _selectedTargetId = connectedPeer.id.value;
      } else {
        _selectedTargetId = targets.first.id.value;
      }
    }

    // Show incoming dialog if pending
    if (transferState.pendingIncoming != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showIncomingDialog(
            context, transferState.pendingIncoming!, controller);
      });
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (transferState.pendingIncoming != null)
          _IncomingTransferBanner(
            request: transferState.pendingIncoming!,
            onAccept: () => controller
                .acceptIncomingTransfer(transferState.pendingIncoming!),
            onDecline: () => controller
                .declineIncomingTransfer(transferState.pendingIncoming!),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Send to device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (targets.isEmpty)
                  Text(
                    'No paired or discovered computers found.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTargetId,
                    decoration: const InputDecoration(
                      labelText: 'Target device',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.computer),
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final t in targets)
                        DropdownMenuItem<String>(
                          value: t.id.value,
                          child: Text(
                            '${t.name} ${t.isLive ? "(online)" : "(offline)"}',
                          ),
                        ),
                    ],
                    onChanged: (val) => setState(() => _selectedTargetId = val),
                  ),
                const SizedBox(height: 16),
                SegmentedButton<int>(
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('Text / URL'),
                      icon: Icon(Icons.text_snippet_outlined),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('File'),
                      icon: Icon(Icons.insert_drive_file_outlined),
                    ),
                    ButtonSegment<int>(
                      value: 2,
                      label: Text('Photo'),
                      icon: Icon(Icons.photo_outlined),
                    ),
                  ],
                  selected: <int>{_selectedType},
                  onSelectionChanged: (set) =>
                      setState(() => _selectedType = set.first),
                ),
                const SizedBox(height: 16),
                if (_selectedType == 0) ...<Widget>[
                  TextField(
                    controller: _textController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Text, URL, or code snippet',
                      hintText: 'Enter text to send directly to the computer…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customNameController,
                    decoration: const InputDecoration(
                      labelText: 'File name (optional)',
                      hintText: 'snippet.txt',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else if (_selectedType == 1) ...<Widget>[
                  TextField(
                    controller: _filePathController,
                    decoration: InputDecoration(
                      labelText: 'File path',
                      hintText: '/path/to/document.pdf',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Sample file',
                        onPressed: _setSampleFile,
                      ),
                    ),
                  ),
                ] else ...<Widget>[
                  TextField(
                    controller: _filePathController,
                    decoration: InputDecoration(
                      labelText: 'Photo / Image path',
                      hintText: '/path/to/photo.jpg',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.image),
                        tooltip: 'Sample image',
                        onPressed: _setSampleImage,
                      ),
                    ),
                  ),
                ],
                if (_statusError != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _statusError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: isConnected && targets.isNotEmpty
                      ? () => _send(controller, targets)
                      : null,
                  icon: const Icon(Icons.send),
                  label: Text(
                    _selectedType == 0
                        ? 'Send Text'
                        : _selectedType == 1
                            ? 'Send File'
                            : 'Send Photo',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Transfers',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (transferState.transfers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No active or recent transfers.'),
              ),
            ),
          )
        else
          for (final transfer in transferState.transfers)
            _TransferCard(
              transfer: transfer,
              onCancel: () => controller.cancelTransfer(transfer.transferId),
              onRetry: () => controller.retryTransfer(transfer.transferId),
            ),
      ],
    );
  }

  void _setSampleFile() {
    _filePathController.text = '/sdcard/Download/sample_document.pdf';
  }

  void _setSampleImage() {
    _filePathController.text = '/sdcard/DCIM/Camera/photo_001.jpg';
  }

  Future<void> _send(
    MobileTransferController controller,
    List<({DeviceId id, String name, bool isLive})> targets,
  ) async {
    setState(() => _statusError = null);
    final target =
        targets.where((t) => t.id.value == _selectedTargetId).firstOrNull;
    if (target == null) {
      setState(() => _statusError = 'Please select a target device');
      return;
    }

    try {
      if (_selectedType == 0) {
        final text = _textController.text;
        if (text.trim().isEmpty) {
          setState(() => _statusError = 'Please enter text to send');
          return;
        }
        await controller.sendText(
          targetPeerId: target.id,
          targetPeerName: target.name,
          text: text,
          customFileName: _customNameController.text.trim().isEmpty
              ? null
              : _customNameController.text.trim(),
        );
        _textController.clear();
        _customNameController.clear();
      } else {
        final path = _filePathController.text.trim();
        if (path.isEmpty) {
          setState(() => _statusError = 'Please enter a valid file path');
          return;
        }
        final file = File(path);
        if (!file.existsSync()) {
          // If file doesn't exist on disk, create temporary dummy file for testing/demo
          await file.parent.create(recursive: true);
          await file.writeAsString('RemoteLink transfer payload');
        }
        await controller.sendFiles(
          targetPeerId: target.id,
          targetPeerName: target.name,
          files: <File>[file],
        );
        _filePathController.clear();
      }
    } catch (e) {
      setState(() => _statusError = 'Send failed: $e');
    }
  }

  bool _isDialogShowing = false;

  void _showIncomingDialog(
    BuildContext context,
    PendingIncomingTransfer request,
    MobileTransferController controller,
  ) {
    if (_isDialogShowing) return;
    _isDialogShowing = true;

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _IncomingTransferDialog(request: request),
    ).then((accepted) {
      _isDialogShowing = false;
      if (accepted == true) {
        unawaited(controller.acceptIncomingTransfer(request));
      } else {
        unawaited(controller.declineIncomingTransfer(request));
      }
    });
  }
}

class _IncomingTransferBanner extends StatelessWidget {
  const _IncomingTransferBanner({
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  final PendingIncomingTransfer request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.downloading, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Incoming transfer from ${request.peerName}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${request.offer.files.length} file(s) · ${formatBytes(request.totalBytes)}',
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
            if (request.isFirstTransferFromDevice &&
                request.destinationPath.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'First transfer: files will be saved to ${request.destinationPath}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: onDecline,
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
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

class _TransferCard extends StatelessWidget {
  const _TransferCard({
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
                _StatusChip(status: transfer.status),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TransferStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final success = successColors(scheme);

    // Container/on-container pairs rather than one colour drawn at 15% alpha
    // behind itself. The old scheme failed contrast twice over: `Colors.green`
    // measured about 2.7:1 on the light theme's surface, and every status drew
    // its text in the same hue as its own background.
    // Material 3 defines these pairs to meet 4.5:1 in both themes.
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
