import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

Uint8List encode(ScreenTopology topology) {
  final writer = ByteWriter();
  topology.writeTo(writer);
  return writer.toBytes();
}

ScreenTopology decode(Uint8List payload) =>
    ScreenTopology.readFrom(ByteReader(payload));

/// Writes one monitor entry by hand, so a test can put values on the wire that
/// the encoder would never produce.
void writeRawMonitor(
  ByteWriter writer, {
  required int id,
  int x = 0,
  int y = 0,
  int width = 1920,
  int height = 1080,
  double scaleFactor = 1.0,
  bool isPrimary = false,
  String name = 'Display 1',
}) {
  writer
    ..writeVarUint(id)
    ..writeVarInt(x)
    ..writeVarInt(y)
    ..writeVarUint(width)
    ..writeVarUint(height)
    ..writeFloat32(scaleFactor)
    ..writeUint8(isPrimary ? 1 : 0)
    ..writeString(name);
}

void main() {
  const topology = ScreenTopology(<MonitorDescriptor>[
    MonitorDescriptor(
      id: 69733248,
      x: 0,
      y: 0,
      width: 1920,
      height: 1080,
      name: 'Studio Display',
      isPrimary: true,
    ),
    MonitorDescriptor(
      id: 1,
      x: -1512,
      y: 98,
      width: 1512,
      height: 982,
      scaleFactor: 2.0,
      name: 'Built-in Display',
    ),
  ]);

  group('round trip', () {
    test('preserves every field, including negative origins', () {
      final decoded = decode(encode(topology));

      expect(decoded.monitors, hasLength(2));
      expect(decoded.monitors[0].id, 69733248);
      expect(decoded.monitors[0].isPrimary, isTrue);
      expect(decoded.monitors[0].name, 'Studio Display');

      // A monitor placed to the left of the primary has a negative origin, so
      // the field is zig-zag encoded. An unsigned varint here would have made
      // this a nonsense positive number and put the cursor on another planet.
      expect(decoded.monitors[1].x, -1512);
      expect(decoded.monitors[1].y, 98);
      expect(decoded.monitors[1].scaleFactor, 2.0);
      expect(decoded.monitors[1].isPrimary, isFalse);
    });

    test('survives a whole frame through the codec', () {
      final codec = MessageCodec(clock: FakeClock());
      final frame = codec.encode(topology);
      final decoded = codec.decode(Frame.readFrom(ByteReader(frame.encode())))
          as ScreenTopology;
      expect(decoded.monitors, hasLength(2));
      expect(decoded.monitors[1].name, 'Built-in Display');
    });

    test('an empty topology is legal', () {
      expect(
          decode(encode(const ScreenTopology(<MonitorDescriptor>[]))).monitors,
          isEmpty);
    });
  });

  group('hostile input', () {
    test('a declared count past the cap is refused before allocating', () {
      // Five bytes of varint can ask for four billion monitors. A decoder that
      // trusts the count and pre-sizes a list hands a peer an out-of-memory
      // kill for the price of a malformed packet.
      final writer = ByteWriter()..writeVarUint(0xFFFFFFF);

      expect(
        () => decode(writer.toBytes()),
        throwsA(
          isA<ProtocolError>()
              .having((e) => e.code, 'code', contains('length_limit')),
        ),
      );
    });

    test('a count larger than the entries present is a short read', () {
      // The count check passes, then the body runs out. This must be an error
      // rather than a partial topology, because a truncated payload means the
      // stream may be desynchronised.
      final writer = ByteWriter()..writeVarUint(4);
      writeRawMonitor(writer, id: 1);

      expect(() => decode(writer.toBytes()), throwsA(isA<ProtocolError>()));
    });

    test('a monitor claiming the reserved id is dropped', () {
      // Zero means "the whole virtual desktop" in `MouseMoveAbsolute`. A
      // monitor holding it could be shown in a picker and never addressed, so
      // it is better not to offer it at all.
      final writer = ByteWriter()..writeVarUint(2);
      writeRawMonitor(writer, id: 0, name: 'Ghost');
      writeRawMonitor(writer, id: 7, name: 'Real');

      final decoded = decode(writer.toBytes());
      expect(decoded.monitors, hasLength(1));
      expect(decoded.monitors.single.name, 'Real');
    });

    test('a name carrying an ANSI escape loses the name, not the monitor', () {
      // Monitor names are rendered in the phone UI and written to logs, exactly
      // like device names — one is display spoofing, the other is terminal
      // injection. `sanitiseDeviceName` is the one validator for both.
      final writer = ByteWriter()..writeVarUint(1);
      writeRawMonitor(writer, id: 9, name: '[31mDELL[0m');

      final decoded = decode(writer.toBytes());
      expect(decoded.monitors, hasLength(1));
      expect(decoded.monitors.single.name, 'Display 1');
      expect(decoded.monitors.single.id, 9,
          reason: 'the geometry is what makes the screen addressable');
    });

    test('a name carrying a bidi override is rejected too', () {
      final writer = ByteWriter()..writeVarUint(1);
      writeRawMonitor(writer, id: 9, name: 'Dell\u202E1yalpsiD');

      expect(decode(writer.toBytes()).monitors.single.name, 'Display 1');
    });

    test('a valid name is kept verbatim after NFC normalisation', () {
      final writer = ByteWriter()..writeVarUint(1);
      writeRawMonitor(writer, id: 9, name: 'Écran de bureau');

      expect(decode(writer.toBytes()).monitors.single.name, 'Écran de bureau');
    });

    test('a non-finite scale factor becomes 1.0', () {
      // float32 straight off the wire. NaN would propagate into every preview
      // size the phone computes and render nothing at all.
      final writer = ByteWriter()..writeVarUint(3);
      writeRawMonitor(writer, id: 1, scaleFactor: double.nan);
      writeRawMonitor(writer, id: 2, scaleFactor: double.infinity);
      writeRawMonitor(writer, id: 3, scaleFactor: -4.0);

      final decoded = decode(writer.toBytes());
      expect(decoded.monitors[0].scaleFactor, 1.0);
      expect(decoded.monitors[1].scaleFactor, 1.0);
      expect(decoded.monitors[2].scaleFactor, 0.1);
    });

    test('absurd dimensions are clamped rather than propagated', () {
      final writer = ByteWriter()..writeVarUint(1);
      writeRawMonitor(
        writer,
        id: 1,
        x: -999999999,
        width: 999999999,
        height: 999999999,
      );

      final monitor = decode(writer.toBytes()).monitors.single;
      expect(monitor.width, kMaxMonitorExtent);
      expect(monitor.height, kMaxMonitorExtent);
      expect(monitor.x, -kMaxMonitorExtent);
    });

    test('an over-long name is refused before it is allocated', () {
      final writer = ByteWriter()
        ..writeVarUint(1)
        ..writeVarUint(1)
        ..writeVarInt(0)
        ..writeVarInt(0)
        ..writeVarUint(100)
        ..writeVarUint(100)
        ..writeFloat32(1)
        ..writeUint8(0)
        // Declares a kilobyte of name in three bytes and supplies none of it.
        ..writeVarUint(1024);

      expect(() => decode(writer.toBytes()), throwsA(isA<ProtocolError>()));
    });

    test('trailing bytes after the last monitor are ignored', () {
      // A newer peer appending a field to the descriptor must not break this
      // build — the same §5 rule that applies to whole messages.
      final bytes = Uint8List.fromList(<int>[...encode(topology), 1, 2, 3, 4]);
      expect(decode(bytes).monitors, hasLength(2));
    });
  });

  group('the encoder', () {
    test('never writes more monitors than the decoder will accept', () {
      // Otherwise a host with a video wall would produce a payload its own peer
      // refuses, and the failure would look like a protocol bug rather than a
      // limit.
      final many = ScreenTopology(<MonitorDescriptor>[
        for (var i = 1; i <= kMaxMonitors + 5; i++)
          MonitorDescriptor(
            id: i,
            x: 0,
            y: 0,
            width: 800,
            height: 600,
            name: 'Display $i',
          ),
      ]);

      expect(decode(encode(many)).monitors, hasLength(kMaxMonitors));
    });
  });
}
