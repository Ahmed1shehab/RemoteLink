import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

/// A decoder frozen at the shape `MouseMoveAbsolute` had *before* `monitorId`
/// was appended.
///
/// Same reasoning as `device_info_compatibility_test.dart`: PROTOCOL.md §5
/// rule 2 promises appending is non-breaking because an older decoder reads the
/// fields it knows and stops, and the only way to check that rather than assume
/// it is to keep a copy of the older decoder and run it against bytes the
/// current encoder produced. A round trip through the *new* decoder would pass
/// just as happily if the field had been inserted before `displayIndex`.
///
/// Do not "modernise" this to call the real decoder.
({double x, double y, int displayIndex, int trailingBytes}) decodeAsV1(
  Uint8List payload,
) {
  final reader = ByteReader(payload);
  final x = reader.readFloat32();
  final y = reader.readFloat32();
  final displayIndex = reader.readVarUint();
  return (
    x: x,
    y: y,
    displayIndex: displayIndex,
    trailingBytes: reader.remaining,
  );
}

/// Encodes the way an older build would have: everything up to `displayIndex`,
/// and then nothing.
Uint8List encodeAsV1(MouseMoveAbsolute move) {
  final writer = ByteWriter()
    ..writeFloat32(move.x)
    ..writeFloat32(move.y)
    ..writeVarUint(move.displayIndex);
  return writer.toBytes();
}

Uint8List encode(MouseMoveAbsolute move) {
  final writer = ByteWriter();
  move.writeTo(writer);
  return writer.toBytes();
}

void main() {
  // A real CGDirectDisplayID, i.e. a value large enough to need a multi-byte
  // varint. A single-digit id would let a length mistake pass unnoticed.
  const displayId = 69733248;

  const addressed = MouseMoveAbsolute(x: 0.25, y: 0.75, monitorId: displayId);

  group('the appended monitor id field', () {
    test('round trips through the current decoder', () {
      final decoded = MouseMoveAbsolute.readFrom(ByteReader(encode(addressed)));
      expect(decoded.monitorId, displayId);
      expect(decoded.x, closeTo(0.25, 1e-6));
      expect(decoded.y, closeTo(0.75, 1e-6));
      expect(decoded.displayIndex, 0);
    });

    test('a decoder that does not know the field still reads every other one',
        () {
      // The guarantee the whole feature rests on: a phone or desktop running
      // the previous build must survive a peer that appends. An absolute move
      // is the worst message to get this wrong on — it is sent continuously,
      // so a short_read here would drop the session the moment a finger moved.
      final v1 = decodeAsV1(encode(addressed));

      expect(v1.x, closeTo(0.25, 1e-6));
      expect(v1.y, closeTo(0.75, 1e-6));
      expect(v1.displayIndex, 0);

      // And it stops with bytes to spare — proof the new field really is at the
      // end rather than having displaced something the old decoder read.
      expect(
        v1.trailingBytes,
        greaterThan(0),
        reason: 'the appended field must sit after everything v1 reads',
      );
    });

    test('an old peer that never sends the field addresses the whole desktop',
        () {
      // The mirror image. Reading the varint unconditionally would turn every
      // pre-RL-302 phone into a short_read on its first absolute move, and a
      // short_read on a *known* type closes the connection.
      const legacy = MouseMoveAbsolute(x: 0.5, y: 0.5, displayIndex: 3);

      final decoded =
          MouseMoveAbsolute.readFrom(ByteReader(encodeAsV1(legacy)));

      expect(decoded.monitorId, 0);
      expect(decoded.displayIndex, 3);
      expect(decoded.x, closeTo(0.5, 1e-6));
    });

    test('zero, not the primary monitor, is what an old peer means', () {
      // Deliberate: `monitorId == 0` maps across the virtual desktop, which is
      // exactly the behaviour every deployed build already gets. Redefining it
      // as "the primary monitor" would move where existing phones' taps land
      // without changing a single byte on the wire — the silent breakage the
      // append-only rule exists to prevent.
      expect(kWholeVirtualDesktopMonitorId, 0);
      final decoded = MouseMoveAbsolute.readFrom(
        ByteReader(encodeAsV1(const MouseMoveAbsolute(x: 0, y: 0))),
      );
      expect(decoded.monitorId, kWholeVirtualDesktopMonitorId);
    });

    test('the codec ignores the trailing bytes for a whole frame, too', () {
      // `MessageCodec.decode` is where "trailing bytes are not an error" is
      // enforced for real traffic, so it is exercised here and not only at the
      // message level.
      final codec = MessageCodec(clock: FakeClock());
      final frame = codec.encode(addressed);
      final decoded = codec.decode(Frame.readFrom(ByteReader(frame.encode())))
          as MouseMoveAbsolute;
      expect(decoded.monitorId, displayId);
    });

    test('costs one byte on a peer that names no monitor', () {
      // Absolute moves are sent continuously, so the cost of the field on the
      // common path has to be nearly nothing. A varint zero is one byte.
      const anywhere = MouseMoveAbsolute(x: 0.1, y: 0.2);
      expect(encode(anywhere).length, encodeAsV1(anywhere).length + 1);
    });

    test('a payload truncated mid-field is a short read, not a silent zero',
        () {
      // Trailing bytes that are *present but incomplete* are a corrupt stream,
      // not forward compatibility, and must not be mistaken for an absent
      // field. Continuation bit set with nothing following it.
      final truncated = Uint8List.fromList(<int>[
        ...encodeAsV1(const MouseMoveAbsolute(x: 0, y: 0)),
        0x80,
      ]);

      expect(
        () => MouseMoveAbsolute.readFrom(ByteReader(truncated)),
        throwsA(isA<ProtocolError>()),
      );
    });
  });
}
