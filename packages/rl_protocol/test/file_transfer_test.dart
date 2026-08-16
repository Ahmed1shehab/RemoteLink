import 'dart:convert';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

T _roundTrip<T extends Message>(T message) {
  final codec = MessageCodec(clock: FakeClock());
  final decoded = codec.decode(codec.encode(message));
  expect(decoded, isA<T>());
  return decoded as T;
}

Matcher _protocolError(String code) => throwsA(
      isA<ProtocolError>().having((error) => error.code, 'code', code),
    );

Uint8List _sha(int byte) => Uint8List.fromList(List<int>.filled(32, byte));

void main() {
  group('file-transfer message round trips', () {
    test('FileOffer preserves LocalSend-style metadata', () {
      final modifiedAt = DateTime.utc(2025, 1, 2, 3, 4, 5, 6, 7);
      final accessedAt = DateTime.utc(2025, 2, 3, 4, 5, 6, 7, 8);
      final decoded = _roundTrip(
        FileOffer(
          transferId: 'transfer-1',
          files: <OfferedFile>[
            OfferedFile(
              fileId: 'file-a',
              fileName: 'caf\u00e9.txt',
              size: 123456789,
              fileType: 'text/plain',
              sha256: _sha(1),
              modifiedAt: modifiedAt,
              accessedAt: accessedAt,
            ),
            OfferedFile(
              fileId: 'file-b',
              fileName: 'photo.jpg',
              size: 42,
              fileType: 'image/jpeg',
            ),
          ],
        ),
      );

      expect(decoded.transferId, 'transfer-1');
      expect(decoded.files, hasLength(2));
      expect(decoded.files.first.fileId, 'file-a');
      expect(decoded.files.first.fileName, 'caf\u00e9.txt');
      expect(decoded.files.first.size, 123456789);
      expect(decoded.files.first.fileType, 'text/plain');
      expect(decoded.files.first.sha256, _sha(1));
      expect(decoded.files.first.modifiedAt, modifiedAt);
      expect(decoded.files.first.accessedAt, accessedAt);
      expect(decoded.files.last.sha256, isNull);
      expect(decoded.files.last.modifiedAt, isNull);
      expect(decoded.files.last.accessedAt, isNull);
    });

    test('FileAccept represents partial acceptance by map omission', () {
      final decoded = _roundTrip(
        const FileAccept(
          transferId: 'transfer-1',
          sessionId: 'session-1',
          fileTokens: <String, String>{'file-a': 'token-a'},
        ),
      );

      expect(decoded.transferId, 'transfer-1');
      expect(decoded.sessionId, 'session-1');
      expect(decoded.fileTokens, <String, String>{'file-a': 'token-a'});
      expect(decoded.fileTokens, isNot(contains('file-b')));
    });

    test('FileChunk preserves routing fields, offset, bytes, and CRC-32C', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      final decoded = _roundTrip(
        FileChunk(
          transferId: 'transfer-1',
          sessionId: 'session-1',
          fileId: 'file-a',
          token: 'token-a',
          offset: 1 << 40,
          bytes: bytes,
        ),
      );

      expect(decoded.transferId, 'transfer-1');
      expect(decoded.sessionId, 'session-1');
      expect(decoded.fileId, 'file-a');
      expect(decoded.token, 'token-a');
      expect(decoded.offset, 1 << 40);
      expect(decoded.bytes, bytes);
      expect(decoded.crc32c, Crc32c.compute(bytes));
    });

    test('FileComplete carries the final whole-file SHA-256', () {
      final decoded = _roundTrip(
        FileComplete(
          transferId: 'transfer-1',
          fileId: 'file-a',
          sha256: _sha(9),
        ),
      );

      expect(decoded.transferId, 'transfer-1');
      expect(decoded.fileId, 'file-a');
      expect(decoded.sha256, _sha(9));
    });

    test('FileAbort carries transfer-wide and per-file aborts', () {
      final perFile = _roundTrip(
        const FileAbort(
          transferId: 'transfer-1',
          fileId: 'file-a',
          reason: FileAbortReason.hashMismatch,
        ),
      );
      final wholeTransfer = _roundTrip(
        const FileAbort(
          transferId: 'transfer-1',
          reason: FileAbortReason.cancelled,
        ),
      );

      expect(perFile.fileId, 'file-a');
      expect(perFile.reason, FileAbortReason.hashMismatch);
      expect(wholeTransfer.fileId, isNull);
      expect(wholeTransfer.reason, FileAbortReason.cancelled);
    });

    test('a corrupted FileChunk checksum is rejected', () {
      final chunk = FileChunk(
        transferId: 'transfer-1',
        sessionId: 'session-1',
        fileId: 'file-a',
        token: 'token-a',
        offset: 0,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final payload = chunk.encodePayload()..last ^= 0xFF;
      final frame = Frame(
        type: MessageType.fileChunk,
        sequence: 0,
        timestampMicros: 0,
        payload: payload,
      );

      expect(
        () => MessageCodec(clock: FakeClock()).decode(frame),
        _protocolError('protocol.file_chunk_checksum_mismatch'),
      );
    });
  });

  group('bounded file-transfer decoders', () {
    test('FileOffer rejects a file count above the cap before entries', () {
      final writer = ByteWriter()
        ..writeString('transfer-1')
        ..writeVarUint(kMaxFileOfferCount + 1);
      final frame = Frame(
        type: MessageType.fileOffer,
        sequence: 0,
        timestampMicros: 0,
        payload: writer.toBytes(),
      );

      expect(
        () => MessageCodec(clock: FakeClock()).decode(frame),
        _protocolError('protocol.file_count_limit'),
      );
    });

    test('FileOffer checks name length before reading name bytes', () {
      final writer = ByteWriter()
        ..writeString('transfer-1')
        ..writeVarUint(1)
        ..writeString('file-a')
        ..writeVarUint(kMaxFileNameBytes + 1);
      final frame = Frame(
        type: MessageType.fileOffer,
        sequence: 0,
        timestampMicros: 0,
        payload: writer.toBytes(),
      );

      expect(
        () => MessageCodec(clock: FakeClock()).decode(frame),
        _protocolError('protocol.length_limit'),
      );
    });

    test('FileAccept rejects an accepted-file count above the cap', () {
      final writer = ByteWriter()
        ..writeString('transfer-1')
        ..writeString('session-1')
        ..writeVarUint(kMaxFileOfferCount + 1);
      final frame = Frame(
        type: MessageType.fileAccept,
        sequence: 0,
        timestampMicros: 0,
        payload: writer.toBytes(),
      );

      expect(
        () => MessageCodec(clock: FakeClock()).decode(frame),
        _protocolError('protocol.file_count_limit'),
      );
    });

    test('FileChunk checks chunk size before reading chunk bytes', () {
      final writer = ByteWriter()
        ..writeString('transfer-1')
        ..writeString('session-1')
        ..writeString('file-a')
        ..writeString('token-a')
        ..writeUint64(0)
        ..writeVarUint(kMaxFileChunkBytes + 1);
      final frame = Frame(
        type: MessageType.fileChunk,
        sequence: 0,
        timestampMicros: 0,
        payload: writer.toBytes(),
      );

      expect(
        () => MessageCodec(clock: FakeClock()).decode(frame),
        _protocolError('protocol.length_limit'),
      );
    });
  });

  group('sanitiseFileName accepts safe path components', () {
    test('preserves a plain filename', () {
      expect(sanitiseFileName('quarterly report.pdf'), 'quarterly report.pdf');
    });

    test('normalises canonically equivalent text to Unicode NFC', () {
      expect(sanitiseFileName('cafe\u0301.txt'), 'caf\u00e9.txt');
    });

    test('allows a literal percent that is not an encoded octet', () {
      expect(sanitiseFileName('100% complete.txt'), '100% complete.txt');
    });

    test('allows exactly 255 encoded bytes', () {
      final name = '${'a' * 251}.txt';
      expect(utf8.encode(name), hasLength(255));
      expect(sanitiseFileName(name), name);
    });
  });

  group('sanitiseFileName rejects adversarial names', () {
    test('empty name', () {
      expect(() => sanitiseFileName(''),
          _protocolError('protocol.unsafe_file_name'));
    });

    test('name empty after trimming', () {
      expect(
        () => sanitiseFileName(' \t '),
        _protocolError('protocol.unsafe_file_name'),
      );
    });

    test('forward-slash path separator', () {
      expect(
        () => sanitiseFileName('safe/escape.txt'),
        _protocolError('protocol.unsafe_file_name'),
      );
    });

    test('backslash path separator', () {
      expect(
        () => sanitiseFileName(r'safe\escape.txt'),
        _protocolError('protocol.unsafe_file_name'),
      );
    });

    test('literal dot-dot anywhere in the name', () {
      for (final name in <String>['..', '../secret', 'report..txt']) {
        expect(
          () => sanitiseFileName(name),
          _protocolError('protocol.unsafe_file_name'),
          reason: name,
        );
      }
    });

    test('percent-encoded and repeatedly encoded dot-dot', () {
      for (final name in <String>[
        '%2e%2e',
        '%2E.',
        '%252e%252e',
        '%c0%ae%c0%ae',
        '%e0%80%ae%e0%80%ae',
        '%f0%80%80%ae%f0%80%80%ae',
      ]) {
        expect(
          () => sanitiseFileName(name),
          _protocolError('protocol.unsafe_file_name'),
          reason: name,
        );
      }
    });

    test('absolute Unix and Windows paths', () {
      for (final name in <String>['/etc/passwd', r'\Windows\system.ini']) {
        expect(
          () => sanitiseFileName(name),
          _protocolError('protocol.unsafe_file_name'),
          reason: name,
        );
      }
    });

    test('Windows drive letters', () {
      for (final name in <String>['C:secret.txt', 'z:file.txt']) {
        expect(
          () => sanitiseFileName(name),
          _protocolError('protocol.unsafe_file_name'),
          reason: name,
        );
      }
    });

    test('Windows reserved device names with case and extensions', () {
      for (final name in <String>[
        'CON',
        'con.txt',
        'PRN.pdf',
        'AUX',
        'nul.bin',
        'COM1',
        'com9.log',
        'LPT1',
        'lpt9.txt',
      ]) {
        expect(
          () => sanitiseFileName(name),
          _protocolError('protocol.unsafe_file_name'),
          reason: name,
        );
      }
    });

    test('trailing dot', () {
      expect(
        () => sanitiseFileName('report.txt.'),
        _protocolError('protocol.unsafe_file_name'),
      );
    });

    test('trailing space', () {
      expect(
        () => sanitiseFileName('report.txt '),
        _protocolError('protocol.unsafe_file_name'),
      );
    });

    test('NUL and other C0/C1 control characters', () {
      for (final name in <String>[
        'nul\u0000.txt',
        'line\nfeed.txt',
        'delete\u007f.txt',
        'c1\u0085.txt',
      ]) {
        expect(
          () => sanitiseFileName(name),
          _protocolError('protocol.unsafe_file_name'),
          reason: name,
        );
      }
    });

    test('encoded length above 255 bytes', () {
      final name = '${'a' * 252}.txt';
      expect(utf8.encode(name), hasLength(256));
      expect(
        () => sanitiseFileName(name),
        _protocolError('protocol.unsafe_file_name'),
      );
    });

    test('over-long UTF-8 bytes are rejected by FileOffer decoding', () {
      final writer = ByteWriter()
        ..writeString('transfer-1')
        ..writeVarUint(1)
        ..writeString('file-a')
        ..writeVarUint(2)
        ..writeBytes(<int>[0xC0, 0xAE]);
      final frame = Frame(
        type: MessageType.fileOffer,
        sequence: 0,
        timestampMicros: 0,
        payload: writer.toBytes(),
      );

      expect(
        () => MessageCodec(clock: FakeClock()).decode(frame),
        _protocolError('protocol.bad_utf8'),
      );
    });

    test('FileOffer decoding cannot bypass filename sanitisation', () {
      final writer = ByteWriter()
        ..writeString('transfer-1')
        ..writeVarUint(1)
        ..writeString('file-a')
        ..writeString('../secret.txt')
        ..writeUint64(10)
        ..writeString('text/plain')
        ..writeUint8(0);
      final frame = Frame(
        type: MessageType.fileOffer,
        sequence: 0,
        timestampMicros: 0,
        payload: writer.toBytes(),
      );

      expect(
        () => MessageCodec(clock: FakeClock()).decode(frame),
        _protocolError('protocol.unsafe_file_name'),
      );
    });
  });
}
