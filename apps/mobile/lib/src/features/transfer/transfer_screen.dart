import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import 'file_picker.dart';
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

  /// What the user chose in the picker, in the order they chose it.
  final List<PickedFile> _picked = <PickedFile>[];

  /// True while a picker is open, so a second tap cannot stack two of them.
  bool _isPicking = false;

  String? _selectedTargetId;
  String? _statusError;

  @override
  void dispose() {
    _textController.dispose();
    _customNameController.dispose();
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
    // Re-checked against the current list every build rather than filled in
    // once. `DropdownButtonFormField` asserts when its value names no item, and
    // this list changes underneath it constantly: a computer drops off the
    // network, discovery reshuffles, a peer is forgotten in settings. Holding
    // an id that has gone would take down the whole Send tab.
    if (!targets.any((t) => t.id.value == _selectedTargetId)) {
      _selectedTargetId = switch ((connectedPeer, targets.isEmpty)) {
        (final peer?, _) => peer.id.value,
        (null, false) => targets.first.id.value,
        (null, true) => null,
      };
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
                ] else ...<Widget>[
                  _PickedFilesField(
                    picked: _picked,
                    isPhotoMode: _selectedType == 2,
                    isPicking: _isPicking,
                    onPick: _pick,
                    onRemove: (file) => setState(() => _picked.remove(file)),
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
                  // Disabled with nothing chosen, rather than enabled and then
                  // complaining. The button is the only place the state is
                  // visible, and an enabled Send that cannot send is the shape
                  // of the bug this screen already had once.
                  onPressed: isConnected &&
                          targets.isNotEmpty &&
                          (_selectedType == 0 || _picked.isNotEmpty)
                      ? () => _send(controller, targets)
                      : null,
                  icon: const Icon(Icons.send),
                  label: Text(_sendLabel),
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

  String get _sendLabel {
    if (_selectedType == 0) return 'Send Text';
    final noun = _selectedType == 2 ? 'Photo' : 'File';
    if (_picked.isEmpty) return 'Send $noun';
    if (_picked.length == 1) return 'Send 1 $noun';
    return 'Send ${_picked.length} ${noun}s';
  }

  Future<void> _pick() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _statusError = null;
    });

    final picker = ref.read(transferFilePickerProvider);
    try {
      final chosen = _selectedType == 2
          ? await picker.pickImages()
          : await picker.pickFiles();
      if (!mounted) return;
      setState(() {
        // Appended, not replaced. Picking twice is how the user assembles a
        // set from more than one place — a photo from the camera roll and a
        // PDF from Files — and replacing would silently discard the first.
        for (final file in chosen) {
          if (!_picked.any((p) => p.file.path == file.file.path)) {
            _picked.add(file);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      // A picker can fail for reasons the user can act on — a permission
      // refused, no photos app on the device — so this is shown rather than
      // swallowed. A cancel is not an error: it returns an empty list.
      setState(() => _statusError = 'Could not open the picker: $e');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
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
        if (_picked.isEmpty) {
          setState(
            () => _statusError = _selectedType == 2
                ? 'Choose at least one photo to send'
                : 'Choose at least one file to send',
          );
          return;
        }

        // Re-checked at send time, not only at pick time. Android can evict a
        // cached copy between the two, and the alternative — the transfer
        // engine throwing on `lengthSync` — surfaces as an unexplained failure
        // partway through the offer.
        final missing = _picked.where((p) => !p.file.existsSync()).toList();
        if (missing.isNotEmpty) {
          setState(() {
            _picked.removeWhere((p) => missing.contains(p));
            _statusError = missing.length == 1
                ? '${missing.first.displayName} is no longer available. '
                    'Choose it again.'
                : '${missing.length} files are no longer available. '
                    'Choose them again.';
          });
          return;
        }

        await controller.sendFiles(
          targetPeerId: target.id,
          targetPeerName: target.name,
          files: <File>[for (final p in _picked) p.file],
          fileNames: <String>[for (final p in _picked) p.displayName],
        );
        setState(_picked.clear);
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

/// The choose-files control and the list of what is currently chosen.
///
/// This replaced a text field that asked the user to type an absolute path,
/// next to a button that filled in a hard-coded sample one. Nothing about that
/// arrangement could send a real file, and on iOS — where an app cannot read
/// outside its own container without going through the picker — no typed path
/// would ever have worked.
class _PickedFilesField extends StatelessWidget {
  const _PickedFilesField({
    required this.picked,
    required this.isPhotoMode,
    required this.isPicking,
    required this.onPick,
    required this.onRemove,
  });

  final List<PickedFile> picked;
  final bool isPhotoMode;
  final bool isPicking;
  final Future<void> Function() onPick;
  final void Function(PickedFile) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final noun = isPhotoMode ? 'photos' : 'files';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: isPicking ? null : () => unawaited(onPick()),
          icon: isPicking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(isPhotoMode ? Icons.photo_library : Icons.folder_open),
          label: Text(
            picked.isEmpty ? 'Choose $noun' : 'Add more $noun',
          ),
        ),
        if (picked.isEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            isPhotoMode ? 'Opens your photo library.' : 'Opens your files.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ] else ...<Widget>[
          const SizedBox(height: 12),
          for (final file in picked)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  Icon(
                    isPhotoMode ? Icons.image_outlined : Icons.description,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatBytes(_lengthOrZero(file.file)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remove ${file.displayName}',
                    onPressed: () => onRemove(file),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  /// A size for the row, without letting a vanished file take down the build.
  ///
  /// `lengthSync` throws when the path no longer resolves, and a throw inside
  /// `build` is a red screen rather than a missing number. Send-time re-checks
  /// the file properly and tells the user; this only has to render.
  static int _lengthOrZero(File file) {
    try {
      return file.lengthSync();
    } on FileSystemException {
      return 0;
    }
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
