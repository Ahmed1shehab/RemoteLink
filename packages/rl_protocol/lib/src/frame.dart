import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

import 'bytes.dart';
import 'crc32c.dart';
import 'message_type.dart';

/// Wire format version negotiated during the handshake.
///
/// Bumped only for changes that a previous version cannot parse. Adding a new
/// [MessageType] or appending fields to an existing payload does **not** bump
/// this: unknown types are ignored and trailing bytes are skipped, so both are
/// backward compatible by construction.
const int kProtocolVersion = 1;

/// Oldest version this build can still speak.
const int kMinSupportedProtocolVersion = 1;

/// Fixed frame header size in bytes.
///
/// ```text
/// offset size field
/// 0      1    version
/// 1      2    type              (u16, big endian)
/// 3      4    sequence          (u32)
/// 7      8    timestampMicros   (u64)
/// 15     1    flags
/// 16     4    payloadLength     (u32)
/// 20     N    payload
/// 20+N   4    crc32c            (present only when FrameFlags.hasChecksum)
/// ```
const int kFrameHeaderSize = 20;

/// Hard cap on a single frame's payload.
///
/// 16 MiB comfortably holds a full-resolution screen keyframe and a clipboard
/// image while bounding the memory a hostile peer can make us allocate before
/// authentication completes. File transfers exceed this and are chunked.
const int kMaxPayloadSize = 16 * 1024 * 1024;

/// Bit flags in the frame header.
extension type const FrameFlags(int bits) {
  static const FrameFlags none = FrameFlags(0);

  /// Payload is compressed. The codec is fixed per protocol version (v1: raw
  /// DEFLATE) rather than negotiated, to keep the fast path branch-free.
  static const int compressed = 0x01;

  /// Sender wants an [MessageType.ack] carrying this frame's sequence number.
  static const int requiresAck = 0x02;

  /// This frame *is* an acknowledgement.
  static const int isAck = 0x04;

  /// A CRC-32C trailer follows the payload.
  static const int hasChecksum = 0x08;

  /// Part of a multi-frame message (file chunks, large clipboard images).
  static const int fragment = 0x10;

  /// Final fragment of a fragmented message.
  static const int lastFragment = 0x20;

  bool get isCompressed => bits & compressed != 0;
  bool get needsAck => bits & requiresAck != 0;
  bool get acknowledges => bits & isAck != 0;
  bool get checksummed => bits & hasChecksum != 0;
  bool get isFragment => bits & fragment != 0;
  bool get isLastFragment => bits & lastFragment != 0;

  FrameFlags withFlag(int flag) => FrameFlags(bits | flag);
  FrameFlags withoutFlag(int flag) => FrameFlags(bits & ~flag);
}

/// One protocol frame: a header plus an opaque payload.
///
/// A [Frame] is transport-agnostic. On TCP it is wrapped in a 4-byte length
/// prefix and (after the handshake) sealed in a ChaCha20-Poly1305 record; on
/// the planned UDP input channel it is sent as a single datagram. Neither
/// wrapping is this class's concern.
@immutable
final class Frame {
  const Frame({
    required this.type,
    required this.sequence,
    required this.timestampMicros,
    required this.payload,
    this.version = kProtocolVersion,
    this.flags = FrameFlags.none,
  });

  final int version;
  final MessageType type;

  /// Monotonically increasing per direction, wrapping at 2^32.
  ///
  /// Used to correlate acknowledgements and to detect reordering on the
  /// unreliable channel. It is *not* a replay defence — that is the AEAD nonce
  /// counter's job, which is enforced independently in `rl_crypto`.
  final int sequence;

  /// Sender's monotonic clock in microseconds.
  ///
  /// Never compared across devices (the two clocks are unrelated). It is echoed
  /// back in acks so the sender can compute RTT against its own timeline, which
  /// avoids needing any clock synchronisation at all.
  final int timestampMicros;

  final FrameFlags flags;
  final Uint8List payload;

  /// Total encoded size including header and optional checksum trailer.
  int get encodedSize =>
      kFrameHeaderSize + payload.length + (flags.checksummed ? 4 : 0);

  Frame copyWith({
    MessageType? type,
    int? sequence,
    int? timestampMicros,
    FrameFlags? flags,
    Uint8List? payload,
  }) =>
      Frame(
        version: version,
        type: type ?? this.type,
        sequence: sequence ?? this.sequence,
        timestampMicros: timestampMicros ?? this.timestampMicros,
        flags: flags ?? this.flags,
        payload: payload ?? this.payload,
      );

  /// Serialises into [writer].
  ///
  /// Takes a writer rather than returning bytes so the caller can reuse one
  /// buffer for the lifetime of a connection. At 120 Hz mouse input this
  /// removes roughly 120 allocations per second per session.
  void writeTo(ByteWriter writer) {
    if (payload.length > kMaxPayloadSize) {
      throw ProtocolError(
        'payload_too_large',
        'payload ${payload.length} exceeds cap $kMaxPayloadSize',
      );
    }
    final headerStart = writer.length;
    writer
      ..writeUint8(version)
      ..writeUint16(type.code)
      ..writeUint32(sequence & 0xFFFFFFFF)
      ..writeUint64(timestampMicros)
      ..writeUint8(flags.bits)
      ..writeUint32(payload.length)
      ..writeBytes(payload);

    if (flags.checksummed) {
      final body = writer.viewBytes();
      final crc = Crc32c.compute(body, start: headerStart, end: writer.length);
      writer.writeUint32(crc);
    }
  }

  /// Convenience wrapper around [writeTo] for tests and one-off sends.
  Uint8List encode() {
    final writer = ByteWriter(initialCapacity: encodedSize);
    writeTo(writer);
    return writer.toBytes();
  }

  /// Parses one frame starting at the reader's cursor.
  ///
  /// [copyPayload] controls ownership: `false` returns a view into the source
  /// buffer, which is correct when the payload is decoded synchronously before
  /// the buffer is reused, and dangerous when the frame is queued. The session
  /// layer passes `false` and decodes immediately.
  static Frame readFrom(ByteReader reader, {bool copyPayload = true}) {
    final frameStart = reader.offset;
    final version = reader.readUint8();
    if (version < kMinSupportedProtocolVersion || version > kProtocolVersion) {
      throw ProtocolError(
        'version_unsupported',
        'frame version $version outside supported '
            '[$kMinSupportedProtocolVersion, $kProtocolVersion]',
      );
    }

    final typeCode = reader.readUint16();
    final sequence = reader.readUint32();
    final timestampMicros = reader.readUint64();
    final flags = FrameFlags(reader.readUint8());
    final payloadLength = reader.readUint32();

    if (payloadLength > kMaxPayloadSize) {
      throw ProtocolError(
        'payload_too_large',
        'declared payload $payloadLength exceeds cap $kMaxPayloadSize',
      );
    }
    if (reader.remaining < payloadLength + (flags.checksummed ? 4 : 0)) {
      throw ProtocolError(
        'truncated_frame',
        'declared $payloadLength bytes, ${reader.remaining} available',
      );
    }

    final payload = copyPayload
        ? reader.readBytes(payloadLength)
        : reader.readBytesView(payloadLength);

    if (flags.checksummed) {
      final bodyEnd = reader.offset;
      final expected = reader.readUint32();
      final actual = Crc32c.compute(
        _sourceOf(reader),
        start: frameStart,
        end: bodyEnd,
      );
      if (expected != actual) {
        throw ProtocolError(
          'checksum_mismatch',
          'crc32c expected 0x${expected.toRadixString(16)}, '
              'got 0x${actual.toRadixString(16)}',
        );
      }
    }

    return Frame(
      version: version,
      type: MessageType.fromCode(typeCode),
      sequence: sequence,
      timestampMicros: timestampMicros,
      flags: flags,
      payload: payload,
    );
  }

  /// Recovers the reader's backing store for checksum verification.
  ///
  /// [ByteReader] intentionally does not expose its buffer; this narrow helper
  /// exists so that stays true for every caller except checksum validation,
  /// which genuinely needs to re-read already-consumed bytes.
  static Uint8List _sourceOf(ByteReader reader) => reader.backingStore;

  @override
  String toString() => 'Frame(${type.name}, seq=$sequence, '
      '${payload.length}B, flags=0x${flags.bits.toRadixString(16)})';
}
