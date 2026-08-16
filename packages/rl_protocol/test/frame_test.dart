import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

Frame _sample({
  MessageType type = MessageType.mouseMove,
  FrameFlags flags = FrameFlags.none,
  int payloadLength = 8,
}) =>
    Frame(
      type: type,
      sequence: 42,
      timestampMicros: 1234567890,
      flags: flags,
      payload: Uint8List.fromList(
        List<int>.generate(payloadLength, (i) => i & 0xFF),
      ),
    );

void main() {
  group('Frame encoding', () {
    test('header is exactly 20 bytes', () {
      final frame = _sample(payloadLength: 0);
      expect(frame.encode().length, kFrameHeaderSize);
      expect(kFrameHeaderSize, 20);
    });

    test('fields land at their specified offsets', () {
      // Pins the wire layout. If this test changes, kProtocolVersion must too.
      final bytes = _sample(payloadLength: 3).encode();
      final view = ByteData.sublistView(bytes);

      expect(view.getUint8(0), kProtocolVersion, reason: 'version at 0');
      expect(view.getUint16(1), MessageType.mouseMove.code,
          reason: 'type at 1');
      expect(view.getUint32(3), 42, reason: 'sequence at 3');
      expect(view.getUint64(7), 1234567890, reason: 'timestamp at 7');
      expect(view.getUint8(15), 0, reason: 'flags at 15');
      expect(view.getUint32(16), 3, reason: 'payload length at 16');
    });

    test('round trips without a checksum', () {
      final original = _sample();
      final decoded = Frame.readFrom(ByteReader(original.encode()));

      expect(decoded.version, original.version);
      expect(decoded.type, original.type);
      expect(decoded.sequence, original.sequence);
      expect(decoded.timestampMicros, original.timestampMicros);
      expect(decoded.payload, original.payload);
    });

    test('round trips with a checksum and validates it', () {
      final original = _sample(
        flags: const FrameFlags(FrameFlags.hasChecksum),
        payloadLength: 64,
      );
      final encoded = original.encode();
      expect(encoded.length, kFrameHeaderSize + 64 + 4);

      final decoded = Frame.readFrom(ByteReader(encoded));
      expect(decoded.payload, original.payload);
      expect(decoded.flags.checksummed, isTrue);
    });

    test('a corrupted payload fails checksum verification', () {
      final encoded = _sample(
        flags: const FrameFlags(FrameFlags.hasChecksum),
        payloadLength: 64,
      ).encode();
      encoded[kFrameHeaderSize + 10] ^= 0xFF;

      expect(
        () => Frame.readFrom(ByteReader(encoded)),
        throwsA(
          isA<ProtocolError>().having(
            (e) => e.code,
            'code',
            'protocol.checksum_mismatch',
          ),
        ),
      );
    });

    test('several frames decode back to back from one buffer', () {
      final writer = ByteWriter();
      for (var i = 0; i < 5; i++) {
        Frame(
          type: MessageType.ping,
          sequence: i,
          timestampMicros: i * 1000,
          payload: Uint8List.fromList(<int>[i]),
        ).writeTo(writer);
      }

      final reader = ByteReader(writer.toBytes());
      for (var i = 0; i < 5; i++) {
        final frame = Frame.readFrom(reader);
        expect(frame.sequence, i);
        expect(frame.payload.single, i);
      }
      expect(reader.isAtEnd, isTrue);
    });
  });

  group('Frame decoding rejects hostile input', () {
    test('a declared length longer than the buffer is caught', () {
      final encoded = _sample(payloadLength: 4).encode();
      ByteData.sublistView(encoded).setUint32(16, 0xFFFF);

      expect(
        () => Frame.readFrom(ByteReader(encoded)),
        throwsA(
          isA<ProtocolError>().having(
            (e) => e.code,
            'code',
            'protocol.truncated_frame',
          ),
        ),
      );
    });

    test('a payload length above the cap is rejected before allocating', () {
      // The important property is that we never try to allocate 4 GiB just
      // because a peer said so.
      final encoded = _sample(payloadLength: 4).encode();
      ByteData.sublistView(encoded).setUint32(16, 0xFFFFFFFF);

      expect(
        () => Frame.readFrom(ByteReader(encoded)),
        throwsA(
          isA<ProtocolError>().having(
            (e) => e.code,
            'code',
            'protocol.payload_too_large',
          ),
        ),
      );
    });

    test('an unsupported version is rejected', () {
      final encoded = _sample().encode();
      encoded[0] = 99;

      expect(
        () => Frame.readFrom(ByteReader(encoded)),
        throwsA(
          isA<ProtocolError>().having(
            (e) => e.code,
            'code',
            'protocol.version_unsupported',
          ),
        ),
      );
    });

    test('an unknown message type decodes as unknown rather than throwing', () {
      // Forward compatibility: a v1 build must survive a v1.1 message.
      final encoded = _sample().encode();
      ByteData.sublistView(encoded).setUint16(1, 0x7FFF);

      final frame = Frame.readFrom(ByteReader(encoded));
      expect(frame.type, MessageType.unknown);
    });
  });

  group('MessageType', () {
    test('wire codes are unique', () {
      final codes = <int>{};
      for (final type in MessageType.values) {
        expect(codes.add(type.code), isTrue, reason: 'duplicate ${type.name}');
      }
    });

    test('unrecognised codes resolve to unknown', () {
      expect(MessageType.fromCode(0x7FFF), MessageType.unknown);
      expect(MessageType.fromCode(MessageType.ping.code), MessageType.ping);
    });

    test('only handshake messages are allowed before authentication', () {
      final allowed = MessageType.values
          .where((type) => type.allowedUnauthenticated)
          .toSet();

      expect(
        allowed,
        <MessageType>{
          MessageType.clientHello,
          MessageType.serverHello,
          MessageType.handshakeFinish,
          MessageType.resumeSession,
          MessageType.error,
          MessageType.close,
        },
        reason: 'widening this set widens the pre-auth attack surface',
      );
    });

    test('input and video are lossy, clipboard and files are not', () {
      expect(MessageType.mouseMove.isLossy, isTrue);
      expect(MessageType.screenFrame.isLossy, isTrue);
      expect(MessageType.clipboardUpdate.isLossy, isFalse);
      expect(MessageType.fileChunk.isLossy, isFalse);
      expect(MessageType.keyEvent.isLossy, isFalse);
    });
  });
}
