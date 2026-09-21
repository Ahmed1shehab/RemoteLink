import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_icons.dart';
import '../../app/modern_ui.dart';
import '../../app/theme.dart';
import '../host/host_providers.dart';
import 'file_name_text.dart';
import 'file_picker.dart';
import 'image_preview.dart';
import 'transfer_controller.dart';
import 'transfer_model.dart';

/// Sending and receiving, on the phone.
///
/// The screen is two things stacked: one card that starts a send, and the list
/// of everything that has been sent or received. It used to be three, because
/// starting a send was itself a small form — pick a mode, open a picker, press
/// a button that was grey until all of it lined up — and the mode was a
/// distinction the phone cared about rather than one the user did. Nobody
/// thinks "I am in media mode"; they think "this photo".
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  /// What the user chose in the picker, in the order they chose it.
  final List<PickedFile> _picked = <PickedFile>[];

  /// True while a picker is open, so a second tap cannot stack two of them.
  bool _isPicking = false;

  /// Which device the user picked, when there is more than one to pick from.
  ///
  /// Held as an id rather than a [PeerLink], because a link is rebuilt whenever
  /// the connection behind it changes and holding the object would pin a stale
  /// session. Null means "whichever is first", which is the right answer while
  /// there is only one and a sane one the moment a second appears.
  DeviceId? _targetId;

  String? _statusError;

  @override
  Widget build(BuildContext context) {
    final transferState = ref.watch(transferControllerProvider);
    final controller = ref.read(transferControllerProvider.notifier);

    // Everything reachable, not just the computer being controlled. This is the
    // change that made the rest of the screen worth rewriting: there can now be
    // several real destinations at once — a computer this phone dialled, and
    // any phone that dialled it — where before there was one and the UI was
    // built around saying so.
    final links = ref.watch(peerLinksProvider);
    final target = _resolveTarget(links);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        AppSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SendHeader(target: target, choices: links.length),
              const SizedBox(height: 18),
              if (links.isEmpty)
                const _NothingToSendTo()
              else ...<Widget>[
                if (links.length > 1) ...<Widget>[
                  _DestinationPicker(
                    links: links,
                    selectedId: target?.id,
                    onSelected: (id) => setState(() => _targetId = id),
                  ),
                  const SizedBox(height: 16),
                ],
                _SourceButtons(
                  isPicking: _isPicking,
                  hasPicked: _picked.isNotEmpty,
                  onPickMedia: () => _pick(media: true),
                  onPickFiles: () => _pick(media: false),
                ),
                if (_picked.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  _PickedList(
                    picked: _picked,
                    onRemove: _removePicked,
                    onClear: () => setState(_picked.clear),
                  ),
                ],
                if (_statusError != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _SendProblem(
                    message: _statusError!,
                    onDismiss: () => setState(() => _statusError = null),
                  ),
                ],
                const SizedBox(height: 16),
                _SendButton(
                  target: target,
                  count: _picked.length,
                  onSend:
                      target == null ? null : () => _send(controller, target),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        const AppSectionTitle(
          title: 'Transfers',
        ),
        const SizedBox(height: 12),
        if (transferState.transfers.isEmpty)
          const AppEmptyState(
            icon: AppIcons.materialSwapVert,
            title: 'No transfers yet',
            message: 'Anything you send or receive will stay visible here.',
          )
        else
          for (final transfer in transferState.transfers)
            _TransferCard(
              transfer: transfer,
              onCancel: () => controller.cancelTransfer(transfer.transferId),
              onRetry: () => _retryTransfer(controller, transfer.transferId),
              onDelete: () => _deleteTransfer(controller, transfer),
            ),
      ],
    );
  }

  /// The device a send would go to.
  ///
  /// The chosen one while it is still there, and the first otherwise. A device
  /// that goes away mid-choice does not leave the button pointing at nothing:
  /// it falls back, and the picker shows the fallback selected, so what the
  /// button says and what it would do cannot disagree.
  PeerLink? _resolveTarget(List<PeerLink> links) {
    if (links.isEmpty) return null;
    final chosen = _targetId;
    if (chosen == null) return links.first;
    return links.where((link) => link.id == chosen).firstOrNull ?? links.first;
  }

  Future<void> _pick({required bool media}) async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _statusError = null;
    });

    final picker = ref.read(transferFilePickerProvider);
    try {
      final chosen =
          media ? await picker.pickMedia() : await picker.pickFiles();
      if (!mounted) return;
      setState(() {
        // Appended, not replaced. Picking twice is how the user assembles a
        // set from more than one place — a photo from the camera roll and a
        // PDF from Files — and replacing would silently discard the first.
        // That this now works across *both* buttons rather than only within
        // one mode is the point of having two buttons instead of a switch.
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

  void _removePicked(PickedFile file) {
    final index = _picked.indexOf(file);
    if (index == -1) return;
    setState(() => _picked.removeAt(index));
    showBottomUndoSnackBar(
      context,
      message: 'Deleted from selection',
      onUndo: () {
        if (!mounted) return;
        final restoreAt = index > _picked.length ? _picked.length : index;
        setState(() => _picked.insert(restoreAt, file));
      },
    );
  }

  Future<void> _send(
    MobileTransferController controller,
    PeerLink target,
  ) async {
    setState(() => _statusError = null);

    try {
      if (_picked.isEmpty) {
        setState(() => _statusError = 'Choose something to send first.');
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

      final count = _picked.length;
      await controller.sendFiles(
        targetPeerId: target.id,
        targetPeerName: target.name,
        files: <File>[for (final p in _picked) p.file],
        fileNames: <String>[for (final p in _picked) p.displayName],
      );
      setState(_picked.clear);

      // Said out loud, because the evidence otherwise is a row appearing in a
      // list further down the screen that the user may not have scrolled to.
      // An offer is also not an arrival — the other device still has to accept
      // — and a message that claimed it had landed would be a lie a third of
      // the time.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Offered 1 item to ${target.name}.'
                : 'Offered $count items to ${target.name}.',
          ),
        ),
      );
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

  void _deleteTransfer(
    MobileTransferController controller,
    TransferRecord transfer,
  ) {
    final removed = controller.removeTransfer(transfer.transferId);
    if (removed == null || !mounted) return;
    showBottomUndoSnackBar(
      context,
      message: 'Transfer deleted',
      onUndo: () => controller.restoreTransfer(removed),
    );
  }
}

/// The card's heading, which says what the card will do to what.
///
/// The old heading said "Send to device / Photos, videos, and files" whichever
/// way the app was configured, which is the kind of caption that survives every
/// state and describes none of them. This one names the device, because naming
/// it is the thing that stops a file going somewhere the user did not intend.
class _SendHeader extends StatelessWidget {
  const _SendHeader({required this.target, required this.choices});

  final PeerLink? target;
  final int choices;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final subtitle = switch (target) {
      null => 'No device connected',
      final PeerLink link when choices > 1 => 'to ${link.name}, of $choices',
      final PeerLink link => 'to ${link.name}',
    };

    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: AppIcon(AppIcons.materialNearMe, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Send', style: text.titleMedium),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the card shows when there is genuinely nowhere to send.
///
/// A sentence and a reason, rather than the previous arrangement: a picker and
/// a grey button, which invited the user to choose three photos and then told
/// them nothing about why pressing Send did not work.
class _NothingToSendTo extends StatelessWidget {
  const _NothingToSendTo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Nowhere to send yet',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Connect to a computer, or open Remote Link on another phone on '
            'the same Wi-Fi and it will appear here.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Which of several devices a send goes to.
///
/// Shown only when there is a real choice. A single-device picker is a control
/// that cannot be operated, and the heading already names the one device.
///
/// This replaces a dropdown that listed every computer the phone had ever seen.
/// That list was honest about discovery and dishonest about sending: only a
/// device with a live session can receive anything, so most of its rows were
/// choices that could not be honoured. Every row here is a session.
class _DestinationPicker extends StatelessWidget {
  const _DestinationPicker({
    required this.links,
    required this.selectedId,
    required this.onSelected,
  });

  final List<PeerLink> links;
  final DeviceId? selectedId;
  final void Function(DeviceId) onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final link in links)
            ChoiceChip(
              selected: link.id == selectedId,
              onSelected: (_) => onSelected(link.id),
              avatar: AppIcon(
                link.isHandheld
                    ? AppIcons.monitorSmartphone
                    : AppIcons.monitorSmartphone,
                size: 18,
              ),
              label: Text(link.name),
              // The chip's own box is around 32 tall, which is under every
              // platform's minimum and exactly the size that produces a tap
              // landing on the chip beside the one intended.
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      );
}

/// Where the things to send come from.
///
/// Two buttons rather than a segmented control and one button. The control was
/// a mode: the user set it, then pressed a picker, and the picker's meaning
/// depended on a switch several inches away that they had already stopped
/// looking at. Two named buttons collapse that to a single decision made at the
/// moment it matters, and — because they no longer disagree — a photo and a PDF
/// can go in the same send.
class _SourceButtons extends StatelessWidget {
  const _SourceButtons({
    required this.isPicking,
    required this.hasPicked,
    required this.onPickMedia,
    required this.onPickFiles,
  });

  final bool isPicking;
  final bool hasPicked;
  final Future<void> Function() onPickMedia;
  final Future<void> Function() onPickFiles;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            style: style,
            onPressed: isPicking ? null : () => unawaited(onPickMedia()),
            icon: isPicking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                // Media, not photos: the button opens the system *media*
                // picker, which returns videos as readily as stills. Labelled
                // "Photos" it undersold itself — someone wanting to send a
                // clip read the two buttons, saw neither offered video, and
                // went to Files, where the camera roll is not.
                : const AppIcon(AppIcons.gallery),
            label: Text(hasPicked ? 'Add media' : 'Media'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: style,
            onPressed: isPicking ? null : () => unawaited(onPickFiles()),
            icon: const AppIcon(AppIcons.clipboard),
            label: Text(hasPicked ? 'Add files' : 'Files'),
          ),
        ),
      ],
    );
  }
}

/// What is currently chosen, and a way to change one's mind about any of it.
class _PickedList extends StatelessWidget {
  const _PickedList({
    required this.picked,
    required this.onRemove,
    required this.onClear,
  });

  final List<PickedFile> picked;
  final void Function(PickedFile) onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = picked.fold<int>(0, (sum, p) => sum + _lengthOrZero(p.file));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                picked.length == 1
                    ? '1 item · ${formatBytes(total)}'
                    : '${picked.length} items · ${formatBytes(total)}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ),
        const SizedBox(height: 4),
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
                // Tapping opens the picture full size. Four screenshots from
                // the same afternoon are indistinguishable at 40 pixels, and
                // sending the wrong one to a computer is not undoable.
                _PickedThumbnail(file: file),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      FileNameText(
                        file.displayName,
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
                  icon: const AppIcon(AppIcons.delete, size: 21),
                  tooltip: 'Remove ${file.displayName}',
                  onPressed: () => onRemove(file),
                  color: scheme.error,
                ),
              ],
            ),
          ),
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

/// Something went wrong, and the way out of it.
///
/// Given a dismiss rather than left to sit there, because most of what lands
/// here is about a choice the user is in the middle of changing — a file that
/// vanished, a picker that would not open — and an error that outlives the
/// thing it described is just noise the user learns to read past.
class _SendProblem extends StatelessWidget {
  const _SendProblem({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppIcon(AppIcons.settings, color: scheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              // A live region, so the error is spoken when it appears rather
              // than only when someone happens to swipe onto it. The user who
              // most needs telling that a send failed is the one who cannot see
              // the red.
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            icon: const AppIcon(AppIcons.settings, size: 18),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            color: scheme.onErrorContainer,
          ),
        ],
      ),
    );
  }
}

/// The card's one primary action, and what it says when it cannot be pressed.
///
/// The button used to go grey with nothing beside it, which left three
/// different situations looking identical: nothing chosen, nothing connected,
/// and a connection still settling. A disabled control that does not say what
/// it is waiting for is a puzzle, and the user's usual solution to a puzzle is
/// to press it repeatedly.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.target,
    required this.count,
    required this.onSend,
  });

  final PeerLink? target;
  final int count;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final blocked = switch ((target, count)) {
      (null, _) => 'Connect to a device to send.',
      (_, 0) => 'Choose media or files above.',
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: blocked == null ? onSend : null,
          child: const Text('Send'),
        ),
        if (blocked != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            blocked,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// The 40-pixel square beside a picked file: the picture itself when it is one,
/// and a tap target that opens it full size.
class _PickedThumbnail extends StatelessWidget {
  const _PickedThumbnail({required this.file});

  final PickedFile file;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previewable = isPreviewableImage(file.displayName);

    final square = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ImageThumbnail(
        file: file.file,
        fileName: file.displayName,
        // Chosen per file rather than from whichever picker opened it. The
        // two pickers can now contribute to one send, so "this came from the
        // media button" no longer says anything about what it is.
        fallback: AppIcon(
          previewable ? AppIcons.gallery : AppIcons.files,
          size: 20,
          color: scheme.primary,
        ),
      ),
    );

    if (!previewable) return square;

    return Semantics(
      button: true,
      label: 'Preview ${file.displayName}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => unawaited(
          ImagePreviewPage.show(
            context,
            file: file.file,
            fileName: file.displayName,
          ),
        ),
        child: square,
      ),
    );
  }
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
                child: AppIcon(
                  isIncoming
                      ? AppIcons.materialArrowDown
                      : AppIcons.materialArrowUp,
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
              _StatusChip(status: transfer.status, isIncoming: isIncoming),
              if (!transfer.isActive) ...<Widget>[
                const SizedBox(width: 2),
                IconButton(
                  onPressed: onDelete,
                  icon: const AppIcon(AppIcons.delete, size: 21),
                  tooltip: 'Delete transfer',
                  color: scheme.error,
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          for (final f in transfer.files) ...<Widget>[
            _TransferFileRow(file: f),
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
                  icon: const AppIcon(AppIcons.settings, size: 20),
                  tooltip: 'Cancel',
                  color: scheme.error,
                ),
              if (transfer.canRetry)
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const AppIcon(AppIcons.settings, size: 18),
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

/// One file's name, size, and — once it has arrived — a way to open it.
///
/// The name is the tap target because the name is what people press. Before
/// this, pressing it did nothing and the only route to a received photo was to
/// leave the app and hunt for it in the gallery, which makes the transfer list
/// a receipt rather than a place you can do anything from.
///
/// What a tap does depends on what arrived. An image opens in the app, where
/// the point is to glance at it and go back. Anything else goes to the share
/// sheet, which is the only "open this in something" a phone offers an app
/// that does not own the file type — and is the same sheet the file came
/// through when it landed, so it is already familiar.
class _TransferFileRow extends StatelessWidget {
  const _TransferFileRow({required this.file});

  final TransferFileProgress file;

  bool get _isImage => isPreviewableImage(file.fileName);

  Future<void> _open(BuildContext context) async {
    final path = file.savedPath;
    if (path == null) return;

    final handle = File(path);
    // The keep lives in a cache directory, so it can be emptied by the OS
    // between the row being drawn and the row being tapped. Checked here rather
    // than trusted, and said plainly when it is gone.
    //
    // Async on purpose, against the lint: this runs on a tap, and the file may
    // sit on storage that is slow to stat. A frame dropped on the way into a
    // preview is exactly the jank the synchronous version would cause.
    // ignore: avoid_slow_async_io
    if (!await handle.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This file is no longer stored on your phone.'),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    if (_isImage) {
      await ImagePreviewPage.show(
        context,
        file: handle,
        fileName: file.fileName,
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(path)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = file.savedPath;
    final size = Text(
      '${formatBytes(file.transferredBytes)} / ${formatBytes(file.totalBytes)}',
      style: Theme.of(context).textTheme.bodySmall,
    );

    final name = FileNameText(
      file.fileName,
      style: TextStyle(
        fontWeight: FontWeight.w500,
        color: path == null ? null : scheme.primary,
      ),
    );

    if (path == null) {
      return Row(
        children: <Widget>[
          Expanded(child: name),
          const SizedBox(width: 8),
          size,
        ],
      );
    }

    return Semantics(
      button: true,
      label: '${_isImage ? 'Open' : 'Share'} ${file.fileName}',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => unawaited(_open(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              Expanded(child: name),
              const SizedBox(width: 6),
              // Says which of the two things a tap will do before it happens.
              AppIcon(
                _isImage ? AppIcons.zoomOut : AppIcons.materialArrowUp,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              size,
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.isIncoming = false});

  final TransferStatus status;

  /// Which end of the transfer this phone is on.
  ///
  /// Only [TransferStatus.prompting] reads differently from the two sides, but
  /// it reads *backwards* from the wrong one, which is worse than vague.
  final bool isIncoming;

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
      // Which way this is waiting depends on which end asked. On a transfer
      // this phone is receiving, "Awaiting response" describes the computer,
      // which is not what is happening.
      TransferStatus.prompting => (
          isIncoming ? 'Waiting for you' : 'Awaiting response',
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
