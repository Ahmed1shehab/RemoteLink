import 'dart:async';
import 'dart:typed_data';

import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'receiver.dart';
import 'storage.dart';
import 'transfer_crypto.dart';

typedef SendFileChunk = Future<void> Function(FileChunk chunk);
typedef SendFileComplete = Future<void> Function(FileComplete complete);

final class _AcceptanceToken {
  const _AcceptanceToken({
    required this.raw,
    required this.chunkSize,
    required this.firstGap,
  });

  final String raw;
  final int chunkSize;
  final int firstGap;

  static _AcceptanceToken? parse(String raw) {
    final parts = raw.split('.');
    if (parts.length != 3) return null;
    final chunkSize = int.tryParse(parts[1]);
    final firstGap = int.tryParse(parts[2]);
    if (chunkSize == null ||
        firstGap == null ||
        chunkSize <= 0 ||
        chunkSize > kMaxFileChunkBytes - Primitives.macLength ||
        firstGap < 0) {
      return null;
    }
    return _AcceptanceToken(raw: raw, chunkSize: chunkSize, firstGap: firstGap);
  }
}

/// Bounds chunks awaiting application acknowledgement.
final class FileTransferFlowControl {
  FileTransferFlowControl({this.maximumBytes = kMaximumInFlightFileBytes});

  final int maximumBytes;
  int _inFlightBytes = 0;
  int _maximumObservedBytes = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  int get inFlightBytes => _inFlightBytes;
  int get maximumObservedBytes => _maximumObservedBytes;

  Future<FileTransferPermit> acquire(int byteCount) async {
    if (byteCount <= 0 || byteCount > maximumBytes) {
      throw ArgumentError.value(byteCount, 'byteCount');
    }
    while (_inFlightBytes + byteCount > maximumBytes) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _inFlightBytes += byteCount;
    if (_inFlightBytes > _maximumObservedBytes) {
      _maximumObservedBytes = _inFlightBytes;
    }
    return FileTransferPermit._(this, byteCount);
  }

  Future<T> run<T>(int byteCount, Future<T> Function() operation) async {
    final permit = await acquire(byteCount);
    try {
      return await operation();
    } finally {
      permit.release();
    }
  }

  void _release(int byteCount) {
    _inFlightBytes -= byteCount;
    final waiters = List<Completer<void>>.from(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }
}

final class FileTransferPermit {
  FileTransferPermit._(this._owner, this.byteCount);

  final FileTransferFlowControl _owner;
  final int byteCount;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _owner._release(byteCount);
  }
}

/// Outgoing state machine. [sendChunk] completes only when the peer acks it.
final class FileTransferSender {
  FileTransferSender({
    required List<int> exporterSecret,
    FileTransferFlowControl? flowControl,
  })  : _exporterSecret = Uint8List.fromList(exporterSecret),
        flowControl = flowControl ?? FileTransferFlowControl();

  final Uint8List _exporterSecret;
  final FileTransferFlowControl flowControl;

  Future<void> sendAccepted({
    required FileOffer offer,
    required FileAccept accept,
    required Map<String, OutgoingFile> sources,
    required SendFileChunk sendChunk,
    required SendFileComplete sendComplete,
  }) async {
    if (accept.transferId != offer.transferId) {
      throw ArgumentError('acceptance belongs to a different transfer');
    }
    final key = await deriveTransferKey(_exporterSecret, offer.transferId);
    try {
      for (var fileIndex = 0; fileIndex < offer.files.length; fileIndex++) {
        final offered = offer.files[fileIndex];
        final rawToken = accept.fileTokens[offered.fileId];
        if (rawToken == null) continue;
        final token = _AcceptanceToken.parse(rawToken);
        final source = sources[offered.fileId];
        if (token == null || source == null || source.size != offered.size) {
          throw ArgumentError(
            'invalid acceptance or source for ${offered.fileId}',
          );
        }
        if (token.firstGap > source.size) {
          throw ArgumentError('resume offset exceeds ${offered.fileId}');
        }

        final pending = <Future<void>>{};
        Object? firstSendError;
        StackTrace? firstSendStack;
        var offset = token.firstGap;
        while (offset < source.size) {
          final remaining = source.size - offset;
          final length =
              remaining < token.chunkSize ? remaining : token.chunkSize;
          final chunkOffset = offset;
          final permit = await flowControl.acquire(
            length + Primitives.macLength,
          );
          try {
            final plaintext = await source.read(chunkOffset, length);
            if (plaintext.length != length) {
              throw StateError(
                'short read for ${offered.fileId} at $chunkOffset',
              );
            }
            final sealed = await sealChunk(
              key: key,
              fileIndex: fileIndex,
              transferId: offer.transferId,
              fileId: offered.fileId,
              offset: chunkOffset,
              plaintext: plaintext,
            );
            final future = sendChunk(
              FileChunk(
                transferId: offer.transferId,
                sessionId: accept.sessionId,
                fileId: offered.fileId,
                token: token.raw,
                offset: chunkOffset,
                bytes: sealed,
              ),
            );
            late final Future<void> tracked;
            tracked = future.then<void>(
              (_) {},
              onError: (Object error, StackTrace stackTrace) {
                firstSendError ??= error;
                firstSendStack ??= stackTrace;
              },
            ).whenComplete(() {
              permit.release();
              pending.remove(tracked);
            });
            pending.add(tracked);
          } on Object {
            permit.release();
            rethrow;
          }
          offset += length;
        }
        await Future.wait(pending.toList());
        if (firstSendError case final error?) {
          Error.throwWithStackTrace(error, firstSendStack!);
        }
        final hash = await Primitives.sha256Stream(source.readAll());
        await sendComplete(
          FileComplete(
            transferId: offer.transferId,
            fileId: offered.fileId,
            sha256: hash,
          ),
        );
      }
    } finally {
      Primitives.wipe(key);
    }
  }
}
