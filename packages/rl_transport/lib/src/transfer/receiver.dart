import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'storage.dart';
import 'transfer_crypto.dart';

const int kDefaultFileChunkSize = 256 * 1024;
const int kMaximumInFlightFileBytes = 4 * 1024 * 1024;
const int _tagLength = Primitives.macLength;

enum ChunkDisposition { accepted, duplicate, corrupt, refused }

enum CompletionDisposition { completed, incomplete, hashMismatch, refused }

final class OfferDecision {
  const OfferDecision({required this.accept, this.abort});

  final FileAccept accept;
  final FileAbort? abort;
}

final class _ReceivingFile {
  _ReceivingFile({
    required this.target,
    required this.fileIndex,
    required this.token,
  });

  final IncomingFile target;
  final int fileIndex;
  final String token;
}

/// Receive-side state machine for one authenticated connection.
final class FileTransferReceiver {
  FileTransferReceiver({
    required List<int> exporterSecret,
    required IncomingTransferStore store,
    required this.storageNamespace,
    this.maximumChunkSize = kDefaultFileChunkSize,
    Random? random,
  })  : _exporterSecret = Uint8List.fromList(exporterSecret),
        _store = store,
        _random = random ?? Random.secure() {
    if (maximumChunkSize <= 0 ||
        maximumChunkSize > kMaxFileChunkBytes - _tagLength) {
      throw ArgumentError.value(maximumChunkSize, 'maximumChunkSize');
    }
  }

  final Uint8List _exporterSecret;
  final IncomingTransferStore _store;
  final Random _random;
  final int maximumChunkSize;
  final String storageNamespace;

  final Log _log = Log.scoped('transfer.receiver');

  final Map<String, Uint8List> _keys = <String, Uint8List>{};
  final Map<String, String> _sessionIds = <String, String>{};
  final Map<String, Map<String, _ReceivingFile>> _files =
      <String, Map<String, _ReceivingFile>>{};
  Future<void> _receiveChain = Future<void>.value();

  Future<OfferDecision> acceptOffer(
    FileOffer offer, {
    required PermissionTier tier,
  }) =>
      _serialise(() => _acceptOfferNow(offer, tier: tier));

  Future<OfferDecision> _acceptOfferNow(
    FileOffer offer, {
    required PermissionTier tier,
  }) async {
    if (!tier.canTransferFiles) {
      return OfferDecision(
        accept: FileAccept(
          transferId: offer.transferId,
          sessionId: '',
          fileTokens: const <String, String>{},
        ),
        abort: FileAbort(
          transferId: offer.transferId,
          reason: FileAbortReason.declined,
        ),
      );
    }
    if (offer.transferId.isEmpty || offer.files.isEmpty) {
      return OfferDecision(
        accept: FileAccept(
          transferId: offer.transferId,
          sessionId: '',
          fileTokens: const <String, String>{},
        ),
        abort: FileAbort(
          transferId: offer.transferId,
          reason: FileAbortReason.declined,
        ),
      );
    }
    for (final file in offer.files) {
      if (file.fileId.isEmpty || file.size < 0) {
        return OfferDecision(
          accept: FileAccept(
            transferId: offer.transferId,
            sessionId: '',
            fileTokens: const <String, String>{},
          ),
          abort: FileAbort(
            transferId: offer.transferId,
            fileId: file.fileId,
            reason: FileAbortReason.declined,
          ),
        );
      }
    }

    final Map<String, IncomingFile> targets;
    try {
      targets = await _store.prepare(offer, namespace: storageNamespace);
    } on Object catch (error, stackTrace) {
      // `tooLarge` only when the store actually compared the numbers and came
      // up short. Everything else is `ioError`.
      //
      // This used to report every storage failure as `tooLarge`, and the
      // sender rendered that as "not enough storage space on peer" — which a
      // user saw for a 400 KB file when the real cause was a sandboxed app
      // with no permission to write to its download directory. Both paths
      // raised `FileSystemException`, so there was nothing to tell them apart
      // until the store grew a type for the one case it can be certain about.
      //
      // A wrong diagnosis is worse than a vague one: it sends whoever reads it
      // looking in the wrong direction, and they believe it because it sounds
      // specific.
      //
      // The exception itself only goes to the local log. The peer is told the
      // category and nothing more — a path or an OS error string from this
      // side is not something a remote device needs to hear.
      final outOfSpace = error is InsufficientSpaceError;
      _log.warn(
        'could not prepare storage for an incoming transfer',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{
          'transferId': offer.transferId,
          'files': offer.files.length,
          'outOfSpace': outOfSpace,
        },
      );
      return OfferDecision(
        accept: FileAccept(
          transferId: offer.transferId,
          sessionId: '',
          fileTokens: const <String, String>{},
        ),
        abort: FileAbort(
          transferId: offer.transferId,
          reason:
              outOfSpace ? FileAbortReason.tooLarge : FileAbortReason.ioError,
        ),
      );
    }

    final sessionId = _randomToken(18);
    final receiving = <String, _ReceivingFile>{};
    final tokens = <String, String>{};
    for (var index = 0; index < offer.files.length; index++) {
      final offered = offer.files[index];
      final target = targets[offered.fileId];
      if (target == null) continue;
      final firstGap = _firstGap(target.receivedRanges, offered.size);
      final token = '${_randomToken(24)}.$maximumChunkSize.$firstGap';
      tokens[offered.fileId] = token;
      receiving[offered.fileId] = _ReceivingFile(
        target: target,
        fileIndex: index,
        token: token,
      );
    }

    final previousKey = _keys.remove(offer.transferId);
    if (previousKey != null) Primitives.wipe(previousKey);
    _keys[offer.transferId] = await deriveTransferKey(
      _exporterSecret,
      offer.transferId,
    );
    _sessionIds[offer.transferId] = sessionId;
    _files[offer.transferId] = receiving;
    return OfferDecision(
      accept: FileAccept(
        transferId: offer.transferId,
        sessionId: sessionId,
        fileTokens: tokens,
      ),
    );
  }

  Future<ChunkDisposition> receiveChunk(
    FileChunk chunk, {
    required PermissionTier tier,
  }) =>
      _serialise(() => _receiveChunkNow(chunk, tier: tier));

  Future<ChunkDisposition> _receiveChunkNow(
    FileChunk chunk, {
    required PermissionTier tier,
  }) async {
    if (!tier.canTransferFiles) return ChunkDisposition.refused;
    final file = _files[chunk.transferId]?[chunk.fileId];
    final key = _keys[chunk.transferId];
    if (file == null ||
        key == null ||
        _sessionIds[chunk.transferId] != chunk.sessionId ||
        file.token != chunk.token ||
        chunk.offset < 0 ||
        chunk.bytes.length > maximumChunkSize + _tagLength) {
      return ChunkDisposition.refused;
    }

    final Uint8List plaintext;
    try {
      plaintext = await openChunk(
        key: key,
        fileIndex: file.fileIndex,
        transferId: chunk.transferId,
        fileId: chunk.fileId,
        offset: chunk.offset,
        sealed: chunk.bytes,
      );
    } on SecurityError {
      return ChunkDisposition.corrupt;
    }
    if (plaintext.isEmpty && file.target.offer.size != 0 ||
        chunk.offset + plaintext.length > file.target.offer.size) {
      return ChunkDisposition.refused;
    }
    if (_covers(
      file.target.receivedRanges,
      chunk.offset,
      chunk.offset + plaintext.length,
    )) {
      return ChunkDisposition.duplicate;
    }
    await file.target.write(chunk.offset, plaintext);
    return ChunkDisposition.accepted;
  }

  Future<CompletionDisposition> complete(
    FileComplete complete, {
    required PermissionTier tier,
  }) =>
      _serialise(() => _completeNow(complete, tier: tier));

  Future<CompletionDisposition> _completeNow(
    FileComplete complete, {
    required PermissionTier tier,
  }) async {
    if (!tier.canTransferFiles) return CompletionDisposition.refused;
    final file = _files[complete.transferId]?[complete.fileId];
    if (file == null) return CompletionDisposition.refused;
    final offer = file.target.offer;
    if (_firstGap(file.target.receivedRanges, offer.size) != offer.size) {
      return CompletionDisposition.incomplete;
    }

    final actual = await Primitives.sha256Stream(file.target.read());
    final offeredHash = offer.sha256;
    final matchesCompletion = Primitives.constantTimeEquals(
      actual,
      complete.sha256,
    );
    final matchesOffer = offeredHash == null ||
        Primitives.constantTimeEquals(actual, offeredHash);
    if (!matchesCompletion || !matchesOffer) {
      await file.target.delete();
      _files[complete.transferId]?.remove(complete.fileId);
      _finishTransferIfEmpty(complete.transferId);
      return CompletionDisposition.hashMismatch;
    }

    await file.target.commit();
    _files[complete.transferId]?.remove(complete.fileId);
    _finishTransferIfEmpty(complete.transferId);
    return CompletionDisposition.completed;
  }

  Future<void> abort(FileAbort abort, {required PermissionTier tier}) =>
      _serialise(() => _abortNow(abort, tier: tier));

  Future<void> _abortNow(
    FileAbort abort, {
    required PermissionTier tier,
  }) async {
    if (!tier.canTransferFiles) return;
    final files = _files[abort.transferId];
    if (files == null) return;
    if (abort.fileId case final fileId?) {
      await files.remove(fileId)?.target.delete();
      _finishTransferIfEmpty(abort.transferId);
    } else {
      for (final file in files.values) {
        await file.target.delete();
      }
      files.clear();
      _finishTransferIfEmpty(abort.transferId);
    }
  }

  void _finishTransferIfEmpty(String transferId) {
    final files = _files[transferId];
    if (files == null || files.isNotEmpty) return;
    _files.remove(transferId);
    _sessionIds.remove(transferId);
    final key = _keys.remove(transferId);
    if (key != null) Primitives.wipe(key);
  }

  Future<void> dispose() => _serialise(_disposeNow);

  Future<void> _disposeNow() async {
    for (final key in _keys.values) {
      Primitives.wipe(key);
    }
    _keys.clear();
    _sessionIds.clear();
    _files.clear();
    Primitives.wipe(_exporterSecret);
  }

  Future<T> _serialise<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _receiveChain = _receiveChain.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  String _randomToken(int byteLength) {
    final bytes = List<int>.generate(byteLength, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

int _firstGap(List<ReceivedRange> ranges, int size) {
  var offset = 0;
  final sorted = List<ReceivedRange>.from(ranges)
    ..sort((left, right) => left.start.compareTo(right.start));
  for (final range in sorted) {
    if (range.start > offset) return offset;
    if (range.end > offset) offset = range.end;
    if (offset >= size) return size;
  }
  return offset;
}

bool _covers(List<ReceivedRange> ranges, int start, int end) =>
    ranges.any((range) => range.start <= start && range.end >= end);
