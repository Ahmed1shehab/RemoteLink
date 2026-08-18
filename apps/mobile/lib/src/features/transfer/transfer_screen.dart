import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/modern_ui.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import 'file_picker.dart';
import 'transfer_controller.dart';
import 'transfer_model.dart';

/// Send and receive media and file transfers on mobile.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  int _selectedType = 0; // 0 = Media, 1 = File

  /// What the user chose in the picker, in the order they chose it.
  final List<PickedFile> _picked = <PickedFile>[];

  /// True while a picker is open, so a second tap cannot stack two of them.
  bool _isPicking = false;

  String? _selectedTargetId;
  String? _statusError;

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

    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        if (transferState.pendingIncoming != null)
          _IncomingTransferBanner(
            request: transferState.pendingIncoming!,
            onAccept: () => controller
                .acceptIncomingTransfer(transferState.pendingIncoming!),
            onDecline: () => controller
                .declineIncomingTransfer(transferState.pendingIncoming!),
          ),
        AppSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.near_me_rounded, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Send to device',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Photos, videos, and files',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (targets.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'No paired or discovered computers found.',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedTargetId,
                  decoration: const InputDecoration(
                    labelText: 'Send to',
                    prefixIcon: Icon(Icons.computer_rounded),
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final t in targets)
                      DropdownMenuItem<String>(
                        value: t.id.value,
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: t.isLive
                                    ? const Color(0xFF22A06B)
                                    : scheme.outline,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                t.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (val) => setState(() => _selectedTargetId = val),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('Media'),
                      icon: Icon(Icons.photo_library_outlined),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('File'),
                      icon: Icon(Icons.folder_copy_outlined),
                    ),
                  ],
                  selected: <int>{_selectedType},
                  onSelectionChanged: (set) => setState(() {
                    _selectedType = set.first;
                    _statusError = null;
                  }),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: context.motion(const Duration(milliseconds: 220)),
                child: _PickedFilesField(
                  key: ValueKey<int>(_selectedType),
                  picked: _picked,
                  isMediaMode: _selectedType == 0,
                  isPicking: _isPicking,
                  onPick: _pick,
                  onRemove: (file) => setState(() => _picked.remove(file)),
                ),
              ),
              if (_statusError != null) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.error_outline_rounded,
                        color: scheme.error, size: 18),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _statusError!,
                        style: TextStyle(color: scheme.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      isConnected && targets.isNotEmpty && _picked.isNotEmpty
                          ? () => _send(controller, targets)
                          : null,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  label: Text(_sendLabel),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        AppSectionTitle(
          title: 'Transfers',
          subtitle: transferState.transfers.isEmpty
              ? 'Your recent activity appears here'
              : '${transferState.transfers.length} recent',
        ),
        const SizedBox(height: 12),
        if (transferState.transfers.isEmpty)
          const AppEmptyState(
            icon: Icons.swap_vert_rounded,
            title: 'No transfers yet',
            message: 'Anything you send or receive will stay visible here.',
          )
        else
          for (final transfer in transferState.transfers)
            _TransferCard(
              transfer: transfer,
              onCancel: () => controller.cancelTransfer(transfer.transferId),
              onRetry: () => _retryTransfer(controller, transfer.transferId),
              onDelete: () => controller.removeTransfer(transfer.transferId),
            ),
      ],
    );
  }

  String get _sendLabel {
    final noun = _selectedType == 0 ? 'Item' : 'File';
    if (_picked.isEmpty) return _selectedType == 0 ? 'Send Media' : 'Send File';
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
      final chosen = _selectedType == 0
          ? await picker.pickMedia()
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
      if (_picked.isEmpty) {
        setState(
          () => _statusError = _selectedType == 0
              ? 'Choose at least one photo or video to send'
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
    } catch (e) {
      setState(() => _statusError = 'Send failed: $e');
    }
  }

  Future<void> _retryTransfer(
    MobileTransferController controller,
    String transferId,
  ) async {
    try {
      await controller.retryTransfer(transferId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not retry: $error')),
      );
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
    required this.isMediaMode,
    required this.isPicking,
    required this.onPick,
    required this.onRemove,
    super.key,
  });

  final List<PickedFile> picked;
  final bool isMediaMode;
  final bool isPicking;
  final Future<void> Function() onPick;
  final void Function(PickedFile) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final noun = isMediaMode ? 'media' : 'files';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Material(
          color: scheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: isPicking ? null : () => unawaited(onPick()),
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 96),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: isPicking
                          ? const Padding(
                              padding: EdgeInsets.all(15),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              isMediaMode
                                  ? Icons.add_photo_alternate_outlined
                                  : Icons.note_add_outlined,
                              color: scheme.primary,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            picked.isEmpty ? 'Choose $noun' : 'Add more $noun',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isMediaMode
                                ? 'Pick photos or videos from your library'
                                : 'Browse files on this device',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (picked.isEmpty) ...<Widget>[
          const SizedBox.shrink(),
        ] else ...<Widget>[
          const SizedBox(height: 12),
          for (final file in picked)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isMediaMode
                          ? Icons.image_outlined
                          : Icons.description_outlined,
                      size: 20,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          file.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatBytes(_lengthOrZero(file.file)),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 21),
                    tooltip: 'Remove ${file.displayName}',
                    onPressed: () => onRemove(file),
                    color: scheme.error,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

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
    required this.onDelete,
  });

  final TransferRecord transfer;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncoming = transfer.direction == TransferDirection.incoming;

    return AppSectionCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  isIncoming
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 21,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      isIncoming
                          ? 'From ${transfer.peerName}'
                          : 'To ${transfer.peerName}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${transfer.files.length} ${transfer.files.length == 1 ? 'item' : 'items'} · ${formatBytes(transfer.totalBytes)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _StatusChip(status: transfer.status),
              if (!transfer.isActive) ...<Widget>[
                const SizedBox(width: 2),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 21),
                  tooltip: 'Delete transfer',
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
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
              borderRadius: BorderRadius.circular(20),
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
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Cancel',
                  color: scheme.error,
                ),
              if (transfer.canRetry)
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
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
