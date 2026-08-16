import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../bytes.dart';
import '../crc32c.dart';
import '../message_type.dart';
import 'message.dart';

/// Maximum number of files described by one offer or acceptance.
const int kMaxFileOfferCount = 1024;

/// Maximum UTF-8 length of a filename path component.
const int kMaxFileNameBytes = 255;

/// Maximum bytes carried by one [FileChunk].
const int kMaxFileChunkBytes = 1024 * 1024;

const int _maxIdentifierBytes = 128;
const int _maxTokenBytes = 256;
const int _maxMimeTypeBytes = 255;
const int _sha256Length = 32;

final RegExp _encodedOctet = RegExp(r'%[0-9a-fA-F]{2}');
final RegExp _driveLetter = RegExp(r'^[a-zA-Z]:');
final RegExp _windowsDeviceName = RegExp(
  r'^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
  caseSensitive: false,
);

/// Converts an untrusted peer-provided filename into one safe path component.
///
/// Unsafe names are rejected instead of rewritten. Rewriting separators or
/// trailing characters could make two distinct offers resolve to the same
/// local file. Valid names are returned in Unicode NFC so canonically
/// equivalent spellings cannot create separate files.
///
/// Percent-encoded octets are rejected wholesale. RemoteLink does not URL
/// decode filenames, and forbidding encoded octets prevents a later layer from
/// accidentally turning `%2e%2e`, a nested encoding, or an over-long encoded
/// UTF-8 sequence into traversal syntax.
String sanitiseFileName(String untrustedName) {
  if (untrustedName.isEmpty || untrustedName.trim().isEmpty) {
    throw const ProtocolError('unsafe_file_name', 'filename is empty');
  }

  final fileName = unicode.nfc(untrustedName);
  if (fileName.contains('/') || fileName.contains(r'\')) {
    throw const ProtocolError(
      'unsafe_file_name',
      'filename contains a path separator',
    );
  }
  if (fileName.contains('..') || _encodedOctet.hasMatch(fileName)) {
    throw const ProtocolError(
      'unsafe_file_name',
      'filename contains encoded or literal traversal syntax',
    );
  }
  if (_driveLetter.hasMatch(fileName)) {
    throw const ProtocolError(
      'unsafe_file_name',
      'filename contains a Windows drive letter',
    );
  }
  if (_windowsDeviceName.hasMatch(fileName)) {
    throw const ProtocolError(
      'unsafe_file_name',
      'filename is a reserved Windows device name',
    );
  }
  if (fileName.endsWith('.') || fileName.endsWith(' ')) {
    throw const ProtocolError(
      'unsafe_file_name',
      'filename has a trailing dot or space',
    );
  }
  if (fileName.runes.any(_isControlCharacter)) {
    throw const ProtocolError(
      'unsafe_file_name',
      'filename contains a control character',
    );
  }

  final encodedLength = utf8.encode(fileName).length;
  if (encodedLength > kMaxFileNameBytes) {
    throw ProtocolError(
      'unsafe_file_name',
      'filename is $encodedLength bytes, cap is $kMaxFileNameBytes',
    );
  }
  return fileName;
}

bool _isControlCharacter(int codePoint) =>
    codePoint <= 0x1F || (codePoint >= 0x7F && codePoint <= 0x9F);

/// LocalSend-style metadata for one file in a [FileOffer].
///
/// [fileName] is normalised and validated by [sanitiseFileName] during
/// construction, so callers never receive an untrusted raw name as a usable
/// path component.
@immutable
final class OfferedFile {
  OfferedFile({
    required this.fileId,
    required String fileName,
    required this.size,
    required this.fileType,
    Uint8List? sha256,
    this.modifiedAt,
    this.accessedAt,
  })  : fileName = sanitiseFileName(fileName),
        sha256 = _copySha256(sha256);

  final String fileId;
  final String fileName;
  final int size;
  final String fileType;
  final Uint8List? sha256;
  final DateTime? modifiedAt;
  final DateTime? accessedAt;

  void writeTo(ByteWriter writer) {
    writer
      ..writeString(fileId)
      ..writeString(fileName)
      ..writeUint64(size)
      ..writeString(fileType);

    final hash = sha256;
    final modified = modifiedAt;
    final accessed = accessedAt;
    writer.writeUint8(
      (hash == null ? 0 : 1) |
          (modified == null ? 0 : 2) |
          (accessed == null ? 0 : 4),
    );
    if (hash != null) writer.writeBytes(hash);
    if (modified != null) {
      writer.writeUint64(modified.toUtc().microsecondsSinceEpoch);
    }
    if (accessed != null) {
      writer.writeUint64(accessed.toUtc().microsecondsSinceEpoch);
    }
  }

  static OfferedFile readFrom(ByteReader reader) {
    final fileId = reader.readString(maxLength: _maxIdentifierBytes);
    final fileName = reader.readString(maxLength: kMaxFileNameBytes);
    final size = reader.readUint64();
    final fileType = reader.readString(maxLength: _maxMimeTypeBytes);
    final flags = reader.readUint8();
    return OfferedFile(
      fileId: fileId,
      fileName: fileName,
      size: size,
      fileType: fileType,
      sha256: flags & 1 == 0 ? null : reader.readBytes(_sha256Length),
      modifiedAt: flags & 2 == 0 ? null : _readTimestamp(reader),
      accessedAt: flags & 4 == 0 ? null : _readTimestamp(reader),
    );
  }
}

/// Offers metadata for files the sender wants to transfer.
///
/// The data model follows LocalSend's `prepare-upload`, but RemoteLink carries
/// it inside its authenticated, encrypted session instead of HTTP+TLS. There
/// is therefore no URL, query parameter, or PIN: SAS pairing already
/// authenticated the peer.
@immutable
final class FileOffer extends Message {
  FileOffer({required this.transferId, required List<OfferedFile> files})
      : files = List<OfferedFile>.unmodifiable(files);

  final String transferId;
  final List<OfferedFile> files;

  @override
  MessageType get type => MessageType.fileOffer;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(transferId)
      ..writeVarUint(files.length);
    for (final file in files) {
      file.writeTo(writer);
    }
  }

  static FileOffer readFrom(ByteReader reader) {
    final transferId = reader.readString(maxLength: _maxIdentifierBytes);
    final count = _readFileCount(reader);
    final files = <OfferedFile>[];
    final fileIds = <String>{};
    for (var index = 0; index < count; index++) {
      final file = OfferedFile.readFrom(reader);
      if (!fileIds.add(file.fileId)) {
        throw ProtocolError(
          'duplicate_file_id',
          'file offer repeats file id ${file.fileId}',
        );
      }
      files.add(file);
    }
    return FileOffer(transferId: transferId, files: files);
  }
}

/// Accepts all or part of a [FileOffer].
///
/// As in LocalSend's `prepare-upload` response, [fileTokens] contains only
/// accepted file IDs. A declined file is absent, which supports partial
/// acceptance without another message type. Unlike LocalSend, these tokens do
/// not authenticate an HTTP request; each is only a per-file replay guard
/// within RemoteLink's already-authenticated channel.
@immutable
final class FileAccept extends Message {
  const FileAccept({
    required this.transferId,
    required this.sessionId,
    required this.fileTokens,
  });

  final String transferId;
  final String sessionId;
  final Map<String, String> fileTokens;

  @override
  MessageType get type => MessageType.fileAccept;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(transferId)
      ..writeString(sessionId)
      ..writeVarUint(fileTokens.length);
    for (final MapEntry(:key, :value) in fileTokens.entries) {
      writer
        ..writeString(key)
        ..writeString(value);
    }
  }

  static FileAccept readFrom(ByteReader reader) {
    final transferId = reader.readString(maxLength: _maxIdentifierBytes);
    final sessionId = reader.readString(maxLength: _maxIdentifierBytes);
    final count = _readFileCount(reader);
    final fileTokens = <String, String>{};
    for (var index = 0; index < count; index++) {
      final fileId = reader.readString(maxLength: _maxIdentifierBytes);
      final token = reader.readString(maxLength: _maxTokenBytes);
      if (fileTokens.containsKey(fileId)) {
        throw ProtocolError(
          'duplicate_file_id',
          'file acceptance repeats file id $fileId',
        );
      }
      fileTokens[fileId] = token;
    }
    return FileAccept(
      transferId: transferId,
      sessionId: sessionId,
      fileTokens: Map<String, String>.unmodifiable(fileTokens),
    );
  }
}

/// Carries one independently verified range of file bytes.
///
/// This replaces LocalSend's HTTP upload body and query parameters. Routing
/// fields travel in the encrypted payload, [token] is an in-channel replay
/// guard rather than primary authentication, and [crc32c] catches corruption
/// before a chunk is handed to storage.
@immutable
final class FileChunk extends Message {
  FileChunk({
    required this.transferId,
    required this.sessionId,
    required this.fileId,
    required this.token,
    required this.offset,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes);

  final String transferId;
  final String sessionId;
  final String fileId;
  final String token;
  final int offset;
  final Uint8List bytes;

  int get crc32c => Crc32c.compute(bytes);

  @override
  MessageType get type => MessageType.fileChunk;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(transferId)
      ..writeString(sessionId)
      ..writeString(fileId)
      ..writeString(token)
      ..writeUint64(offset)
      ..writeLengthPrefixedBytes(bytes)
      ..writeUint32(crc32c);
  }

  static FileChunk readFrom(ByteReader reader) {
    final transferId = reader.readString(maxLength: _maxIdentifierBytes);
    final sessionId = reader.readString(maxLength: _maxIdentifierBytes);
    final fileId = reader.readString(maxLength: _maxIdentifierBytes);
    final token = reader.readString(maxLength: _maxTokenBytes);
    final offset = reader.readUint64();
    final bytes = reader.readLengthPrefixedBytes(
      maxLength: kMaxFileChunkBytes,
    );
    final expectedCrc32c = reader.readUint32();
    final actualCrc32c = Crc32c.compute(bytes);
    if (actualCrc32c != expectedCrc32c) {
      throw ProtocolError(
        'file_chunk_checksum_mismatch',
        'file chunk CRC-32C mismatch: expected '
            '0x${expectedCrc32c.toRadixString(16)}, got '
            '0x${actualCrc32c.toRadixString(16)}',
      );
    }
    return FileChunk(
      transferId: transferId,
      sessionId: sessionId,
      fileId: fileId,
      token: token,
      offset: offset,
      bytes: bytes,
    );
  }
}

/// Marks one file complete and supplies its final whole-file SHA-256.
@immutable
final class FileComplete extends Message {
  FileComplete({
    required this.transferId,
    required this.fileId,
    required Uint8List sha256,
  }) : sha256 = _copyRequiredSha256(sha256);

  final String transferId;
  final String fileId;
  final Uint8List sha256;

  @override
  MessageType get type => MessageType.fileComplete;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(transferId)
      ..writeString(fileId)
      ..writeBytes(sha256);
  }

  static FileComplete readFrom(ByteReader reader) => FileComplete(
        transferId: reader.readString(maxLength: _maxIdentifierBytes),
        fileId: reader.readString(maxLength: _maxIdentifierBytes),
        sha256: reader.readBytes(_sha256Length),
      );
}

/// Why a file or whole transfer was aborted.
enum FileAbortReason {
  declined(1),
  cancelled(2),
  ioError(3),
  hashMismatch(4),
  tooLarge(5),
  timeout(6);

  const FileAbortReason(this.wireValue);

  final int wireValue;

  static FileAbortReason fromWire(int value) => values.firstWhere(
        (reason) => reason.wireValue == value,
        orElse: () => FileAbortReason.cancelled,
      );
}

/// Aborts either an entire transfer or, when [fileId] is present, one file.
@immutable
final class FileAbort extends Message {
  const FileAbort(
      {required this.transferId, this.fileId, required this.reason});

  final String transferId;
  final String? fileId;
  final FileAbortReason reason;

  @override
  MessageType get type => MessageType.fileAbort;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(transferId)
      ..writeOptionalString(fileId)
      ..writeUint8(reason.wireValue);
  }

  static FileAbort readFrom(ByteReader reader) => FileAbort(
        transferId: reader.readString(maxLength: _maxIdentifierBytes),
        fileId: reader.readOptionalString(maxLength: _maxIdentifierBytes),
        reason: FileAbortReason.fromWire(reader.readUint8()),
      );
}

int _readFileCount(ByteReader reader) {
  final count = reader.readVarUint();
  if (count > kMaxFileOfferCount) {
    throw ProtocolError(
      'file_count_limit',
      'file transfer declared $count files, cap is $kMaxFileOfferCount',
    );
  }
  return count;
}

Uint8List? _copySha256(Uint8List? hash) =>
    hash == null ? null : _copyRequiredSha256(hash);

Uint8List _copyRequiredSha256(Uint8List hash) {
  if (hash.length != _sha256Length) {
    throw ArgumentError.value(
      hash.length,
      'sha256',
      'SHA-256 must be exactly $_sha256Length bytes',
    );
  }
  return Uint8List.fromList(hash);
}

DateTime _readTimestamp(ByteReader reader) {
  final microseconds = reader.readUint64();
  try {
    return DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
  } on ArgumentError catch (error) {
    throw ProtocolError(
      'bad_file_timestamp',
      'file timestamp is outside the supported DateTime range',
      cause: error,
    );
  }
}
