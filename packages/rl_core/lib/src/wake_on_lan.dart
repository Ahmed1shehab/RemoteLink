import 'dart:typed_data';

import 'mac_address.dart';

/// The port a magic packet is customarily sent to.
///
/// Nothing listens on it. Wake-on-LAN is handled by the network adapter itself,
/// which scans every inbound frame for the magic byte pattern regardless of
/// port — so 9 (the historic discard service) and 7 (echo) are equally correct
/// and 9 is the conventional choice. The host being woken is switched off, so
/// there is no socket to refuse the datagram either way.
const int kWakeOnLanPort = 9;

/// The all-ones IPv4 broadcast address.
const String kLimitedBroadcastAddress = '255.255.255.255';

/// Bytes of the magic packet that wakes [mac].
///
/// The format is fixed by AMD's original specification and is not negotiable:
/// six `0xFF` bytes, then the six-byte target address repeated sixteen times —
/// 102 bytes exactly. The adapter's wake filter looks for precisely this
/// sequence anywhere inside a frame, which is why the payload carries no
/// framing, length, or checksum of its own.
Uint8List buildMagicPacket(MacAddress mac) {
  final packet = Uint8List(6 + MacAddress.length * 16);
  packet.fillRange(0, 6, 0xff);
  final address = mac.bytes;
  for (var repeat = 0; repeat < 16; repeat++) {
    packet.setRange(
      6 + repeat * MacAddress.length,
      6 + (repeat + 1) * MacAddress.length,
      address,
    );
  }
  return packet;
}

/// The directed broadcast address of the subnet containing [ipv4Address], or
/// `null` if the input is not a dotted-quad IPv4 address.
///
/// [prefixLength] defaults to 24 because the phone genuinely cannot do better:
/// `NetworkInterface` exposes addresses but no netmask, so there is nothing to
/// derive a real prefix from. On the home and office LANs where Wake-on-LAN is
/// used, /24 is right nearly always — and when it is wrong the packet is merely
/// delivered to a smaller set of hosts than intended, which costs nothing,
/// because the limited broadcast is always sent alongside it.
String? directedBroadcastFor(String ipv4Address, {int prefixLength = 24}) {
  if (prefixLength < 1 || prefixLength > 31) return null;

  final parts = ipv4Address.trim().split('.');
  if (parts.length != 4) return null;

  var packed = 0;
  for (final part in parts) {
    // Rejecting non-digits explicitly: `int.tryParse` accepts a leading sign,
    // so `192.+168.1.1` would otherwise be read as a valid address.
    if (part.isEmpty || part.length > 3) return null;
    for (final unit in part.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return null;
    }
    final octet = int.parse(part);
    if (octet > 255) return null;
    packed = (packed << 8) | octet;
  }

  final hostMask = (1 << (32 - prefixLength)) - 1;
  final broadcast = packed | hostMask;
  return <int>[
    (broadcast >> 24) & 0xff,
    (broadcast >> 16) & 0xff,
    (broadcast >> 8) & 0xff,
    broadcast & 0xff,
  ].join('.');
}

/// Every address a magic packet for a host last seen at [lastKnownAddress]
/// should be sent to, in order, with no duplicates.
///
/// Both the limited broadcast and the subnet-directed broadcast are used, for
/// the same reason the discovery layer sends both multicast and broadcast:
/// consumer access points disagree about which they forward. Some drop
/// `255.255.255.255` as noise; some will not route a directed broadcast onto
/// the wired segment. Sending one and hoping is how a Wake button ends up
/// working on the author's network and nowhere else.
///
/// [localAddresses] are this device's own IPv4 addresses, included because the
/// phone may be on a subnet the stored address does not describe — for
/// instance after the computer moved to a new lease.
List<String> wakeTargetsFor({
  String? lastKnownAddress,
  Iterable<String> localAddresses = const <String>[],
}) {
  final targets = <String>[kLimitedBroadcastAddress];
  void add(String? candidate) {
    if (candidate == null || targets.contains(candidate)) return;
    targets.add(candidate);
  }

  if (lastKnownAddress != null) add(directedBroadcastFor(lastKnownAddress));
  for (final address in localAddresses) {
    add(directedBroadcastFor(address));
  }
  return List<String>.unmodifiable(targets);
}
