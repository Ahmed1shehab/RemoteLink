import 'dart:convert';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';

/// Growable big-endian byte builder.
///
/// Big-endian ("network order") is used throughout the protocol so that frames
/// are readable in a packet capture without byte-swapping, and so that a future
/// non-Dart implementation has no ambiguity to resolve.
///
/// The buffer grows by doubling and is reused across frames via
/// [ByteWriter.reset], which matters on the input hot path: at 120 Hz a
/// per-event allocation would add measurable GC pressure.
final class ByteWriter {
  ByteWriter({int initialCapacity = 256})
      : _buffer = Uint8List(initialCapacity),
        _length = 0 {
    _view = ByteData.view(_buffer.buffer);
  }

  Uint8List _buffer;
  late ByteData _view;
  int _length;

  /// Number of bytes written so far.
  int get length => _length;

  void _ensure(int extra) {
    final required = _length + extra;
    if (required <= _buffer.length) return;
    var capacity = _buffer.length == 0 ? 64 : _buffer.length;
    while (capacity < required) {
      capacity *= 2;
    }
    final grown = Uint8List(capacity)..setRange(0, _length, _buffer);
    _buffer = grown;
    _view = ByteData.view(_buffer.buffer);
  }

  void writeUint8(int value) {
    _ensure(1);
    _view.setUint8(_length, value);
    _length += 1;
  }

  void writeInt8(int value) {
    _ensure(1);
    _view.setInt8(_length, value);
    _length += 1;
  }

  void writeUint16(int value) {
    _ensure(2);
    _view.setUint16(_length, value, Endian.big);
    _length += 2;
  }

  void writeInt16(int value) {
    _ensure(2);
    _view.setInt16(_length, value, Endian.big);
    _length += 2;
  }

  void writeUint32(int value) {
    _ensure(4);
    _view.setUint32(_length, value, Endian.big);
    _length += 4;
  }

  void writeInt32(int value) {
    _ensure(4);
    _view.setInt32(_length, value, Endian.big);
    _length += 4;
  }

  /// Writes a 64-bit value. VM-only: `setUint64` is unsupported on the web
  /// compilation targets, which RemoteLink does not ship to.
  void writeUint64(int value) {
    _ensure(8);
    _view.setUint64(_length, value, Endian.big);
    _length += 8;
  }

  void writeFloat32(double value) {
    _ensure(4);
    _view.setFloat32(_length, value, Endian.big);
    _length += 4;
  }

  void writeBool(bool value) => writeUint8(value ? 1 : 0);

  /// LEB128 unsigned varint. One byte for values below 128, which covers almost
  /// every length and enum in the protocol.
  void writeVarUint(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'varuint must be non-negative');
    }
    var remaining = value;
    while (remaining >= 0x80) {
      writeUint8((remaining & 0x7f) | 0x80);
      remaining >>= 7;
    }
    writeUint8(remaining);
  }

  /// Zig-zag encoded signed varint: small negatives stay one byte, which is the
  /// common case for mouse deltas and scroll ticks.
  void writeVarInt(int value) => writeVarUint((value << 1) ^ (value >> 63));

  void writeBytes(List<int> value) {
    _ensure(value.length);
    _buffer.setRange(_length, _length + value.length, value);
    _length += value.length;
  }

  /// Varint length prefix followed by raw bytes.
  void writeLengthPrefixedBytes(List<int> value) {
    writeVarUint(value.length);
    writeBytes(value);
  }

  /// Varint byte-length prefix followed by UTF-8. Note the prefix counts
  /// *bytes*, not code points, so multi-byte text round-trips exactly.
  void writeString(String value) =>
      writeLengthPrefixedBytes(utf8.encode(value));

  /// Writes an optional string as a presence byte plus the value.
  void writeOptionalString(String? value) {
    writeBool(value != null);
    if (value != null) writeString(value);
  }

  /// Overwrites 4 bytes at [offset]. Used to backfill a length prefix once the
  /// body has been written, avoiding a second pass or intermediate buffer.
  void patchUint32(int offset, int value) {
    if (offset < 0 || offset + 4 > _length) {
      throw RangeError('patch offset $offset out of range (length $_length)');
    }
    _view.setUint32(offset, value, Endian.big);
  }

  /// Zero-copy view of the written region.
  ///
  /// Valid only until the next write or [reset]. Use [toBytes] when the result
  /// must outlive this writer.
  Uint8List viewBytes() => Uint8List.view(_buffer.buffer, 0, _length);

  /// Independent copy of the written region.
  Uint8List toBytes() => Uint8List.fromList(viewBytes());

  /// Rewinds to empty, keeping the allocated capacity for reuse.
  void reset() => _length = 0;
}

/// Bounds-checked big-endian reader over a byte range.
///
/// Every read validates remaining length and throws [ProtocolError] rather than
/// [RangeError], so a malicious peer cannot produce an unhandled crash — the
/// session layer catches [ProtocolError] and closes the connection.
final class ByteReader {
  ByteReader(Uint8List bytes, {int? start, int? end})
      : _bytes = bytes,
        _start = start ?? 0,
        _end = end ?? bytes.length,
        _offset = start ?? 0 {
    if (_start < 0 || _end > bytes.length || _start > _end) {
      throw ArgumentError('invalid reader window [$_start, $_end)');
    }
    _view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  }

  final Uint8List _bytes;
  late final ByteData _view;
  final int _start;
  final int _end;
  int _offset;

  /// Absolute position of the read cursor.
  int get offset => _offset;

  /// The underlying buffer.
  ///
  /// Exposed solely so `Frame.readFrom` can re-checksum bytes it has already
  /// consumed. Nothing else should reach past the cursor abstraction — doing so
  /// bypasses every bounds check in this class.
  Uint8List get backingStore => _bytes;

  /// Bytes left before the end of the window.
  int get remaining => _end - _offset;

  bool get isAtEnd => _offset >= _end;

  void _need(int count, String what) {
    if (remaining < count) {
      throw ProtocolError(
        'short_read',
        'need $count bytes for $what, $remaining remaining',
      );
    }
  }

  int readUint8() {
    _need(1, 'uint8');
    return _view.getUint8(_offset++);
  }

  int readInt8() {
    _need(1, 'int8');
    return _view.getInt8(_offset++);
  }

  int readUint16() {
    _need(2, 'uint16');
    final value = _view.getUint16(_offset, Endian.big);
    _offset += 2;
    return value;
  }

  int readInt16() {
    _need(2, 'int16');
    final value = _view.getInt16(_offset, Endian.big);
    _offset += 2;
    return value;
  }

  int readUint32() {
    _need(4, 'uint32');
    final value = _view.getUint32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  int readInt32() {
    _need(4, 'int32');
    final value = _view.getInt32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  int readUint64() {
    _need(8, 'uint64');
    final value = _view.getUint64(_offset, Endian.big);
    _offset += 8;
    return value;
  }

  double readFloat32() {
    _need(4, 'float32');
    final value = _view.getFloat32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  bool readBool() => readUint8() != 0;

  /// LEB128 unsigned varint, capped at 10 groups so a hostile stream of
  /// continuation bytes cannot spin forever.
  int readVarUint() {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < 10; i++) {
      final byte = readUint8();
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
    }
    throw const ProtocolError('bad_varint', 'varint exceeds 64 bits');
  }

  int readVarInt() {
    final raw = readVarUint();
    return (raw >> 1) ^ -(raw & 1);
  }

  /// Copy of [count] bytes.
  Uint8List readBytes(int count) {
    _need(count, 'bytes[$count]');
    final result = Uint8List.sublistView(_bytes, _offset, _offset + count);
    _offset += count;
    return Uint8List.fromList(result);
  }

  /// Zero-copy view of [count] bytes. Valid only while the backing buffer is
  /// alive and unmodified — safe inside a decode call, unsafe to retain.
  Uint8List readBytesView(int count) {
    _need(count, 'bytesView[$count]');
    final result = Uint8List.sublistView(_bytes, _offset, _offset + count);
    _offset += count;
    return result;
  }

  Uint8List readLengthPrefixedBytes({int maxLength = 64 * 1024 * 1024}) {
    final length = readVarUint();
    if (length > maxLength) {
      throw ProtocolError(
        'length_limit',
        'declared length $length exceeds cap $maxLength',
      );
    }
    return readBytes(length);
  }

  String readString({int maxLength = 1024 * 1024}) {
    final bytes = readLengthPrefixedBytes(maxLength: maxLength);
    try {
      return utf8.decode(bytes);
    } on FormatException catch (e) {
      throw ProtocolError('bad_utf8', 'invalid UTF-8 in string field',
          cause: e);
    }
  }

  String? readOptionalString({int maxLength = 1024 * 1024}) =>
      readBool() ? readString(maxLength: maxLength) : null;

  /// Advances past [count] bytes without reading them, for forward
  /// compatibility with fields added by a newer peer.
  void skip(int count) {
    _need(count, 'skip($count)');
    _offset += count;
  }
}
