import 'package:rl_core/rl_core.dart';
import 'package:test/test.dart';

void main() {
  group('MacAddress.tryParse', () {
    test('accepts the spellings the two platforms actually produce', () {
      // The same address as macOS writes it, as Windows writes it, as a Cisco
      // switch writes it, and bare — all six bytes must come out identical, or
      // an address copied from one place will not match one read from another.
      const expected = <int>[0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E];
      for (final spelling in <String>[
        '00:1A:2B:3C:4D:5E',
        '00:1a:2b:3c:4d:5e',
        '00-1A-2B-3C-4D-5E',
        '001a.2b3c.4d5e',
        '001A2B3C4D5E',
        '  00:1A:2B:3C:4D:5E  ',
      ]) {
        final parsed = MacAddress.tryParse(spelling);
        expect(parsed, isNotNull, reason: 'should have parsed "$spelling"');
        expect(parsed!.bytes, expected, reason: 'wrong bytes for "$spelling"');
        expect(parsed.canonical, '00:1A:2B:3C:4D:5E');
      }
    });

    test('rejects malformed input rather than guessing', () {
      for (final malformed in <String>[
        '',
        '   ',
        'not a mac',
        '00:1A:2B:3C:4D', // five groups
        '00:1A:2B:3C:4D:5E:6F', // seven groups
        '00:1A:2B:3C:4D:5', // short final group
        '00:1A:2B:3C:4D:5EE', // long final group
        '00:1A:2B:3C:4D:GG', // not hex
        '00:1A:2B:3C:4D:-1',
        '00:1A-2B:3C:4D:5E', // mixed separators
        '001A2B3C4D5', // eleven digits
        '001A2B3C4D5E7', // thirteen digits
        '00:1A:2B', // three groups, but not the dotted form
        '001a.2b3c.4d5e.6f70', // four dotted groups
        '0x001A2B3C4D5E',
        '+0:1A:2B:3C:4D:5E',
      ]) {
        expect(
          MacAddress.tryParse(malformed),
          isNull,
          reason: 'should have rejected "$malformed"',
        );
      }
    });

    test('equality is by value, so a stored address matches a reported one',
        () {
      expect(
        MacAddress.tryParse('00-1a-2b-3c-4d-5e'),
        MacAddress.tryParse('00:1A:2B:3C:4D:5E'),
      );
      expect(
        MacAddress.tryParse('00:1A:2B:3C:4D:5E'),
        isNot(MacAddress.tryParse('00:1A:2B:3C:4D:5F')),
      );
    });

    test('rejects addresses that identify no machine', () {
      expect(MacAddress.tryParse('00:00:00:00:00:00')!.isWakeable, isFalse);
      expect(MacAddress.tryParse('FF:FF:FF:FF:FF:FF')!.isWakeable, isFalse);
      // Group bit set in the first octet: a multicast address.
      expect(MacAddress.tryParse('01:00:5E:00:00:FB')!.isWakeable, isFalse);
      expect(MacAddress.tryParse('00:1A:2B:3C:4D:5E')!.isWakeable, isTrue);
    });

    test('the byte list handed out cannot mutate the address', () {
      final mac = MacAddress.tryParse('00:1A:2B:3C:4D:5E')!;
      mac.bytes[0] = 0xff;
      expect(mac.canonical, '00:1A:2B:3C:4D:5E');
    });

    test('the raw constructor refuses anything that is not six bytes', () {
      expect(() => MacAddress(<int>[1, 2, 3]), throwsArgumentError);
      expect(
        () => MacAddress(<int>[1, 2, 3, 4, 5, 6, 7]),
        throwsArgumentError,
      );
      expect(() => MacAddress(<int>[1, 2, 3, 4, 5, 256]), throwsArgumentError);
    });
  });

  group('buildMagicPacket', () {
    test('is exactly six 0xFF bytes then the address sixteen times', () {
      final mac = MacAddress.tryParse('00:1A:2B:3C:4D:5E')!;
      final packet = buildMagicPacket(mac);

      // Asserted against a literal rather than against a re-derivation of the
      // same rule: a test that builds its expectation the way the code does
      // would agree with the code even when both are wrong, and the whole point
      // of this feature is that a NIC's wake filter matches this and nothing
      // else.
      expect(packet, <int>[
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, //
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
        0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
      ]);
      expect(packet, hasLength(102));
    });

    test('a different address changes only the repeated section', () {
      final packet = buildMagicPacket(MacAddress.tryParse('AABBCCDDEEFF')!);
      expect(packet.sublist(0, 6), <int>[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
      expect(packet.sublist(6, 12), <int>[0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]);
      expect(packet.sublist(96), <int>[0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]);
      expect(packet, hasLength(102));
    });
  });

  group('directedBroadcastFor', () {
    test('derives the /24 broadcast of a dotted quad', () {
      expect(directedBroadcastFor('192.168.1.42'), '192.168.1.255');
      expect(directedBroadcastFor('10.0.0.1'), '10.0.0.255');
      expect(directedBroadcastFor('172.16.31.200'), '172.16.31.255');
    });

    test('honours a non-default prefix', () {
      expect(
          directedBroadcastFor('10.1.2.3', prefixLength: 16), '10.1.255.255');
      expect(
          directedBroadcastFor('10.1.2.3', prefixLength: 8), '10.255.255.255');
      expect(
        directedBroadcastFor('192.168.1.42', prefixLength: 25),
        '192.168.1.127',
      );
    });

    test('returns null for anything that is not an IPv4 address', () {
      expect(directedBroadcastFor('192.168.1'), isNull);
      expect(directedBroadcastFor('192.168.1.256'), isNull);
      expect(directedBroadcastFor('192.168.1.1.1'), isNull);
      expect(directedBroadcastFor('192.168.1.'), isNull);
      expect(directedBroadcastFor('192.+168.1.1'), isNull);
      expect(directedBroadcastFor('fe80::1'), isNull);
      expect(directedBroadcastFor(''), isNull);
      expect(directedBroadcastFor('192.168.1.1', prefixLength: 32), isNull);
      expect(directedBroadcastFor('192.168.1.1', prefixLength: 0), isNull);
    });
  });

  group('wakeTargetsFor', () {
    test('always includes the limited broadcast, first', () {
      expect(wakeTargetsFor().first, '255.255.255.255');
      expect(wakeTargetsFor(), <String>['255.255.255.255']);
    });

    test('adds the directed broadcast of the stored address', () {
      expect(
        wakeTargetsFor(lastKnownAddress: '192.168.1.42'),
        <String>['255.255.255.255', '192.168.1.255'],
      );
    });

    test('adds this device\'s own subnets and never repeats one', () {
      expect(
        wakeTargetsFor(
          lastKnownAddress: '192.168.1.42',
          localAddresses: const <String>['192.168.1.90', '10.0.0.4'],
        ),
        <String>['255.255.255.255', '192.168.1.255', '10.0.0.255'],
      );
    });

    test('ignores addresses it cannot make sense of', () {
      expect(
        wakeTargetsFor(
          lastKnownAddress: 'office-mac.local',
          localAddresses: const <String>['fe80::1'],
        ),
        <String>['255.255.255.255'],
      );
    });
  });
}
