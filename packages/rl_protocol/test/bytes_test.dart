import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ByteWriter/ByteReader round trip', () {
    test('fixed-width integers preserve sign and magnitude', () {
      final writer = ByteWriter()
        ..writeUint8(255)
        ..writeInt8(-128)
        ..writeUint16(65535)
        ..writeInt16(-32768)
        ..writeUint32(4294967295)
        ..writeInt32(-2147483648)
        ..writeUint64(1 << 62);

      final reader = ByteReader(writer.toBytes());
      expect(reader.readUint8(), 255);
      expect(reader.readInt8(), -128);
      expect(reader.readUint16(), 65535);
      expect(reader.readInt16(), -32768);
      expect(reader.readUint32(), 4294967295);
      expect(reader.readInt32(), -2147483648);
      expect(reader.readUint64(), 1 << 62);
      expect(reader.isAtEnd, isTrue);
    });

    test('varuint uses the minimum number of bytes', () {
      expect((ByteWriter()..writeVarUint(0)).length, 1);
      expect((ByteWriter()..writeVarUint(127)).length, 1);
      expect((ByteWriter()..writeVarUint(128)).length, 2);
      expect((ByteWriter()..writeVarUint(16383)).length, 2);
      expect((ByteWriter()..writeVarUint(16384)).length, 3);
    });

    test('varuint round trips across byte-length boundaries', () {
      const values = <int>[0, 1, 127, 128, 300, 16383, 16384, 1 << 20, 1 << 40];
      final writer = ByteWriter();
      for (final value in values) {
        writer.writeVarUint(value);
      }
      final reader = ByteReader(writer.toBytes());
      for (final value in values) {
        expect(reader.readVarUint(), value);
      }
    });

    test('zig-zag varint keeps small negatives to one byte', () {
      // The whole point of zig-zag: a -3 mouse delta must not cost 10 bytes.
      expect((ByteWriter()..writeVarInt(-1)).length, 1);
      expect((ByteWriter()..writeVarInt(-63)).length, 1);
      expect((ByteWriter()..writeVarInt(63)).length, 1);

      const values = <int>[0, -1, 1, -64, 64, -1000, 1000, -70000, 70000];
      final writer = ByteWriter();
      for (final value in values) {
        writer.writeVarInt(value);
      }
      final reader = ByteReader(writer.toBytes());
      for (final value in values) {
        expect(reader.readVarInt(), value);
      }
    });

    test('strings round trip multi-byte UTF-8 exactly', () {
      const samples = <String>[
        '',
        'hello',
        'héllo wörld',
        '日本語',
        '👨‍👩‍👧‍👦'
      ];
      final writer = ByteWriter();
      for (final sample in samples) {
        writer.writeString(sample);
      }
      final reader = ByteReader(writer.toBytes());
      for (final sample in samples) {
        expect(reader.readString(), sample);
      }
    });

    test('optional strings distinguish null from empty', () {
      final writer = ByteWriter()
        ..writeOptionalString(null)
        ..writeOptionalString('');
      final reader = ByteReader(writer.toBytes());
      expect(reader.readOptionalString(), isNull);
      expect(reader.readOptionalString(), '');
    });

    test('patchUint32 backfills a length prefix', () {
      final writer = ByteWriter()..writeUint32(0);
      final placeholder = writer.length - 4;
      writer.writeBytes(<int>[1, 2, 3, 4, 5]);
      writer.patchUint32(placeholder, 5);

      final reader = ByteReader(writer.toBytes());
      expect(reader.readUint32(), 5);
      expect(reader.readBytes(5), <int>[1, 2, 3, 4, 5]);
    });

    test('writer grows past its initial capacity without corruption', () {
      final writer = ByteWriter(initialCapacity: 4);
      for (var i = 0; i < 1000; i++) {
        writer.writeUint16(i);
      }
      final reader = ByteReader(writer.toBytes());
      for (var i = 0; i < 1000; i++) {
        expect(reader.readUint16(), i);
      }
    });

    test('reset reuses the buffer and rewinds', () {
      final writer = ByteWriter()..writeUint32(0xDEADBEEF);
      expect(writer.length, 4);
      writer.reset();
      expect(writer.length, 0);
      writer.writeUint8(7);
      expect(writer.toBytes(), <int>[7]);
    });
  });

  group('ByteReader hostile input', () {
    test('reading past the end throws ProtocolError, not RangeError', () {
      // A malicious peer must never be able to produce an unhandled crash;
      // ProtocolError is caught by the session layer and closes the connection.
      final reader = ByteReader(Uint8List.fromList(<int>[1, 2]));
      expect(reader.readUint8(), 1);
      expect(() => reader.readUint32(), throwsA(isA<ProtocolError>()));
    });

    test('unterminated varint is rejected rather than looping', () {
      final continuation = Uint8List.fromList(List<int>.filled(12, 0x80));
      expect(
        () => ByteReader(continuation).readVarUint(),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('length-prefixed read honours its cap', () {
      final writer = ByteWriter()..writeVarUint(10 * 1024 * 1024);
      expect(
        () => ByteReader(writer.toBytes()).readLengthPrefixedBytes(
          maxLength: 1024,
        ),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('invalid UTF-8 in a string field is rejected', () {
      final writer = ByteWriter()
        ..writeVarUint(2)
        ..writeBytes(<int>[0xC3, 0x28]);
      expect(
        () => ByteReader(writer.toBytes()).readString(),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('windowed reader cannot see outside its bounds', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]);
      final reader = ByteReader(bytes, start: 2, end: 4);
      expect(reader.remaining, 2);
      expect(reader.readUint8(), 3);
      expect(reader.readUint8(), 4);
      expect(() => reader.readUint8(), throwsA(isA<ProtocolError>()));
    });
  });

  group('Crc32c', () {
    test('matches the standard check value for "123456789"', () {
      final input = Uint8List.fromList('123456789'.codeUnits);
      expect(Crc32c.compute(input), 0xE3069283);
    });

    test('empty input is zero', () {
      expect(Crc32c.compute(Uint8List(0)), 0);
    });

    test('detects a single-bit flip', () {
      final original = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final mutated = Uint8List.fromList(original)..[31] ^= 0x01;
      expect(Crc32c.compute(original), isNot(Crc32c.compute(mutated)));
    });

    test('incremental update equals one-shot compute', () {
      final data = Uint8List.fromList(List<int>.generate(100, (i) => i * 7));
      var crc = 0xFFFFFFFF;
      crc = Crc32c.update(crc, data, end: 40);
      crc = Crc32c.update(crc, data, start: 40);
      expect(crc ^ 0xFFFFFFFF, Crc32c.compute(data));
    });
  });
}
