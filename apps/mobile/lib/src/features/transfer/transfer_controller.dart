import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import 'file_picker.dart';
import 'mobile_transfer_store.dart';
import 'transfer_model.dart';

/// Complete state of the file transfer feature on mobile.
@immutable
final class TransferState {
  const TransferState({
    this.transfers = const <TransferRecord>[],
    this.pendingIncoming,
    this.knownPeersWithTransfers = const <String>{},
    this.destinationDirectoryPath = '',
  });

  final List<TransferRecord> transfers;
  final PendingIncomingTransfer? pendingIncoming;
  final Set<String> knownPeersWithTransfers;
  final String destinationDirectoryPath;

  TransferState copyWith({
    List<TransferRecord>? transfers,
    PendingIncomingTransfer? Function()? pendingIncoming,
    Set<String>? knownPeersWithTransfers,
    String? destinationDirectoryPath,
  }) =>
      TransferState(
        transfers: transfers ?? this.transfers,
        pendingIncoming:
            pendingIncoming != null ? pendingIncoming() : this.pendingIncoming,
        knownPeersWithTransfers:
            knownPeersWithTransfers ?? this.knownPeersWithTransfers,
        destinationDirectoryPath:
            destinationDirectoryPath ?? this.destinationDirectoryPath,
      );
}

/// Controller managing incoming & outgoing file & text transfers on mobile.
class MobileTransferController extends StateNotifier<TransferState> {
  MobileTransferController(
    this._ref, {
    IncomingTransferStore? customTransferStore,
  })  : _customTransferStore = customTransferStore,
        super(const TransferState()) {
    _init();
  }

  final Ref _ref;
  final IncomingTransferStore? _customTransferStore;
  final Log _log = Log.scoped('mobile.transfer');

  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<ClientState>? _stateSubscription;

  final Map<String, FileTransferReceiver> _receivers =
      <String, FileTransferReceiver>{};
  final Map<String, TransferSpeedTracker> _speedTrackers =
      <String, TransferSpeedTracker>{};
  final Map<String, Map<String, OutgoingFile>> _outgoingSources =
      <String, Map<String, OutgoingFile>>{};
  final Map<String, FileOffer> _outgoingOffers = <String, FileOffer>{};
  final Map<String, Completer<void>> _activeSendCompleters =
      <String, Completer<void>>{};

  IncomingTransferStore? _store;

  void _init() {
    unawaited(_listen());
    unawaited(_initStore());
  }

  Future<void> _listen() async {
    final client = await _ref.read(clientProvider.future);
    _messageSubscription = client.messages.listen(
      _onMessage,
      cancelOnError: false,
    );
    _stateSubscription = client.states.listen(
      _onClientStateChange,
      cancelOnError: false,
    );
  }

  Future<void> _initStore() async {
    if (_customTransferStore != null) {
      _store = _customTransferStore;
      state = state.copyWith(destinationDirectoryPath: 'downloads');
      return;
    }

    try {
      final store = await _ref.read(mobileTransferStoreProvider.future);
      _store = store;
      if (store is MobileTransferStore) {
        state = state.copyWith(
          destinationDirectoryPath: store.destination.path,
        );
      }
    } catch (e) {
      _log.warn('Could not initialize mobile transfer store: $e');
    }
  }

  void _onClientStateChange(ClientState clientState) {
    if (clientState != ClientState.connected) {
      // Clean up in-memory receivers when disconnected
      for (final receiver in _receivers.values) {
        unawaited(receiver.dispose());
      }
      _receivers.clear();
    }
  }

  Future<void> _onMessage(Message message) async {
    final client = _ref.read(clientProvider).valueOrNull;
    final session = client?.session;
    final peerId = session?.peerId;
    if (peerId == null || session == null) return;

    final peerName =
        _ref.read(connectedPeerProvider).valueOrNull?.name ?? peerId.short;

    switch (message) {
      case FileOffer():
        await _handleFileOffer(message, session, peerId, peerName);
      case FileAccept():
        await _handleFileAccept(message, session);
      case FileChunk():
        await _handleFileChunk(message, session, peerId);
      case FileComplete():
        await _handleFileComplete(message, session, peerId);
      case FileAbort():
        await _handleFileAbort(message, session, peerId);
      default:
        break;
    }
  }

  Future<void> _handleFileOffer(
    FileOffer offer,
    Session session,
    DeviceId peerId,
    String peerName,
  ) async {
    _log.info(
      'received FileOffer ${offer.transferId} with ${offer.files.length} files',
    );

    final isFirst = !state.knownPeersWithTransfers.contains(peerId.value);
    final pending = PendingIncomingTransfer(
      transferId: offer.transferId,
      peerId: peerId,
      peerName: peerName,
      offer: offer,
      isFirstTransferFromDevice: isFirst,
      destinationPath: state.destinationDirectoryPath,
    );

    final transferRecord = TransferRecord(
      transferId: offer.transferId,
      peerId: peerId,
      peerName: peerName,
      direction: TransferDirection.incoming,
      status: TransferStatus.prompting,
      files: <TransferFileProgress>[
        for (final f in offer.files)
          TransferFileProgress(
            fileId: f.fileId,
            fileName: f.fileName,
            totalBytes: f.size,
            transferredBytes: 0,
          ),
      ],
      totalBytes: offer.files.fold(0, (sum, f) => sum + f.size),
      transferredBytes: 0,
      createdAt: DateTime.now(),
    );

    _speedTrackers[offer.transferId] = TransferSpeedTracker();

    state = state.copyWith(
      transfers: <TransferRecord>[
        transferRecord,
        ...state.transfers.where((t) => t.transferId != offer.transferId),
      ],
      pendingIncoming: () => pending,
    );
  }

  /// Explicitly accepts an incoming transfer. Never called automatically.
  Future<void> acceptIncomingTransfer(PendingIncomingTransfer request) async {
    final client = _ref.read(clientProvider).valueOrNull;
    final session = client?.session;
    if (session == null || !session.isEstablished) {
      _failTransfer(request.transferId, 'Connection lost');
      return;
    }

    if (_store == null) {
      await _initStore();
    }

    final store = _store;
    if (store == null) {
      await session.send(
        FileAbort(
          transferId: request.transferId,
          reason: FileAbortReason.ioError,
        ),
      );
      _failTransfer(request.transferId, 'Storage unavailable');
      return;
    }

    final receiver = _receivers.putIfAbsent(
      session.peerId.value,
      () => FileTransferReceiver(
        exporterSecret: session.exporterSecret,
        store: store,
        storageNamespace: session.peerId.value,
      ),
    );

    try {
      final decision = await receiver.acceptOffer(
        request.offer,
        tier: PermissionTier.extended,
      );

      await session.send(decision.accept);
      if (decision.abort case final abort?) {
        await session.send(abort);
      }

      final known = Set<String>.from(state.knownPeersWithTransfers)
        ..add(request.peerId.value);

      final updated = _updateTransfer(
        request.transferId,
        (t) => t.copyWith(status: TransferStatus.inProgress),
      );

      state = state.copyWith(
        transfers: updated,
        pendingIncoming: () => null,
        knownPeersWithTransfers: known,
      );
    } catch (e) {
      _log.error('Failed to accept offer: $e');
      await session.send(
        FileAbort(
          transferId: request.transferId,
          reason: FileAbortReason.ioError,
        ),
      );
      _failTransfer(request.transferId, e.toString());
    }
  }

  /// Explicitly declines an incoming transfer and sends FileAbort.
  Future<void> declineIncomingTransfer(PendingIncomingTransfer request) async {
    final client = _ref.read(clientProvider).valueOrNull;
    final session = client?.session;
    if (session != null && session.isEstablished) {
      try {
        await session.send(
          FileAbort(
            transferId: request.transferId,
            reason: FileAbortReason.declined,
          ),
        );
      } catch (_) {}
    }

    final updated = _updateTransfer(
      request.transferId,
      (t) => t.copyWith(
        status: TransferStatus.declined,
        completedAt: DateTime.now(),
      ),
    );

    state = state.copyWith(
      transfers: updated,
      pendingIncoming: () => null,
    );
  }

  Future<void> _handleFileChunk(
    FileChunk chunk,
    Session session,
    DeviceId peerId,
  ) async {
    final receiver = _receivers[peerId.value];
    if (receiver == null) {
      await session.send(
        FileAbort(
          transferId: chunk.transferId,
          fileId: chunk.fileId,
          reason: FileAbortReason.ioError,
        ),
      );
      return;
    }

    final result = await receiver.receiveChunk(
      chunk,
      tier: PermissionTier.extended,
    );

    if (result == ChunkDisposition.refused) {
      await session.send(
        FileAbort(
          transferId: chunk.transferId,
          fileId: chunk.fileId,
          reason: FileAbortReason.declined,
        ),
      );
      return;
    }

    if (result == ChunkDisposition.corrupt) {
      await session.send(
        FileAbort(
          transferId: chunk.transferId,
          fileId: chunk.fileId,
          reason: FileAbortReason.hashMismatch,
        ),
      );
      return;
    }

    final record = state.transfers
        .where((t) => t.transferId == chunk.transferId)
        .firstOrNull;
    if (record == null) return;

    final tracker = _speedTrackers.putIfAbsent(
      chunk.transferId,
      TransferSpeedTracker.new,
    );

    final fileIndex = record.files.indexWhere((f) => f.fileId == chunk.fileId);
    if (fileIndex == -1) return;

    final file = record.files[fileIndex];
    final newFileTransferred =
        (chunk.offset + chunk.bytes.length).clamp(0, file.totalBytes);
    final updatedFile = file.copyWith(transferredBytes: newFileTransferred);

    final updatedFiles = List<TransferFileProgress>.from(record.files);
    updatedFiles[fileIndex] = updatedFile;

    final totalTransferred =
        updatedFiles.fold(0, (sum, f) => sum + f.transferredBytes);
    tracker.record(totalTransferred);

    final speed = tracker.calculateSpeed();
    final eta = tracker.calculateEta(
      record.totalBytes,
      totalTransferred,
      speed,
    );

    final updated = _updateTransfer(
      chunk.transferId,
      (t) => t.copyWith(
        files: updatedFiles,
        transferredBytes: totalTransferred,
        speedBytesPerSecond: speed,
        eta: eta,
        status: TransferStatus.inProgress,
      ),
    );

    state = state.copyWith(transfers: updated);
  }

  Future<void> _handleFileComplete(
    FileComplete complete,
    Session session,
    DeviceId peerId,
  ) async {
    final receiver = _receivers[peerId.value];
    if (receiver == null) return;

    final result = await receiver.complete(
      complete,
      tier: PermissionTier.extended,
    );

    if (result == CompletionDisposition.hashMismatch ||
        result == CompletionDisposition.incomplete) {
      await session.send(
        FileAbort(
          transferId: complete.transferId,
          fileId: complete.fileId,
          reason: result == CompletionDisposition.hashMismatch
              ? FileAbortReason.hashMismatch
              : FileAbortReason.ioError,
        ),
      );
      _failTransfer(complete.transferId, 'Integrity verification failed');
      return;
    }

    final record = state.transfers
        .where((t) => t.transferId == complete.transferId)
        .firstOrNull;
    if (record == null) return;

    final fileIndex =
        record.files.indexWhere((f) => f.fileId == complete.fileId);
    if (fileIndex == -1) return;

    final updatedFiles = List<TransferFileProgress>.from(record.files);
    updatedFiles[fileIndex] = updatedFiles[fileIndex].copyWith(
      transferredBytes: updatedFiles[fileIndex].totalBytes,
      isComplete: true,
    );

    final allComplete = updatedFiles.every((f) => f.isComplete);
    final totalTransferred =
        updatedFiles.fold(0, (sum, f) => sum + f.transferredBytes);

    final updated = _updateTransfer(
      complete.transferId,
      (t) => t.copyWith(
        files: updatedFiles,
        transferredBytes: totalTransferred,
        status:
            allComplete ? TransferStatus.completed : TransferStatus.inProgress,
        completedAt: allComplete ? DateTime.now() : null,
      ),
    );

    state = state.copyWith(transfers: updated);
  }

  Future<void> _handleFileAbort(
    FileAbort abort,
    Session session,
    DeviceId peerId,
  ) async {
    final receiver = _receivers[peerId.value];
    if (receiver != null) {
      await receiver.abort(abort, tier: PermissionTier.extended);
    }

    final completer = _activeSendCompleters.remove(abort.transferId);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('Transfer aborted by remote peer'));
    }

    final reasonStr = switch (abort.reason) {
      FileAbortReason.declined => 'Transfer declined by peer',
      FileAbortReason.cancelled => 'Transfer cancelled',
      FileAbortReason.hashMismatch => 'File integrity hash mismatch',
      FileAbortReason.tooLarge => 'Not enough storage space on peer',
      FileAbortReason.timeout => 'Transfer timed out',
      FileAbortReason.ioError => 'I/O error during transfer',
    };

    final isDeclined = abort.reason == FileAbortReason.declined;

    final updated = _updateTransfer(
      abort.transferId,
      (t) => t.copyWith(
        status: isDeclined ? TransferStatus.declined : TransferStatus.cancelled,
        errorMessage: reasonStr,
        completedAt: DateTime.now(),
      ),
    );

    state = state.copyWith(
      transfers: updated,
      pendingIncoming: state.pendingIncoming?.transferId == abort.transferId
          ? () => null
          : null,
    );
  }

  Future<void> _handleFileAccept(FileAccept accept, Session session) async {
    final sources = _outgoingSources[accept.transferId];
    final offer = _outgoingOffers[accept.transferId];
    if (sources == null || offer == null) return;

    final sender = FileTransferSender(exporterSecret: session.exporterSecret);
    final tracker = _speedTrackers.putIfAbsent(
      accept.transferId,
      TransferSpeedTracker.new,
    );

    final sendCompleter = Completer<void>();
    _activeSendCompleters[accept.transferId] = sendCompleter;

    final updated = _updateTransfer(
      accept.transferId,
      (t) => t.copyWith(status: TransferStatus.inProgress),
    );
    state = state.copyWith(transfers: updated);

    unawaited(
      () async {
        try {
          await sender.sendAccepted(
            offer: offer,
            accept: accept,
            sources: sources,
            sendChunk: (chunk) async {
              if (sendCompleter.isCompleted) {
                throw StateError('Transfer was cancelled');
              }
              await session.send(chunk);

              final rec = state.transfers
                  .where((t) => t.transferId == accept.transferId)
                  .firstOrNull;
              if (rec != null) {
                final fileIdx =
                    rec.files.indexWhere((f) => f.fileId == chunk.fileId);
                if (fileIdx != -1) {
                  final f = rec.files[fileIdx];
                  final newBytes = (chunk.offset + chunk.bytes.length)
                      .clamp(0, f.totalBytes);
                  final updatedF = f.copyWith(transferredBytes: newBytes);
                  final uFiles = List<TransferFileProgress>.from(rec.files);
                  uFiles[fileIdx] = updatedF;
                  final totalTr = uFiles.fold(
                      0, (sum, item) => sum + item.transferredBytes);

                  tracker.record(totalTr);
                  final speed = tracker.calculateSpeed();
                  final eta = tracker.calculateEta(
                    rec.totalBytes,
                    totalTr,
                    speed,
                  );

                  state = state.copyWith(
                    transfers: _updateTransfer(
                      accept.transferId,
                      (t) => t.copyWith(
                        files: uFiles,
                        transferredBytes: totalTr,
                        speedBytesPerSecond: speed,
                        eta: eta,
                      ),
                    ),
                  );
                }
              }
            },
            sendComplete: (complete) async {
              if (sendCompleter.isCompleted) {
                throw StateError('Transfer was cancelled');
              }
              await session.send(complete);

              final rec = state.transfers
                  .where((t) => t.transferId == accept.transferId)
                  .firstOrNull;
              if (rec != null) {
                final fileIdx =
                    rec.files.indexWhere((f) => f.fileId == complete.fileId);
                if (fileIdx != -1) {
                  final uFiles = List<TransferFileProgress>.from(rec.files);
                  uFiles[fileIdx] = uFiles[fileIdx].copyWith(
                    transferredBytes: uFiles[fileIdx].totalBytes,
                    isComplete: true,
                  );
                  final allDone = uFiles.every((f) => f.isComplete);
                  final totalTr = uFiles.fold(
                      0, (sum, item) => sum + item.transferredBytes);

                  state = state.copyWith(
                    transfers: _updateTransfer(
                      accept.transferId,
                      (t) => t.copyWith(
                        files: uFiles,
                        transferredBytes: totalTr,
                        status: allDone
                            ? TransferStatus.completed
                            : TransferStatus.inProgress,
                        completedAt: allDone ? DateTime.now() : null,
                      ),
                    ),
                  );
                }
              }
            },
          );

          if (!sendCompleter.isCompleted) {
            sendCompleter.complete();
          }

          state = state.copyWith(
            transfers: _updateTransfer(
              accept.transferId,
              (t) => t.copyWith(
                status: TransferStatus.completed,
                transferredBytes: t.totalBytes,
                completedAt: DateTime.now(),
              ),
            ),
          );
        } catch (e) {
          if (!sendCompleter.isCompleted) {
            sendCompleter.completeError(e);
          }
          _log.warn('Outgoing transfer failed: $e');
          _failTransfer(accept.transferId, e.toString());
        } finally {
          _activeSendCompleters.remove(accept.transferId);
        }
      }(),
    );
  }

  /// Sends a bare string (URL or snippet) to [targetPeerId].
  Future<String> sendText({
    required DeviceId targetPeerId,
    required String targetPeerName,
    required String text,
    String? customFileName,
  }) async {
    final client = _ref.read(clientProvider).valueOrNull;
    final session = client?.session;
    if (session == null || !session.isEstablished) {
      throw StateError('Cannot send: not connected to peer');
    }

    final bytes = Uint8List.fromList(utf8.encode(text));
    final rawName = customFileName != null && customFileName.trim().isNotEmpty
        ? customFileName.trim()
        : generateTextSnippetFileName();
    final fileName = sanitiseFileName(rawName);

    final transferId =
        't-${DateTime.now().microsecondsSinceEpoch}-${bytes.length}';
    const fileId = 'text-1';

    final sha256 = await Primitives.sha256(bytes);
    final offeredFile = OfferedFile(
      fileId: fileId,
      fileName: fileName,
      size: bytes.length,
      fileType: 'text/plain',
      sha256: sha256,
      modifiedAt: DateTime.now().toUtc(),
    );

    final offer = FileOffer(
      transferId: transferId,
      files: <OfferedFile>[offeredFile],
    );

    final sources = <String, OutgoingFile>{
      fileId: MemoryOutgoingFile(bytes),
    };

    _outgoingSources[transferId] = sources;
    _outgoingOffers[transferId] = offer;
    _speedTrackers[transferId] = TransferSpeedTracker();

    final record = TransferRecord(
      transferId: transferId,
      peerId: targetPeerId,
      peerName: targetPeerName,
      direction: TransferDirection.outgoing,
      status: TransferStatus.offered,
      files: <TransferFileProgress>[
        TransferFileProgress(
          fileId: fileId,
          fileName: fileName,
          totalBytes: bytes.length,
          transferredBytes: 0,
        ),
      ],
      totalBytes: bytes.length,
      transferredBytes: 0,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      transfers: <TransferRecord>[record, ...state.transfers],
    );

    await session.send(offer);
    return transferId;
  }

  /// Sends a list of files to [targetPeerId].
  Future<String> sendFiles({
    required DeviceId targetPeerId,
    required String targetPeerName,
    required List<File> files,
    List<String>? fileNames,
  }) async {
    final client = _ref.read(clientProvider).valueOrNull;
    final session = client?.session;
    if (session == null || !session.isEstablished) {
      throw StateError('Cannot send: not connected to peer');
    }

    if (files.isEmpty) {
      throw ArgumentError('files list must not be empty');
    }

    if (fileNames != null && fileNames.length != files.length) {
      throw ArgumentError(
        'fileNames has ${fileNames.length} entries for ${files.length} files',
      );
    }

    final transferId = 't-${DateTime.now().microsecondsSinceEpoch}';
    final offeredFiles = <OfferedFile>[];
    final sources = <String, OutgoingFile>{};

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final fileId = 'file-${i + 1}';
      // The caller's name wins when it has one. A picked file's path is a
      // cache copy — `image_picker_A1B2C3.jpg` — and the name the user
      // recognises only exists in the picker's own metadata.
      final pathName = file.uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => 'file_${i + 1}.dat',
      );
      final fileName = safeOutgoingFileName(
        <String?>[fileNames?[i], pathName],
        fallback: 'file_${i + 1}.dat',
      );
      final length = file.lengthSync();
      final stat = file.statSync();
      final fileType = mimeTypeForFileName(fileName);

      offeredFiles.add(
        OfferedFile(
          fileId: fileId,
          fileName: fileName,
          size: length,
          fileType: fileType,
          modifiedAt: stat.modified.toUtc(),
        ),
      );
      sources[fileId] = FileBackedOutgoingFile(file, length);
    }

    final offer = FileOffer(
      transferId: transferId,
      files: offeredFiles,
    );

    _outgoingSources[transferId] = sources;
    _outgoingOffers[transferId] = offer;
    _speedTrackers[transferId] = TransferSpeedTracker();

    final record = TransferRecord(
      transferId: transferId,
      peerId: targetPeerId,
      peerName: targetPeerName,
      direction: TransferDirection.outgoing,
      status: TransferStatus.offered,
      files: <TransferFileProgress>[
        for (final f in offeredFiles)
          TransferFileProgress(
            fileId: f.fileId,
            fileName: f.fileName,
            totalBytes: f.size,
            transferredBytes: 0,
          ),
      ],
      totalBytes: offeredFiles.fold(0, (sum, f) => sum + f.size),
      transferredBytes: 0,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      transfers: <TransferRecord>[record, ...state.transfers],
    );

    await session.send(offer);
    return transferId;
  }

  /// Cancels an in-progress transfer and sends FileAbort.
  Future<void> cancelTransfer(String transferId) async {
    final client = _ref.read(clientProvider).valueOrNull;
    final session = client?.session;

    if (session != null && session.isEstablished) {
      try {
        await session.send(
          FileAbort(
            transferId: transferId,
            reason: FileAbortReason.cancelled,
          ),
        );
      } catch (_) {}
    }

    final sendCompleter = _activeSendCompleters.remove(transferId);
    if (sendCompleter != null && !sendCompleter.isCompleted) {
      sendCompleter.completeError(StateError('Transfer cancelled by user'));
    }

    final updated = _updateTransfer(
      transferId,
      (t) => t.copyWith(
        status: TransferStatus.cancelled,
        completedAt: DateTime.now(),
      ),
    );

    state = state.copyWith(
      transfers: updated,
      pendingIncoming:
          state.pendingIncoming?.transferId == transferId ? () => null : null,
    );
  }

  /// Retries a failed or cancelled transfer.
  Future<void> retryTransfer(String transferId) async {
    final offer = _outgoingOffers[transferId];
    final sources = _outgoingSources[transferId];
    final record =
        state.transfers.where((t) => t.transferId == transferId).firstOrNull;

    if (offer == null || sources == null || record == null) {
      throw StateError('Cannot retry transfer: offer not found');
    }

    final client = _ref.read(clientProvider).valueOrNull;
    final session = client?.session;
    if (session == null || !session.isEstablished) {
      throw StateError('Cannot retry: not connected');
    }

    final updated = _updateTransfer(
      transferId,
      (t) => t.copyWith(
        status: TransferStatus.offered,
        errorMessage: null,
      ),
    );
    state = state.copyWith(transfers: updated);

    await session.send(offer);
  }

  List<TransferRecord> _updateTransfer(
    String transferId,
    TransferRecord Function(TransferRecord) updater,
  ) =>
      state.transfers
          .map((t) => t.transferId == transferId ? updater(t) : t)
          .toList();

  void _failTransfer(String transferId, String message) {
    final updated = _updateTransfer(
      transferId,
      (t) => t.copyWith(
        status: TransferStatus.failed,
        errorMessage: message,
        completedAt: DateTime.now(),
      ),
    );
    state = state.copyWith(
      transfers: updated,
      pendingIncoming:
          state.pendingIncoming?.transferId == transferId ? () => null : null,
    );
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _stateSubscription?.cancel();
    for (final receiver in _receivers.values) {
      unawaited(receiver.dispose());
    }
    _receivers.clear();
    super.dispose();
  }
}

/// First of [candidates] that survives `sanitiseFileName`, else [fallback].
///
/// `sanitiseFileName` throws rather than repairing, which is right for a name
/// arriving from a peer: there is nothing safe to do with a hostile filename
/// but refuse it. On the sending side the calculus is different. The user
/// picked a file and wants it sent, and aborting the whole transfer because the
/// photo library handed back a name with a trailing space would be the app
/// inventing a problem the user cannot fix. So each candidate is tried in turn
/// and a generated name that cannot fail sits at the end.
///
/// The check itself is never skipped — every name that goes on the wire has
/// been through it, this only decides what to do when one is rejected.
String safeOutgoingFileName(
  List<String?> candidates, {
  required String fallback,
}) {
  for (final candidate in candidates) {
    if (candidate == null) continue;
    try {
      return sanitiseFileName(candidate);
    } on ProtocolError {
      continue;
    }
  }
  return sanitiseFileName(fallback);
}

/// Provider for mobile transfer state.
final transferControllerProvider =
    StateNotifierProvider<MobileTransferController, TransferState>(
  MobileTransferController.new,
);

/// The system file and photo pickers.
///
/// Overridden with a fake in widget tests. The real implementation calls
/// platform channels that do not exist in the test binding, so a test that
/// reaches it fails with `MissingPluginException` rather than anything useful.
final transferFilePickerProvider = Provider<TransferFilePicker>(
  (ref) => SystemTransferFilePicker(),
);

/// Provider for the download directory store on mobile.
final mobileTransferStoreProvider =
    FutureProvider<IncomingTransferStore>((ref) async {
  final base = await getApplicationDocumentsDirectory();
  final destination = Directory('${base.path}/RemoteLink');
  return MobileTransferStore(destination);
});
