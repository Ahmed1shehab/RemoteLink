import 'dart:typed_data';

import 'package:rl_protocol/rl_protocol.dart';

/// A half-open byte range persisted for an incoming file.
final class ReceivedRange {
  const ReceivedRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
}

/// Storage owned by the host application for one incoming file.
///
/// Implementations must persist [write] and its updated range manifest before
/// the returned future completes. The transfer engine deliberately knows
/// nothing about paths or `dart:io`.
abstract interface class IncomingFile {
  OfferedFile get offer;
  List<ReceivedRange> get receivedRanges;

  Future<void> write(int offset, Uint8List bytes);
  Stream<List<int>> read();
  Future<void> commit();
  Future<void> delete();
}

/// Host-provided persistence and filesystem policy for incoming transfers.
abstract interface class IncomingTransferStore {
  /// Validates and reserves the complete offer before opening any file.
  ///
  /// This is where a filesystem implementation performs canonical path and
  /// free-space checks. Existing partials may be returned for a resumed offer.
  Future<Map<String, IncomingFile>> prepare(
    FileOffer offer, {
    required String namespace,
  });
}

/// In-memory or filesystem-backed source for an outgoing file.
abstract interface class OutgoingFile {
  int get size;

  Future<Uint8List> read(int offset, int length);
  Stream<List<int>> readAll();
}
