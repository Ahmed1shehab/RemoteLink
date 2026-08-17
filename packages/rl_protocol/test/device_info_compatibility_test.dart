import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

/// A decoder frozen at the shape `DeviceInfoMessage` had *before* `macAddress`
/// was appended.
///
/// This is the whole point of the test file. `PROTOCOL.md` §5 rule 2 promises
/// that appending a field is non-breaking because an older decoder reads the
/// fields it knows and stops — and the only way to check that promise rather
/// than assume it is to keep a copy of the older decoder and run it against
/// bytes the current encoder produced. Asserting a round trip through the *new*
/// decoder would pass just as happily if the field had been inserted in the
/// middle, which is precisely the mistake the rule exists to prevent.
///
/// Do not "modernise" this to call the real decoder.
({
  DeviceId id,
  String name,
  PlatformKind platform,
  PeerRole role,
  String appVersion,
  String? model,
  int trailingBytes,
}) decodeAsV1(Uint8List payload) {
  final reader = ByteReader(payload);
  final id = DeviceId.tryParse(reader.readString(maxLength: 64))!;
  final name = reader.readString(maxLength: 128);
  final platform = PlatformKind.fromWire(reader.readUint8());
  final role = reader.readUint8() == 1 ? PeerRole.server : PeerRole.client;
  final appVersion = reader.readString(maxLength: 32);
  final model = reader.readOptionalString(maxLength: 128);
  return (
    id: id,
    name: name,
    platform: platform,
    role: role,
    appVersion: appVersion,
    model: model,
    trailingBytes: reader.remaining,
  );
}

/// Encodes a message the way an older build would have: everything up to
/// `model`, and then nothing.
Uint8List encodeAsV1(DeviceInfo info) {
  final writer = ByteWriter()
    ..writeString(info.id.value)
    ..writeString(info.name)
    ..writeUint8(info.platform.wireValue)
    ..writeUint8(info.role == PeerRole.server ? 1 : 2)
    ..writeString(info.appVersion)
    ..writeOptionalString(info.model);
  return writer.toBytes();
}

void main() {
  const id = DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123');
  final mac = MacAddress.tryParse('00:1A:2B:3C:4D:5E')!;

  final withMac = DeviceInfo(
    id: id,
    name: "Ahmed's MacBook Pro",
    platform: PlatformKind.macos,
    role: PeerRole.server,
    appVersion: '0.1.0',
    model: 'Mac16,7',
    macAddress: mac,
  );

  Uint8List encode(DeviceInfo info) {
    final writer = ByteWriter();
    DeviceInfoMessage(info).writeTo(writer);
    return writer.toBytes();
  }

  group('the appended MAC address field', () {
    test('round trips through the current decoder', () {
      final decoded =
          DeviceInfoMessage.readFrom(ByteReader(encode(withMac))).info;
      expect(decoded.macAddress, mac);
      expect(decoded.name, "Ahmed's MacBook Pro");
      expect(decoded.model, 'Mac16,7');
    });

    test('a decoder that does not know the field still reads every other one',
        () {
      // The compatibility guarantee this whole feature is built on: a phone or
      // desktop running the previous build must survive a peer that appends.
      final v1 = decodeAsV1(encode(withMac));

      expect(v1.id, id);
      expect(v1.name, "Ahmed's MacBook Pro");
      expect(v1.platform, PlatformKind.macos);
      expect(v1.role, PeerRole.server);
      expect(v1.appVersion, '0.1.0');
      expect(v1.model, 'Mac16,7');

      // And it stops with bytes to spare — proof the new field really is at the
      // end rather than having displaced something the old decoder read.
      expect(
        v1.trailingBytes,
        greaterThan(0),
        reason: 'the appended field must sit after everything v1 reads',
      );
    });

    test('the codec ignores the trailing bytes for a whole frame, too', () {
      // `MessageCodec.decode` is where the "trailing bytes are not an error"
      // rule is actually enforced for real traffic, so it is exercised here and
      // not only at the message level.
      final codec = MessageCodec(clock: FakeClock());
      final frame = codec.encode(DeviceInfoMessage(withMac));
      final decoded = codec.decode(Frame.readFrom(ByteReader(frame.encode())))
          as DeviceInfoMessage;
      expect(decoded.info.macAddress, mac);
    });

    test('a payload from an older peer decodes with a null address', () {
      // The mirror image: the *new* decoder must not demand the field. Reading
      // it unconditionally would turn every v1 device into a short_read and
      // drop the session on connect.
      const withoutMac = DeviceInfo(
        id: id,
        name: 'Old Desktop',
        platform: PlatformKind.windows,
        role: PeerRole.server,
        appVersion: '0.0.9',
        model: null,
      );

      final decoded =
          DeviceInfoMessage.readFrom(ByteReader(encodeAsV1(withoutMac))).info;

      expect(decoded.macAddress, isNull);
      expect(decoded.name, 'Old Desktop');
      expect(decoded.appVersion, '0.0.9');
      expect(decoded.model, isNull);
    });

    test('a peer that reports nonsense loses the field, not the session', () {
      // A malformed address is a peer bug or a hostile peer; either way the
      // session is fine and only the Wake button is lost.
      final writer = ByteWriter()
        ..writeString(id.value)
        ..writeString('Lying Desktop')
        ..writeUint8(PlatformKind.linux.wireValue)
        ..writeUint8(1)
        ..writeString('9.9.9')
        ..writeOptionalString(null)
        ..writeOptionalString('not-a-mac-address');

      final decoded =
          DeviceInfoMessage.readFrom(ByteReader(writer.toBytes())).info;

      expect(decoded.macAddress, isNull);
      expect(decoded.name, 'Lying Desktop');
    });

    test('an absent address is written as one presence byte', () {
      const withoutMac = DeviceInfo(
        id: id,
        name: 'Old Desktop',
        platform: PlatformKind.windows,
        role: PeerRole.server,
        appVersion: '0.0.9',
      );

      // Appending costs exactly one byte on peers with nothing to report, which
      // is what makes it acceptable on a message sent on every connect.
      expect(encode(withoutMac).length, encodeAsV1(withoutMac).length + 1);
    });
  });
}
