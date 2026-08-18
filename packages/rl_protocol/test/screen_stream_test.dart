import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

Uint8List encode(Message message) {
  final writer = ByteWriter();
  message.writeTo(writer);
  return writer.toBytes();
}

void main() {
  group('ScreenCodec', () {
    test('all known codecs resolve from wire and preserve value', () {
      for (final codec in ScreenCodec.values) {
        if (codec == ScreenCodec.unknown) continue;
        expect(ScreenCodec.fromWire(codec.wireValue), codec);
      }
    });

    test('unknown wire byte returns unknown codec without throwing', () {
      expect(ScreenCodec.fromWire(0), ScreenCodec.unknown);
      expect(ScreenCodec.fromWire(255), ScreenCodec.unknown);
      expect(ScreenCodec.fromWire(127), ScreenCodec.unknown);
    });
  });

  group('ScreenStopReason', () {
    test('all known reasons resolve from wire', () {
      for (final reason in ScreenStopReason.values) {
        if (reason == ScreenStopReason.unknown) continue;
        expect(ScreenStopReason.fromWire(reason.wireValue), reason);
      }
    });

    test('unknown wire byte returns unknown reason without throwing', () {
      expect(ScreenStopReason.fromWire(0), ScreenStopReason.unknown);
      expect(ScreenStopReason.fromWire(255), ScreenStopReason.unknown);
      expect(ScreenStopReason.fromWire(99), ScreenStopReason.unknown);
    });
  });

  group('ScreenStreamStart', () {
    const sample = ScreenStreamStart(
      monitorId: 69733248,
      codec: ScreenCodec.h264,
      targetFps: 60,
      targetBitrateKbps: 8000,
      maxWidth: 1920,
      maxHeight: 1080,
    );

    test('round-trip preserves every field', () {
      final decoded = ScreenStreamStart.readFrom(ByteReader(encode(sample)));
      expect(decoded.monitorId, 69733248);
      expect(decoded.codec, ScreenCodec.h264);
      expect(decoded.targetFps, 60);
      expect(decoded.targetBitrateKbps, 8000);
      expect(decoded.maxWidth, 1920);
      expect(decoded.maxHeight, 1080);
      expect(decoded.type, MessageType.screenStreamStart);
    });

    test('round-trip default / virtual desktop stream', () {
      const start = ScreenStreamStart(codec: ScreenCodec.jpeg);
      final decoded = ScreenStreamStart.readFrom(ByteReader(encode(start)));
      expect(decoded.monitorId, kWholeVirtualDesktopMonitorId);
      expect(decoded.codec, ScreenCodec.jpeg);
      expect(decoded.targetFps, 60);
      expect(decoded.targetBitrateKbps, 5000);
      expect(decoded.maxWidth, 0);
      expect(decoded.maxHeight, 0);
    });

    test('unknown codec byte decodes to ScreenCodec.unknown', () {
      final writer = ByteWriter()
        ..writeVarUint(1)
        ..writeUint8(0xFE) // Unrecognised codec
        ..writeVarUint(30)
        ..writeVarUint(4000)
        ..writeVarUint(1280)
        ..writeVarUint(720);

      final decoded = ScreenStreamStart.readFrom(ByteReader(writer.toBytes()));
      expect(decoded.codec, ScreenCodec.unknown);
      expect(decoded.targetFps, 30);
      expect(decoded.maxWidth, 1280);
    });

    test('clamping nonsense FPS, bitrate, and dimensions', () {
      final writer = ByteWriter()
        ..writeVarUint(1)
        ..writeUint8(ScreenCodec.h264.wireValue)
        ..writeVarUint(0) // 0 FPS
        ..writeVarUint(10) // 10 kbps
        ..writeVarUint(999999999) // absurd width
        ..writeVarUint(999999999); // absurd height

      final decoded = ScreenStreamStart.readFrom(ByteReader(writer.toBytes()));
      expect(decoded.targetFps, kMinFps);
      expect(decoded.targetBitrateKbps, kMinBitrateKbps);
      expect(decoded.maxWidth, kMaxMonitorExtent);
      expect(decoded.maxHeight, kMaxMonitorExtent);

      final writerOver = ByteWriter()
        ..writeVarUint(1)
        ..writeUint8(ScreenCodec.h264.wireValue)
        ..writeVarUint(1000) // 1000 FPS
        ..writeVarUint(500000000) // 500 Gbps
        ..writeVarUint(0)
        ..writeVarUint(0);

      final decodedOver =
          ScreenStreamStart.readFrom(ByteReader(writerOver.toBytes()));
      expect(decodedOver.targetFps, kMaxFps);
      expect(decodedOver.targetBitrateKbps, kMaxBitrateKbps);
    });

    test('trailing garbage is ignored', () {
      final valid = encode(sample);
      final padded =
          Uint8List.fromList(<int>[...valid, 0xDE, 0xAD, 0xBE, 0xEF]);
      final decoded = ScreenStreamStart.readFrom(ByteReader(padded));
      expect(decoded.monitorId, 69733248);
      expect(decoded.codec, ScreenCodec.h264);
    });

    test('truncation at every length throws ProtocolError', () {
      final valid = encode(sample);
      for (var i = 0; i < valid.length; i++) {
        final truncated = Uint8List.sublistView(valid, 0, i);
        expect(
          () => ScreenStreamStart.readFrom(ByteReader(truncated)),
          throwsA(isA<ProtocolError>()),
          reason:
              'truncation at length $i of ${valid.length} did not throw ProtocolError',
        );
      }
    });
  });

  group('ScreenStreamStop', () {
    test('round-trip default reason', () {
      const stop = ScreenStreamStop();
      final decoded = ScreenStreamStop.readFrom(ByteReader(encode(stop)));
      expect(decoded.reason, ScreenStopReason.userClosed);
      expect(decoded.type, MessageType.screenStreamStop);
    });

    test('round-trip explicit reasons', () {
      for (final reason in ScreenStopReason.values) {
        final stop = ScreenStreamStop(reason: reason);
        final decoded = ScreenStreamStop.readFrom(ByteReader(encode(stop)));
        expect(decoded.reason, reason);
      }
    });

    test('unknown reason byte decodes to ScreenStopReason.unknown', () {
      final writer = ByteWriter()..writeUint8(0xAB);
      final decoded = ScreenStreamStop.readFrom(ByteReader(writer.toBytes()));
      expect(decoded.reason, ScreenStopReason.unknown);
    });

    test('trailing garbage is ignored', () {
      const stop = ScreenStreamStop(reason: ScreenStopReason.decoderError);
      final valid = encode(stop);
      final padded = Uint8List.fromList(<int>[...valid, 1, 2, 3]);
      final decoded = ScreenStreamStop.readFrom(ByteReader(padded));
      expect(decoded.reason, ScreenStopReason.decoderError);
    });

    test('truncation at every length throws ProtocolError', () {
      final valid = encode(const ScreenStreamStop());
      for (var i = 0; i < valid.length; i++) {
        final truncated = Uint8List.sublistView(valid, 0, i);
        expect(
          () => ScreenStreamStop.readFrom(ByteReader(truncated)),
          throwsA(isA<ProtocolError>()),
          reason:
              'truncation at length $i of ${valid.length} did not throw ProtocolError',
        );
      }
    });
  });

  group('ScreenFrame', () {
    final frameData = Uint8List.fromList(
        <int>[0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1F]);
    final sample = ScreenFrame(
      sequence: 1234,
      ptsMicros: 1700000000000,
      isKeyframe: true,
      width: 1920,
      height: 1080,
      data: frameData,
    );

    test('round-trip preserves every field', () {
      final decoded = ScreenFrame.readFrom(ByteReader(encode(sample)));
      expect(decoded.sequence, 1234);
      expect(decoded.ptsMicros, 1700000000000);
      expect(decoded.isKeyframe, isTrue);
      expect(decoded.width, 1920);
      expect(decoded.height, 1080);
      expect(decoded.data, frameData);
      expect(decoded.type, MessageType.screenFrame);
    });

    test('carries the cursor position when the desk reported one', () {
      final withCursor = ScreenFrame(
        sequence: 7,
        ptsMicros: 1,
        isKeyframe: true,
        width: 1440,
        height: 900,
        data: frameData,
        cursorX: 0.25,
        cursorY: 0.75,
      );

      final decoded = ScreenFrame.readFrom(ByteReader(encode(withCursor)));
      // float32, so exact equality is the wrong assertion — a quarter and
      // three quarters happen to be exact, but nothing else would be.
      expect(decoded.cursorX, closeTo(0.25, 1e-6));
      expect(decoded.cursorY, closeTo(0.75, 1e-6));
    });

    test('says nothing about the cursor when it is on another display', () {
      final decoded = ScreenFrame.readFrom(ByteReader(encode(sample)));
      expect(decoded.cursorX, isNull);
      expect(decoded.cursorY, isNull);
    });

    test('reads a frame from a peer built before the cursor existed', () {
      // §5 rule 2, from the other side: this is the exact payload an older
      // desktop writes — five fields and then nothing. It must decode as "no
      // cursor" rather than throwing on a short read, or a version mismatch
      // turns into a dead stream instead of a missing pointer.
      final writer = ByteWriter()
        ..writeVarUint(9)
        ..writeUint64(4242)
        ..writeBool(true)
        ..writeVarUint(1280)
        ..writeVarUint(720)
        ..writeLengthPrefixedBytes(frameData);

      final decoded = ScreenFrame.readFrom(ByteReader(writer.toBytes()));
      expect(decoded.sequence, 9);
      expect(decoded.width, 1280);
      expect(decoded.data, frameData);
      expect(decoded.cursorX, isNull);
      expect(decoded.cursorY, isNull);
    });

    test('refuses a cursor position that is not on the frame', () {
      // A peer can put anything in a float32, and these values would each
      // propagate straight into a layout calculation on the phone: NaN poisons
      // every arithmetic it touches, and an out-of-range value would draw a
      // pointer outside the picture or clamped to an edge it is not on.
      for (final pair in <List<double>>[
        <double>[double.nan, 0.5],
        <double>[0.5, double.nan],
        <double>[double.infinity, 0.5],
        <double>[-0.5, 0.5],
        <double>[0.5, 1.5],
      ]) {
        final writer = ByteWriter()
          ..writeVarUint(1)
          ..writeUint64(1)
          ..writeBool(true)
          ..writeVarUint(100)
          ..writeVarUint(100)
          ..writeLengthPrefixedBytes(frameData)
          ..writeBool(true)
          ..writeFloat32(pair[0])
          ..writeFloat32(pair[1]);

        final decoded = ScreenFrame.readFrom(ByteReader(writer.toBytes()));
        expect(
          decoded.cursorX,
          isNull,
          reason: 'accepted a cursor at ${pair[0]},${pair[1]}',
        );
        expect(decoded.cursorY, isNull);
      }
    });

    test('the corners of the frame are valid cursor positions', () {
      // The boundary the check above rejects past. A pointer parked in a corner
      // is ordinary, and rejecting it would make the cursor vanish there.
      for (final corner in <List<double>>[
        <double>[0, 0],
        <double>[1, 1],
        <double>[0, 1],
        <double>[1, 0],
      ]) {
        final frame = ScreenFrame(
          sequence: 1,
          ptsMicros: 1,
          isKeyframe: true,
          width: 100,
          height: 100,
          data: frameData,
          cursorX: corner[0],
          cursorY: corner[1],
        );
        final decoded = ScreenFrame.readFrom(ByteReader(encode(frame)));
        expect(decoded.cursorX, corner[0]);
        expect(decoded.cursorY, corner[1]);
      }
    });

    test('delta frame round-trip', () {
      final delta = ScreenFrame(
        sequence: 1235,
        ptsMicros: 1700000016666,
        isKeyframe: false,
        width: 1920,
        height: 1080,
        data: Uint8List.fromList(<int>[0x00, 0x00, 0x01, 0x41]),
      );
      final decoded = ScreenFrame.readFrom(ByteReader(encode(delta)));
      expect(decoded.sequence, 1235);
      expect(decoded.isKeyframe, isFalse);
      expect(decoded.data, <int>[0x00, 0x00, 0x01, 0x41]);
    });

    test('dimensions are clamped to kMaxMonitorExtent', () {
      final writer = ByteWriter()
        ..writeVarUint(1)
        ..writeUint64(1000)
        ..writeBool(true)
        ..writeVarUint(999999999)
        ..writeVarUint(999999999)
        ..writeLengthPrefixedBytes(<int>[1, 2, 3]);

      final decoded = ScreenFrame.readFrom(ByteReader(writer.toBytes()));
      expect(decoded.width, kMaxMonitorExtent);
      expect(decoded.height, kMaxMonitorExtent);
    });

    test('payload exceeding kMaxScreenFrameBytes is refused before allocating',
        () {
      final writer = ByteWriter()
        ..writeVarUint(1)
        ..writeUint64(1000)
        ..writeBool(true)
        ..writeVarUint(1920)
        ..writeVarUint(1080)
        // Varuint declaring 32 MiB of frame data (cap is 16 MiB).
        ..writeVarUint(32 * 1024 * 1024);

      expect(
        () => ScreenFrame.readFrom(ByteReader(writer.toBytes())),
        throwsA(
          isA<ProtocolError>()
              .having((e) => e.code, 'code', contains('length_limit')),
        ),
      );
    });

    test('declared payload larger than bytes present fails without allocating',
        () {
      final writer = ByteWriter()
        ..writeVarUint(1)
        ..writeUint64(1000)
        ..writeBool(true)
        ..writeVarUint(1920)
        ..writeVarUint(1080)
        // Declares 1 MiB in 3 bytes, provides 0 bytes.
        ..writeVarUint(1024 * 1024);

      expect(
        () => ScreenFrame.readFrom(ByteReader(writer.toBytes())),
        throwsA(
          isA<ProtocolError>()
              .having((e) => e.code, 'code', contains('short_read')),
        ),
      );
    });

    test('trailing garbage is ignored', () {
      final valid = encode(sample);
      final padded =
          Uint8List.fromList(<int>[...valid, 0x11, 0x22, 0x33, 0x44]);
      final decoded = ScreenFrame.readFrom(ByteReader(padded));
      expect(decoded.sequence, 1234);
      expect(decoded.data, frameData);
    });

    test('truncation inside the required fields throws ProtocolError', () {
      // The cursor is an appended field, so the payload now ends with a
      // presence byte that a decoder is allowed not to find — §5 rule 2 makes
      // "the appended tail is missing" indistinguishable from "the peer that
      // sent this predates the field", and a decoder cannot treat one as an
      // error without treating the other as one too.
      //
      // Everything before that tail is still required, and this is where the
      // boundary is checked. `sample` carries no cursor, so its encoding is the
      // required prefix plus one presence byte.
      final valid = encode(sample);
      final requiredLength = valid.length - 1;

      for (var i = 0; i < requiredLength; i++) {
        final truncated = Uint8List.sublistView(valid, 0, i);
        expect(
          () => ScreenFrame.readFrom(ByteReader(truncated)),
          throwsA(isA<ProtocolError>()),
          reason:
              'truncation at length $i of ${valid.length} did not throw ProtocolError',
        );
      }
    });

    test('truncation inside the cursor fields throws ProtocolError', () {
      // The tail is optional as a whole, not field by field. A payload that
      // claims a cursor and then stops halfway through it is malformed, and
      // reading past the end would be the short-read the decoder exists to
      // reject.
      final withCursor = ScreenFrame(
        sequence: 3,
        ptsMicros: 5,
        isKeyframe: true,
        width: 800,
        height: 600,
        data: frameData,
        cursorX: 0.5,
        cursorY: 0.5,
      );
      final valid = encode(withCursor);

      // The presence byte plus two float32s.
      const cursorBytes = 1 + 4 + 4;
      for (var i = valid.length - cursorBytes + 1; i < valid.length; i++) {
        expect(
          () => ScreenFrame.readFrom(
            ByteReader(Uint8List.sublistView(valid, 0, i)),
          ),
          throwsA(isA<ProtocolError>()),
          reason: 'a half-written cursor at length $i decoded without error',
        );
      }
    });

    test('data is defensively copied', () {
      final mutableList = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final frame = ScreenFrame(
        sequence: 1,
        ptsMicros: 0,
        isKeyframe: true,
        width: 100,
        height: 100,
        data: mutableList,
      );
      mutableList[0] = 99;
      expect(frame.data[0], 1);
    });
  });

  group('ScreenConfigure', () {
    const full = ScreenConfigure(
      targetFps: 30,
      targetBitrateKbps: 2500,
      maxWidth: 1280,
      maxHeight: 720,
      monitorId: 2,
    );

    test('round-trip with all fields present', () {
      final decoded = ScreenConfigure.readFrom(ByteReader(encode(full)));
      expect(decoded.targetFps, 30);
      expect(decoded.targetBitrateKbps, 2500);
      expect(decoded.maxWidth, 1280);
      expect(decoded.maxHeight, 720);
      expect(decoded.monitorId, 2);
      expect(decoded.type, MessageType.screenConfigure);
    });

    test('round-trip with all fields absent', () {
      const empty = ScreenConfigure();
      final decoded = ScreenConfigure.readFrom(ByteReader(encode(empty)));
      expect(decoded.targetFps, isNull);
      expect(decoded.targetBitrateKbps, isNull);
      expect(decoded.maxWidth, isNull);
      expect(decoded.maxHeight, isNull);
      expect(decoded.monitorId, isNull);
    });

    test('round-trip with partial fields', () {
      const partial = ScreenConfigure(targetBitrateKbps: 3000);
      final decoded = ScreenConfigure.readFrom(ByteReader(encode(partial)));
      expect(decoded.targetFps, isNull);
      expect(decoded.targetBitrateKbps, 3000);
      expect(decoded.maxWidth, isNull);
      expect(decoded.maxHeight, isNull);
      expect(decoded.monitorId, isNull);
    });

    test('clamping on present fields', () {
      final writer = ByteWriter()
        ..writeBool(true)
        ..writeVarUint(0) // 0 FPS -> clamps to kMinFps
        ..writeBool(true)
        ..writeVarUint(10) // 10 kbps -> clamps to kMinBitrateKbps
        ..writeBool(true)
        ..writeVarUint(999999999) // clamps to kMaxMonitorExtent
        ..writeBool(true)
        ..writeVarUint(999999999) // clamps to kMaxMonitorExtent
        ..writeBool(false);

      final decoded = ScreenConfigure.readFrom(ByteReader(writer.toBytes()));
      expect(decoded.targetFps, kMinFps);
      expect(decoded.targetBitrateKbps, kMinBitrateKbps);
      expect(decoded.maxWidth, kMaxMonitorExtent);
      expect(decoded.maxHeight, kMaxMonitorExtent);
      expect(decoded.monitorId, isNull);
    });

    test('trailing garbage is ignored', () {
      final valid = encode(full);
      final padded = Uint8List.fromList(<int>[...valid, 9, 8, 7]);
      final decoded = ScreenConfigure.readFrom(ByteReader(padded));
      expect(decoded.targetFps, 30);
      expect(decoded.targetBitrateKbps, 2500);
    });

    test('truncation at every length throws ProtocolError for full config', () {
      final valid = encode(full);
      for (var i = 0; i < valid.length; i++) {
        final truncated = Uint8List.sublistView(valid, 0, i);
        expect(
          () => ScreenConfigure.readFrom(ByteReader(truncated)),
          throwsA(isA<ProtocolError>()),
          reason:
              'truncation at length $i of ${valid.length} did not throw ProtocolError',
        );
      }
    });

    test('truncation at every length throws ProtocolError for empty config',
        () {
      final valid = encode(const ScreenConfigure());
      for (var i = 0; i < valid.length; i++) {
        final truncated = Uint8List.sublistView(valid, 0, i);
        expect(
          () => ScreenConfigure.readFrom(ByteReader(truncated)),
          throwsA(isA<ProtocolError>()),
          reason:
              'truncation at length $i of ${valid.length} did not throw ProtocolError',
        );
      }
    });
  });

  group('frozen wire compatibility', () {
    // FROZEN WIRE BYTES — DO NOT REGENERATE.
    // These hard-coded byte arrays represent the exact wire encoding of each
    // screen streaming message as shipped. If an encoder modification changes
    // field order or encoding, these tests fail to ensure forward and backward
    // compatibility across versions.

    test('ScreenStreamStart frozen wire bytes decode correctly', () {
      // ScreenStreamStart(
      //   monitorId: 69733248,
      //   codec: ScreenCodec.h264 (1),
      //   targetFps: 60,
      //   targetBitrateKbps: 5000,
      //   maxWidth: 1920,
      //   maxHeight: 1080,
      // )
      final frozenBytes = Uint8List.fromList(<int>[
        0x80, 0x97, 0xa0, 0x21, // monitorId: 69733248 (varuint)
        0x01, // codec: h264 (uint8)
        0x3c, // targetFps: 60 (varuint)
        0x88, 0x27, // targetBitrateKbps: 5000 (varuint)
        0x80, 0x0f, // maxWidth: 1920 (varuint)
        0xb8, 0x08, // maxHeight: 1080 (varuint)
      ]);

      final decoded = ScreenStreamStart.readFrom(ByteReader(frozenBytes));
      expect(decoded.monitorId, 69733248);
      expect(decoded.codec, ScreenCodec.h264);
      expect(decoded.targetFps, 60);
      expect(decoded.targetBitrateKbps, 5000);
      expect(decoded.maxWidth, 1920);
      expect(decoded.maxHeight, 1080);
    });

    test('ScreenStreamStop frozen wire bytes decode correctly', () {
      // ScreenStreamStop(reason: ScreenStopReason.decoderError (2))
      final frozenBytes = Uint8List.fromList(<int>[
        0x02, // reason: decoderError (uint8)
      ]);

      final decoded = ScreenStreamStop.readFrom(ByteReader(frozenBytes));
      expect(decoded.reason, ScreenStopReason.decoderError);
    });

    test('ScreenFrame frozen wire bytes decode correctly', () {
      // ScreenFrame(
      //   sequence: 42,
      //   ptsMicros: 1000000, // 0x00000000000F4240
      //   isKeyframe: true,
      //   width: 1920,
      //   height: 1080,
      //   data: [0x00, 0x00, 0x00, 0x01],
      // )
      final frozenBytes = Uint8List.fromList(<int>[
        0x2a, // sequence: 42 (varuint)
        0x00, 0x00, 0x00, 0x00, 0x00, 0x0f, 0x42,
        0x40, // ptsMicros: 1000000 (uint64)
        0x01, // isKeyframe: true (bool)
        0x80, 0x0f, // width: 1920 (varuint)
        0xb8, 0x08, // height: 1080 (varuint)
        0x04, // data length: 4 (varuint)
        0x00, 0x00, 0x00, 0x01, // data bytes
      ]);

      final decoded = ScreenFrame.readFrom(ByteReader(frozenBytes));
      expect(decoded.sequence, 42);
      expect(decoded.ptsMicros, 1000000);
      expect(decoded.isKeyframe, isTrue);
      expect(decoded.width, 1920);
      expect(decoded.height, 1080);
      expect(decoded.data, <int>[0x00, 0x00, 0x00, 0x01]);
    });

    test('ScreenConfigure frozen wire bytes decode correctly', () {
      // ScreenConfigure(
      //   targetFps: 30,
      //   targetBitrateKbps: 2500,
      //   maxWidth: null,
      //   maxHeight: null,
      //   monitorId: 1,
      // )
      final frozenBytes = Uint8List.fromList(<int>[
        0x01, 0x1e, // hasFps: true, targetFps: 30 (varuint)
        0x01, 0xc4, 0x13, // hasBitrate: true, targetBitrateKbps: 2500 (varuint)
        0x00, // hasMaxWidth: false
        0x00, // hasMaxHeight: false
        0x01, 0x01, // hasMonitorId: true, monitorId: 1 (varuint)
      ]);

      final decoded = ScreenConfigure.readFrom(ByteReader(frozenBytes));
      expect(decoded.targetFps, 30);
      expect(decoded.targetBitrateKbps, 2500);
      expect(decoded.maxWidth, isNull);
      expect(decoded.maxHeight, isNull);
      expect(decoded.monitorId, 1);
    });
  });

  group('ScreenCursor', () {
    test('round trips a position on screen', () {
      const sample = ScreenCursor(monitorId: 69733248, x: 0.25, y: 0.75);
      final decoded = ScreenCursor.readFrom(ByteReader(encode(sample)));

      expect(decoded.monitorId, 69733248);
      expect(decoded.x, closeTo(0.25, 1e-6));
      expect(decoded.y, closeTo(0.75, 1e-6));
      expect(decoded.isOnScreen, isTrue);
      expect(decoded.type, MessageType.screenCursor);
    });

    test('round trips a pointer that has left the display', () {
      // A real state, and one that has to be *sent* rather than merely not
      // sent: it is how the viewer learns to stop drawing an arrow that is no
      // longer there. Left at its last position it would sit frozen against an
      // edge, which reads as the stream having hung.
      const sample = ScreenCursor(monitorId: 4);
      final decoded = ScreenCursor.readFrom(ByteReader(encode(sample)));

      expect(decoded.monitorId, 4);
      expect(decoded.isOnScreen, isFalse);
      expect(decoded.x, isNull);
      expect(decoded.y, isNull);
    });

    test('is far smaller than the frame it used to travel on', () {
      // The entire reason this message exists. Measured on a real desk, a
      // frame at the default quality is 213,622 bytes; a pointer moving across
      // a still desktop used to cost one of those per position.
      const sample = ScreenCursor(monitorId: 1, x: 0.5, y: 0.5);
      expect(
        encode(sample).length,
        lessThan(32),
        reason: 'a cursor update must stay cheap enough to send at 60 Hz',
      );
    });

    test('a position outside the picture is dropped, not clamped', () {
      // Clamping would pin the arrow to an edge it is not on, which looks like
      // a stuck cursor rather than an absent one.
      final writer = ByteWriter()
        ..writeVarUint(1)
        ..writeBool(true)
        ..writeFloat32(1.4)
        ..writeFloat32(0.5);
      final decoded = ScreenCursor.readFrom(ByteReader(writer.toBytes()));

      expect(decoded.isOnScreen, isFalse);
    });

    test('a non-finite position is dropped rather than drawn', () {
      final writer = ByteWriter()
        ..writeVarUint(1)
        ..writeBool(true)
        ..writeFloat32(double.nan)
        ..writeFloat32(0.5);
      final decoded = ScreenCursor.readFrom(ByteReader(writer.toBytes()));

      expect(decoded.isOnScreen, isFalse);
    });

    test('is lossy, so a stale position never delays a fresh one', () {
      // Only the newest position means anything. Queued rather than coalesced,
      // a burst of movement would replay the whole path late.
      expect(MessageType.screenCursor.isLossy, isTrue);
    });

    test('is gated with the rest of the stream, not below it', () {
      // Where the pointer is is information about the screen. A tier refused
      // the picture must not be handed a live readout of what the user is
      // pointing at instead.
      for (final tier in PermissionTier.values) {
        expect(
          tier.allows(MessageType.screenCursor),
          tier.allows(MessageType.screenFrame),
          reason: '${tier.name} treats the cursor and the picture differently',
        );
      }
    });
  });
}
