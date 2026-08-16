import 'dart:convert';
import 'dart:typed_data';

import 'package:rl_crypto/rl_crypto.dart';

const String _transferLabelPrefix = 'rl1 file ';

Future<Uint8List> deriveTransferKey(
  List<int> exporterSecret,
  String transferId,
) =>
    Primitives.hkdf(
      secret: exporterSecret,
      salt: const <int>[],
      info: '$_transferLabelPrefix$transferId',
    );

Uint8List chunkNonce(int fileIndex, int offset) {
  final nonce = Uint8List(Primitives.nonceLength);
  final data = ByteData.sublistView(nonce)
    ..setUint32(0, fileIndex, Endian.big)
    ..setUint64(4, offset, Endian.big);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

List<int> chunkAssociatedData({
  required String transferId,
  required String fileId,
  required int offset,
}) =>
    utf8.encode('$transferId\u0000$fileId\u0000$offset');

Future<Uint8List> sealChunk({
  required Uint8List key,
  required int fileIndex,
  required String transferId,
  required String fileId,
  required int offset,
  required Uint8List plaintext,
}) =>
    Primitives.sealAtNonce(
      key: key,
      nonce: chunkNonce(fileIndex, offset),
      plaintext: plaintext,
      aad: chunkAssociatedData(
        transferId: transferId,
        fileId: fileId,
        offset: offset,
      ),
    );

Future<Uint8List> openChunk({
  required Uint8List key,
  required int fileIndex,
  required String transferId,
  required String fileId,
  required int offset,
  required Uint8List sealed,
}) =>
    Primitives.openAtNonce(
      key: key,
      nonce: chunkNonce(fileIndex, offset),
      sealed: sealed,
      aad: chunkAssociatedData(
        transferId: transferId,
        fileId: fileId,
        offset: offset,
      ),
    );
