import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';
import 'package:test/test.dart';

/// The beacon parser reads unauthenticated UDP from any host on the network,
/// which makes it the most exposed decoder in the project — it runs before the
/// handshake, before pairing, before anything has proved who it is.
///
/// Its contract is that a malformed or hostile datagram costs one dropped
/// packet and never an exception, because an exception here takes down the
/// discovery listener for everyone.
void main() {
  Beacon sample({
    BeaconKind kind = BeaconKind.announce,
    String name = 'Ahmed\'s MacBook',
    int servicePort = 47810,
  }) =>
      Beacon(
        kind: kind,
        deviceId: const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123'),
        name: name,
        platform: PlatformKind.macos,
        servicePort: servicePort,
        protocolVersion: kProtocolVersion,
        publicKeyFingerprint: Uint8List.fromList(
          <int>[1, 2, 3, 4, 5, 6, 7, 8],
        ),
        capabilities: const Capabilities(Capabilities.mouse),
        activeSessions: 2,
      );

  group('Beacon round-trip', () {
    test('every field survives encode and parse', () {
      final original = sample();
      final parsed = Beacon.tryParse(original.encode());

      expect(parsed, isNotNull);
      expect(parsed!.kind, original.kind);
      expect(parsed.deviceId, original.deviceId);
      expect(parsed.name, original.name);
      expect(parsed.platform, original.platform);
      expect(parsed.servicePort, original.servicePort);
      expect(parsed.protocolVersion, original.protocolVersion);
      expect(parsed.publicKeyFingerprint, original.publicKeyFingerprint);
      expect(parsed.capabilities.bits, original.capabilities.bits);
      expect(parsed.acceptsNewPairings, original.acceptsNewPairings);
      expect(parsed.activeSessions, original.activeSessions);
    });

    test('each kind round-trips', () {
      for (final kind in BeaconKind.values) {
        final parsed = Beacon.tryParse(sample(kind: kind).encode());
        expect(parsed?.kind, kind, reason: 'kind ${kind.name} did not survive');
      }
    });

    test('a non-ASCII name survives', () {
      // Device names are user-chosen and routinely contain emoji or CJK.
      final parsed = Beacon.tryParse(sample(name: 'Ahmed の 💻').encode());
      expect(parsed?.name, 'Ahmed の 💻');
    });
  });

  group('hostile and malformed datagrams are dropped, never thrown', () {
    test('an empty datagram', () {
      expect(Beacon.tryParse(Uint8List(0)), isNull);
    });

    test('a datagram shorter than the magic', () {
      expect(Beacon.tryParse(Uint8List.fromList(<int>[0x52, 0x4C])), isNull);
    });

    test('an unrelated service on the same port', () {
      // The magic exists so a foreign datagram is discarded in one comparison
      // rather than being parsed. mDNS and SSDP traffic lands on shared ports
      // all the time.
      final foreign = Uint8List.fromList('HTTP/1.1 200 OK\r\n\r\n'.codeUnits);
      expect(Beacon.tryParse(foreign), isNull);
    });

    test('a datagram whose magic is one byte wrong', () {
      final bytes = sample().encode();
      bytes[3] = 0x00;
      expect(Beacon.tryParse(bytes), isNull);
    });

    test('truncation at every length is survivable', () {
      final full = sample().encode();

      // The interesting property is not that each prefix parses to null — some
      // may legitimately parse, since trailing fields are read last — but that
      // none of them throws. A throw here kills discovery for the whole app.
      for (var length = 0; length < full.length; length++) {
        final truncated = Uint8List.sublistView(full, 0, length);
        expect(
          () => Beacon.tryParse(truncated),
          returnsNormally,
          reason: 'truncating to $length bytes threw',
        );
      }
    });

    test('random noise carrying a valid magic does not throw', () {
      for (var seed = 0; seed < 256; seed++) {
        final noise = Uint8List(64);
        noise.setAll(0, kBeaconMagic);
        for (var i = kBeaconMagic.length; i < noise.length; i++) {
          noise[i] = (seed * 31 + i * 17) & 0xFF;
        }
        expect(
          () => Beacon.tryParse(noise),
          returnsNormally,
          reason: 'noise with seed $seed threw',
        );
      }
    });

    test('a port of zero is rejected', () {
      // Port 0 means "any port" to the OS and cannot be dialled, so a beacon
      // advertising it is either broken or probing.
      expect(Beacon.tryParse(sample(servicePort: 0).encode()), isNull);
    });

    test('an unsupported protocol version is rejected', () {
      final bytes = sample().encode();
      bytes[kBeaconMagic.length] = 0xFF;
      expect(Beacon.tryParse(bytes), isNull);
    });

    test('an unknown beacon kind is rejected', () {
      final bytes = sample().encode();
      bytes[kBeaconMagic.length + 1] = 0x7F;
      expect(Beacon.tryParse(bytes), isNull);
    });

    test('trailing bytes after a valid beacon are ignored', () {
      // Forward compatibility: a newer peer may append fields this build does
      // not know about, and PROTOCOL.md §5 requires that to remain parseable.
      final full = sample().encode();
      final padded = Uint8List(full.length + 16)..setAll(0, full);

      final parsed = Beacon.tryParse(padded);
      expect(parsed, isNotNull);
      expect(parsed!.deviceId, const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123'));
    });
  });

  group('the fingerprint is not a trust key', () {
    test('it is carried verbatim and is only eight bytes', () {
      final parsed = Beacon.tryParse(sample().encode());

      // SECURITY.md is explicit that this exists to pre-filter a device list
      // and nothing more: eight bytes is trivially forgeable, and treating it
      // as trust would accept anything able to produce a matching prefix.
      expect(parsed!.publicKeyFingerprint, hasLength(8));
    });

    test('two beacons may share a fingerprint and still be distinct devices',
        () {
      final a = Beacon.tryParse(sample().encode())!;
      final b = Beacon.tryParse(
        Beacon(
          kind: BeaconKind.announce,
          deviceId: const DeviceId('ZYXWVTSRQPNMKJHGFEDCBA9876'),
          name: 'Impostor',
          platform: PlatformKind.windows,
          servicePort: 47810,
          protocolVersion: kProtocolVersion,
          // Deliberately identical to the sample's.
          publicKeyFingerprint: Uint8List.fromList(
            <int>[1, 2, 3, 4, 5, 6, 7, 8],
          ),
          capabilities: const Capabilities(0),
        ).encode(),
      )!;

      expect(a.publicKeyFingerprint, b.publicKeyFingerprint);
      expect(
        a.deviceId,
        isNot(b.deviceId),
        reason: 'a colliding fingerprint must not make two devices the same '
            'device — identity comes from the handshake, not the beacon',
      );
    });
  });
}
