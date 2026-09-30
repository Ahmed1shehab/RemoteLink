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
import '../host/host_providers.dart';
import '../host/phone_host_service.dart';
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

  /// Receiver cleanup is serialized with disk writes. Keep its failure from
  /// becoming an unhandled asynchronous error after the row is terminal.
  void _abortReceiver(FileTransferReceiver receiver, FileAbort abort) {
    unawaited(receiver.abort(abort, tier: PermissionTier.extended).onError(
      (Object error, StackTrace stackTrace) {
        _log.warn('Could not clean up aborted transfer: $error');
      },
    ));
  }

  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<ClientState>? _stateSubscription;
  StreamSubscription<InboundMessage>? _inboundSubscription;
  StreamSubscription<List<InboundLink>>? _hostLinksSubscription;
  Set<String> _hostPeerIds = <String>{};

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
  DeviceId? _clientPeerId;

  void _init() {
    unawaited(_listen());
    unawaited(_initStore());
  }

  /// Listens to every link a transfer can arrive on.
  ///
  /// Two subscriptions rather than one, because the two links are made in
  /// opposite directions and neither is a special case of the other. The client
  /// is the connection this phone opened; the host is every connection opened
  /// to it. A transfer looks identical once it is under way — which is the
  /// point — but the session it belongs to is not interchangeable, so the
  /// session comes through with the message rather than being looked up
  /// afterwards from whatever happens to be connected.
  Future<void> _listen() async {
    final client = await _ref.read(clientProvider.future);
    _messageSubscription = client.messages.listen((message) {
      final session = client.session;
      if (session != null) {
        _clientPeerId = session.peerId;
        unawaited(_onMessage(session, message));
      }
    }, cancelOnError: false);
    _stateSubscription = client.states.listen(
      _onClientStateChange,
      cancelOnError: false,
    );

    await _listenToNearbyDevices();
  }

  /// Subscribes to transfers arriving from devices that connected to us.
  ///
  /// Separated and guarded because the two halves fail independently and only
  /// one of them is load-bearing. A phone whose listening socket could not bind
  /// — no permission, a port taken, a platform that will not allow it — can
  /// still send to every computer and every phone it can reach, and that is
  /// worth strictly more than an exception thrown into the void from a
  /// constructor.
  Future<void> _listenToNearbyDevices() async {
    try {
      final host = await _ref.read(phoneHostServiceProvider.future);
      _inboundSubscription = host.messages.listen(
        (inbound) => unawaited(_onMessage(inbound.session, inbound.message)),
        cancelOnError: false,
      );
      _hostPeerIds = host.links.map((link) => link.peerId.value).toSet();
      _hostLinksSubscription = host.linkChanges.listen((links) {
        final connected = links.map((link) => link.peerId.value).toSet();
        for (final peerId in _hostPeerIds.difference(connected)) {
          for (final transfer in state.transfers) {
            if (transfer.peerId.value == peerId && transfer.isActive) {
              _failTransfer(transfer.transferId, 'Connection lost');
            }
          }
          final receiver = _receivers.remove(peerId);
          if (receiver != null) unawaited(receiver.dispose());
        }
        _hostPeerIds = connected;
      });
    } on Object catch (error) {
      _log.warn('not listening for nearby devices', error: error);
    }
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
      // Client sessions carry phone-originated sends to the PC. End their
      // rows before clearing receivers so a vanished PC cannot strand them.
      final clientPeer = _clientPeerId;
      if (clientPeer != null) {
        for (final transfer in state.transfers) {
          if (transfer.peerId == clientPeer && transfer.isActive) {
            _failTransfer(transfer.transferId, 'Connection lost');
          }
        }
      }
      // Inbound host links can stay alive when the outbound PC link drops.
      // Only its receiver belongs to this client session.
      if (clientPeer != null) {
        final receiver = _receivers.remove(clientPeer.value);
        if (receiver != null) unawaited(receiver.dispose());
      }
      _clientPeerId = null;
    }
  }

  Future<void> _onMessage(Session session, Message message) async {
    final peerId = session.peerId;
    final peerName = _nameFor(peerId);
    try {
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
    } on Object catch (error) {
      final transferId = switch (message) {
        FileOffer(:final transferId) ||
        FileAccept(:final transferId) ||
        FileChunk(:final transferId) ||
        FileComplete(:final transferId) ||
        FileAbort(:final transferId) =>
          transferId,
        _ => null,
      };
      if (transferId == null) return;
      _log.warn('Incoming file transfer failed: $error');
      _failTransfer(transferId, 'I/O error during transfer');
      if (session.isEstablished) {
        try {
          await session.send(FileAbort(
            transferId: transferId,
            reason: FileAbortReason.ioError,
          ));
        } on Object {
          // The local row is already terminal if the link disappeared.
        }
      }
    }
  }

  /// The session a transfer with [peerId] belongs to, or null if it has gone.
  ///
  /// Every entry point below asks for this rather than reaching for
  /// `client.session`. That used to be the same thing and is not any more: with
  /// a phone able to listen, "the session" can be one of several, and the one
  /// that matters is the one this peer is on. Reaching for the client's session
  /// while accepting a file from a nearby phone would send the acceptance to
  /// the computer instead, where it means nothing.
  ///
  /// Asked of the two objects directly rather than of [peerLinksProvider],
  /// which is the same answer arrived at a more fragile way. That provider is
  /// built out of streams — connection state, the peer's identity message — and
  /// a send is not a rebuild: it happens once, now, and has to work on the
  /// frame it is called on rather than on the frame after the stream that
  /// describes the connection has caught up with it.
  Session? _sessionFor(DeviceId peerId) {
    final outbound = _ref.read(clientProvider).valueOrNull?.session;
    if (outbound != null &&
        outbound.peerId == peerId &&
        outbound.isEstablished) {
      _clientPeerId = peerId;
      return outbound;
    }

    final host = _ref.read(phoneHostServiceProvider).valueOrNull;
    final inbound =
        host?.links.where((link) => link.peerId == peerId).firstOrNull?.session;
    if (inbound != null && inbound.isEstablished) return inbound;

    return null;
  }

  /// What to call [peerId] on a transfer row.
  ///
  /// Falls back to the short device id rather than to a friendly guess, because
  /// a row naming the wrong device is worse than a row naming none.
  String _nameFor(DeviceId peerId) {
    final reported = _ref.read(connectedPeerProvider).valueOrNull;
    if (reported != null && reported.id == peerId) return reported.name;

    final host = _ref.read(phoneHostServiceProvider).valueOrNull;
    final inbound =
        host?.links.where((link) => link.peerId == peerId).firstOrNull;
    return inbound?.name ?? peerId.short;
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
    if (state.transfers
            .where((t) => t.transferId == request.transferId)
            .firstOrNull
            ?.isActive !=
        true) {
      return;
    }
    final session = _sessionFor(request.peerId);
    if (session == null) {
      _failTransfer(request.transferId, 'Connection lost');
      return;
    }

    if (_store == null) {
      await _initStore();
    }

    final store = _store;
    if (store == null) {
      _failTransfer(request.transferId, 'Storage unavailable');
      await session.send(FileAbort(
        transferId: request.transferId,
        reason: FileAbortReason.ioError,
      ));
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
      if (state.transfers
              .where((t) => t.transferId == request.transferId)
              .firstOrNull
              ?.isActive !=
          true) {
        return;
      }

      await session.send(decision.accept);
      if (decision.abort case final abort?) {
        await session.send(abort);
      }

      final known = Set<String>.from(state.knownPeersWithTransfers)
        ..add(request.peerId.value);

      final updated = _updateTransfer(
        request.transferId,
        (t) => t.isActive
            ? t.copyWith(
                status: decision.abort == null
                    ? TransferStatus.inProgress
                    : TransferStatus.failed,
                errorMessage:
                    decision.abort == null ? null : 'Could not accept transfer',
                completedAt: decision.abort == null ? null : DateTime.now(),
              )
            : t,
      );

      state = state.copyWith(
        transfers: updated,
        pendingIncoming: () => null,
        knownPeersWithTransfers: known,
      );
    } catch (e) {
      _log.error('Failed to accept offer: $e');
      _failTransfer(request.transferId, e.toString());
      if (session.isEstablished) {
        try {
          await session.send(FileAbort(
            transferId: request.transferId,
            reason: FileAbortReason.ioError,
          ));
        } on Object {
          // The local failure remains visible after a broken send.
        }
      }
    }
  }

  /// Explicitly declines an incoming transfer and sends FileAbort.
  Future<void> declineIncomingTransfer(PendingIncomingTransfer request) async {
    final updated = _updateTransfer(
      request.transferId,
      (t) => t.isActive
          ? t.copyWith(
              status: TransferStatus.declined,
              errorMessage: 'Declined by you',
              completedAt: DateTime.now(),
            )
          : t,
    );
    state = state.copyWith(transfers: updated, pendingIncoming: () => null);
    final session = _sessionFor(request.peerId);
    if (session != null) {
      try {
        await session.send(
          FileAbort(
            transferId: request.transferId,
            reason: FileAbortReason.declined,
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> _handleFileChunk(
    FileChunk chunk,
    Session session,
    DeviceId peerId,
  ) async {
    final current = state.transfers
        .where((t) => t.transferId == chunk.transferId)
        .firstOrNull;
    if (current == null || !current.isActive) return;
    final receiver = _receivers[peerId.value];
    if (receiver == null) {
      _failTransfer(chunk.transferId, 'Receiver unavailable');
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
      _failTransfer(chunk.transferId, 'File chunk refused');
      await session.send(
        FileAbort(
          transferId: chunk.transferId,
          fileId: chunk.fileId,
          reason: FileAbortReason.ioError,
        ),
      );
      return;
    }

    if (result == ChunkDisposition.corrupt) {
      _failTransfer(chunk.transferId, 'File integrity hash mismatch');
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
    if (record == null || !record.isActive) return;

    final tracker = _speedTrackers.putIfAbsent(
      chunk.transferId,
      TransferSpeedTracker.new,
    );

    final fileIndex = record.files.indexWhere((f) => f.fileId == chunk.fileId);
    if (fileIndex == -1) return;

    final file = record.files[fileIndex];
    final newFileTransferred = (chunk.offset + chunk.bytes.length).clamp(
      0,
      file.totalBytes,
    );
    final updatedFile = file.copyWith(transferredBytes: newFileTransferred);

    final updatedFiles = List<TransferFileProgress>.from(record.files);
    updatedFiles[fileIndex] = updatedFile;

    final totalTransferred = updatedFiles.fold(
      0,
      (sum, f) => sum + f.transferredBytes,
    );
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
    final current = state.transfers
        .where((t) => t.transferId == complete.transferId)
        .firstOrNull;
    if (current == null || !current.isActive) return;
    if (current.direction == TransferDirection.outgoing) {
      if (current.status != TransferStatus.inProgress) return;
      final fileIndex = current.files.indexWhere(
        (file) => file.fileId == complete.fileId,
      );
      if (fileIndex == -1) return;
      final files = List<TransferFileProgress>.from(current.files);
      files[fileIndex] = files[fileIndex].copyWith(
        transferredBytes: files[fileIndex].totalBytes,
        isComplete: true,
      );
      final allDone = files.every((file) => file.isComplete);
      state = state.copyWith(
          transfers: _updateTransfer(
        complete.transferId,
        (record) => record.copyWith(
          files: files,
          transferredBytes: files.fold<int>(
              0, (total, file) => total + file.transferredBytes),
          status:
              allDone ? TransferStatus.completed : TransferStatus.inProgress,
          completedAt: allDone ? DateTime.now() : null,
        ),
      ));
      return;
    }
    final receiver = _receivers[peerId.value];
    if (receiver == null) {
      _failTransfer(complete.transferId, 'Receiver unavailable');
      await session.send(FileAbort(
        transferId: complete.transferId,
        fileId: complete.fileId,
        reason: FileAbortReason.ioError,
      ));
      return;
    }

    final result = await receiver.complete(
      complete,
      tier: PermissionTier.extended,
    );

    if (result == CompletionDisposition.hashMismatch ||
        result == CompletionDisposition.incomplete ||
        result == CompletionDisposition.refused) {
      _failTransfer(complete.transferId, 'File could not be completed');
      await session.send(
        FileAbort(
          transferId: complete.transferId,
          fileId: complete.fileId,
          reason: result == CompletionDisposition.hashMismatch
              ? FileAbortReason.hashMismatch
              : FileAbortReason.ioError,
        ),
      );
      return;
    }

    final record = state.transfers
        .where((t) => t.transferId == complete.transferId)
        .firstOrNull;
    if (record == null || !record.isActive) return;
    // Confirm after storage succeeds and before committing the local terminal
    // row, so a broken acknowledgement still follows the failure path.
    await session.send(complete);
    final latest = state.transfers
        .where((t) => t.transferId == complete.transferId)
        .firstOrNull;
    if (latest == null || !latest.isActive) return;

    final fileIndex = latest.files.indexWhere(
      (f) => f.fileId == complete.fileId,
    );
    if (fileIndex == -1) return;

    final store = _store;
    final updatedFiles = List<TransferFileProgress>.from(latest.files);
    updatedFiles[fileIndex] = updatedFiles[fileIndex].copyWith(
      transferredBytes: updatedFiles[fileIndex].totalBytes,
      isComplete: true,
      // Where the store put it, so the row can open it later. Null when the
      // file could not be kept, which the list renders as a row with nothing
      // to tap rather than one that fails when tapped.
      savedPath: store is MobileTransferStore
          ? store.keptPath(
              transferId: complete.transferId,
              fileId: complete.fileId,
            )
          : null,
    );

    final allComplete = updatedFiles.every((f) => f.isComplete);
    final totalTransferred = updatedFiles.fold(
      0,
      (sum, f) => sum + f.transferredBytes,
    );

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
    final record = state.transfers
        .where((t) => t.transferId == abort.transferId)
        .firstOrNull;
    if (record == null || !record.isActive) return;

    final completer = _activeSendCompleters.remove(abort.transferId);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('Transfer aborted by remote peer'));
    }

    final reasonStr = switch (abort.reason) {
      FileAbortReason.declined => 'Transfer declined by peer',
      FileAbortReason.cancelled => 'Cancelled by ${record.peerName}',
      FileAbortReason.hashMismatch => 'File integrity hash mismatch',
      FileAbortReason.tooLarge => 'Not enough storage space on peer',
      FileAbortReason.timeout => 'Transfer timed out',
      FileAbortReason.ioError => 'I/O error during transfer',
    };

    final isDeclined = abort.reason == FileAbortReason.declined;

    final updated = _updateTransfer(
      abort.transferId,
      (t) => t.copyWith(
        status: isDeclined
            ? TransferStatus.declined
            : abort.reason == FileAbortReason.cancelled
                ? TransferStatus.cancelled
                : TransferStatus.failed,
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
    final receiver = _receivers[peerId.value];
    if (receiver != null) {
      _abortReceiver(receiver, abort);
    }
  }

  Future<void> _handleFileAccept(FileAccept accept, Session session) async {
    if (state.transfers
            .where((t) => t.transferId == accept.transferId)
            .firstOrNull
            ?.isActive !=
        true) {
      return;
    }
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

    unawaited(() async {
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
            if (rec != null && rec.isActive) {
              final fileIdx = rec.files.indexWhere(
                (f) => f.fileId == chunk.fileId,
              );
              if (fileIdx != -1) {
                final f = rec.files[fileIdx];
                final newBytes = (chunk.offset + chunk.bytes.length).clamp(
                  0,
                  f.totalBytes,
                );
                final updatedF = f.copyWith(transferredBytes: newBytes);
                final uFiles = List<TransferFileProgress>.from(rec.files);
                uFiles[fileIdx] = updatedF;
                final totalTr = uFiles.fold(
                  0,
                  (sum, item) => sum + item.transferredBytes,
                );

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
            if (rec != null && rec.isActive) {
              final fileIdx = rec.files.indexWhere(
                (f) => f.fileId == complete.fileId,
              );
              if (fileIdx != -1) {
                final uFiles = List<TransferFileProgress>.from(rec.files);
                uFiles[fileIdx] = uFiles[fileIdx].copyWith(
                  transferredBytes: uFiles[fileIdx].totalBytes,
                );
                final totalTr = uFiles.fold(
                  0,
                  (sum, item) => sum + item.transferredBytes,
                );

                state = state.copyWith(
                  transfers: _updateTransfer(
                    accept.transferId,
                    (t) => t.copyWith(
                      files: uFiles,
                      transferredBytes: totalTr,
                      status: TransferStatus.inProgress,
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

        // FileComplete echoed by the receiver is the completion signal.
      } catch (e) {
        final active = state.transfers
                .where((t) => t.transferId == accept.transferId)
                .firstOrNull
                ?.isActive ==
            true;
        if (!sendCompleter.isCompleted) {
          sendCompleter.completeError(e);
        }
        _log.warn('Outgoing transfer failed: $e');
        _failTransfer(accept.transferId, e.toString());
        if (active && session.isEstablished) {
          try {
            await session.send(FileAbort(
              transferId: accept.transferId,
              reason: FileAbortReason.ioError,
            ));
          } on Object {
            // The local failure remains visible when the link closes.
          }
        }
      } finally {
        _activeSendCompleters.remove(accept.transferId);
      }
    }());
  }

  /// Sends a bare string (URL or snippet) to [targetPeerId].
  Future<String> sendText({
    required DeviceId targetPeerId,
    required String targetPeerName,
    required String text,
    String? customFileName,
  }) async {
    final session = _sessionFor(targetPeerId);
    if (session == null) {
      throw StateError('Cannot send: not connected to $targetPeerName');
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

    final sources = <String, OutgoingFile>{fileId: MemoryOutgoingFile(bytes)};

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
    final session = _sessionFor(targetPeerId);
    if (session == null) {
      throw StateError('Cannot send: not connected to $targetPeerName');
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
      final fileName = safeOutgoingFileName(<String?>[
        fileNames?[i],
        pathName,
      ], fallback: 'file_${i + 1}.dat');
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

    final offer = FileOffer(transferId: transferId, files: offeredFiles);

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
    // The row, not the connection, decides where the abort goes. A cancel is
    // still worth recording locally when the peer has already gone, so a
    // missing session only costs the notification.
    final record =
        state.transfers.where((t) => t.transferId == transferId).firstOrNull;
    if (record == null || !record.isActive) return;
    final session = _sessionFor(record.peerId);

    // The local decision is visible even when sending the abort blocks on a
    // broken link. A later send completion must not revive this row.
    state = state.copyWith(
      transfers: _updateTransfer(
        transferId,
        (t) => t.copyWith(
          status: TransferStatus.cancelled,
          errorMessage: 'Cancelled by you',
          completedAt: DateTime.now(),
        ),
      ),
      pendingIncoming:
          state.pendingIncoming?.transferId == transferId ? () => null : null,
    );

    final sendCompleter = _activeSendCompleters.remove(transferId);
    if (sendCompleter != null && !sendCompleter.isCompleted) {
      sendCompleter.completeError(StateError('Transfer cancelled by user'));
    }
    if (record.direction == TransferDirection.incoming) {
      final receiver = _receivers[record.peerId.value];
      if (receiver != null) {
        _abortReceiver(
            receiver,
            FileAbort(
                transferId: transferId, reason: FileAbortReason.cancelled));
      }
    }

    if (session != null) {
      try {
        await session.send(
          FileAbort(transferId: transferId, reason: FileAbortReason.cancelled),
        );
      } catch (_) {}
    }
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
    if (record.direction != TransferDirection.outgoing || !record.canRetry) {
      throw StateError('This transfer cannot be retried');
    }

    final session = _sessionFor(record.peerId);
    if (session == null) {
      throw StateError('Cannot retry: ${record.peerName} is not connected');
    }

    _speedTrackers[transferId] = TransferSpeedTracker();
    final updated = _updateTransfer(
      transferId,
      (t) => t.copyWith(
        status: TransferStatus.offered,
        files: <TransferFileProgress>[
          for (final file in t.files)
            file.copyWith(
              transferredBytes: 0,
              isComplete: false,
              clearError: true,
            ),
        ],
        transferredBytes: 0,
        speedBytesPerSecond: 0,
        clearEta: true,
        clearCompletedAt: true,
        clearErrorMessage: true,
      ),
    );
    state = state.copyWith(transfers: updated);

    try {
      await session.send(offer);
    } catch (error) {
      _failTransfer(transferId, 'Retry failed: $error');
      rethrow;
    }
  }

  /// Removes a finished transfer from the visible activity list.
  ///
  /// Active transfers must be cancelled first so deleting a row can never
  /// leave network work running without any visible status or escape route.
  TransferRecord? removeTransfer(String transferId) {
    final record =
        state.transfers.where((t) => t.transferId == transferId).firstOrNull;
    if (record == null || record.isActive) return null;

    _outgoingOffers.remove(transferId);
    _outgoingSources.remove(transferId);
    _speedTrackers.remove(transferId);
    _activeSendCompleters.remove(transferId);
    state = state.copyWith(
      transfers: state.transfers
          .where((transfer) => transfer.transferId != transferId)
          .toList(growable: false),
    );
    return record;
  }

  void restoreTransfer(TransferRecord record) {
    if (record.isActive ||
        state.transfers.any(
          (transfer) => transfer.transferId == record.transferId,
        )) {
      return;
    }
    state = state.copyWith(
      transfers: <TransferRecord>[record, ...state.transfers],
    );
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
      (t) => t.isActive
          ? t.copyWith(
              status: TransferStatus.failed,
              errorMessage: message,
              completedAt: DateTime.now(),
            )
          : t,
    );
    state = state.copyWith(
      transfers: updated,
      pendingIncoming:
          state.pendingIncoming?.transferId == transferId ? () => null : null,
    );
  }

  @override
  void dispose() {
    unawaited(_inboundSubscription?.cancel());
    unawaited(_hostLinksSubscription?.cancel());
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

/// The peer a transfer would go to, or null when there is nowhere to send.
///
/// A record rather than a `DeviceId`, because the send path needs a name to put
/// on the transfer row and the two come from different places while a
/// connection is settling.
typedef TransferTarget = ({DeviceId id, String name});

/// Where a send goes when nothing has chosen otherwise.
///
/// This used to be *the* target and the app was honest in calling it that:
/// there was one session, to one computer, and offering any other row would
/// have sent the file to the connected computer under a different computer's
/// name. Now that a phone can listen, there can be several real targets at
/// once, so this is the first of [peerLinksProvider] rather than the only
/// entry in it — the default for a share arriving from another app with no
/// chance to ask, not a claim that there is only one.
final transferTargetProvider = Provider<TransferTarget?>((ref) {
  final link = ref.watch(peerLinksProvider).firstOrNull;
  if (link == null) return null;
  return (id: link.id, name: link.name);
});

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
/// Where incoming files are assembled before they leave the app.
///
/// The cache directory, not Documents — and the difference is the whole point.
/// Documents is backed up, survives forever, and on iOS is visible in the Files
/// app, so a file left there is a file this app is storing. The cache is none
/// of those things: the OS may empty it at will, which is safe precisely
/// because nothing here is meant to outlive the transfer that created it.
///
/// [MobileTransferStore] hands each file to the photo library or the share
/// sheet the moment it is whole, and keeps only the most recent few afterwards
/// so the transfer list can reopen them. Using the cache is what makes that
/// keep safe to have: the OS may reclaim the whole directory whenever it likes,
/// and everything in it has already been delivered somewhere that will not
/// vanish. A half-written partial left by an app that was killed mid-transfer
/// is likewise the OS's to collect rather than something the user has to find.
final mobileTransferStoreProvider = FutureProvider<IncomingTransferStore>((
  ref,
) async {
  final base = await getApplicationCacheDirectory();
  final destination = Directory('${base.path}/incoming');
  return MobileTransferStore(destination);
});
