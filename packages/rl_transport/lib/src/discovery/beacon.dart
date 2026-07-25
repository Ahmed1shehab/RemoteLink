import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// UDP port RemoteLink discovery runs on.
///
/// In the IANA dynamic range, so no registration is needed and no well-known
/// service can collide with it.
const int kDiscoveryPort = 47810;

/// Default TCP port the desktop listens on.
const int kDefaultServicePort = 47811;

/// IPv4 multicast group for beacons.
///
/// Multicast rather than broadcast (`255.255.255.255`) for two practical
/// reasons: many consumer access points rate-limit or drop directed broadcast
/// while forwarding multicast fine, and multicast does not wake every device on
/// the subnet — which matters when the alternative is draining the battery of
/// every phone in the house every two seconds.
const String kMulticastGroupV4 = '239.255.78.10';

/// IPv6 link-local multicast group, for networks where IPv4 is unavailable.
const String kMulticastGroupV6 = 'ff02::78:10';

/// Magic prefix identifying a RemoteLink datagram.
///
/// Four bytes so an unrelated service that happens to use this port is
/// discarded in one comparison rather than being parsed.
const List<int> kBeaconMagic = <int>[0x52, 0x4C, 0x4E, 0x4B]; // "RLNK"

/// What a datagram is for.
enum BeaconKind {
  /// Server → network. "I am here." Sent periodically and on state change.
  announce(1),

  /// Client → network. "Who is there?" Prompts an immediate [announce] rather
  /// than waiting out the interval, which is what makes discovery feel instant
  /// when the user opens the app.
  query(2),

  /// Server → network. "I am going away." Lets clients remove the entry at once
  /// instead of waiting for it to time out.
  goodbye(3);

  const BeaconKind(this.wireValue);

  final int wireValue;

  static BeaconKind? fromWire(int value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// A discovery datagram.
///
/// ## Why a custom protocol rather than mDNS
///
/// mDNS/DNS-SD is the obvious choice and was the first design. It was rejected
/// for this milestone after weighing what it actually costs here:
///
/// * **Advertising needs native code.** Dart's `multicast_dns` can browse but
///   not publish, so the desktop would need Bonjour on macOS and either the
///   Bonjour service or a hand-written responder on Windows — native
///   dependencies on the exact platform where users are least likely to have
///   Bonjour installed.
/// * **The metadata would be encoded anyway.** Everything below would live in
///   DNS-SD TXT key-value pairs, so the parsing work is the same; only the
///   framing differs.
/// * **Latency is worse, not better.** mDNS query/response involves the
///   platform resolver's caching and backoff. A direct query datagram gets an
///   answer in one round trip, typically under 50 ms on a LAN.
///
/// What is genuinely lost is interoperability — no other Bonjour browser will
/// see a RemoteLink desktop — and that is acceptable for a closed protocol
/// where both endpoints ship together. `DiscoveryBackend` keeps the seam open
/// so a DNS-SD backend can be added later without touching anything above it.
///
/// The payload is plaintext by necessity: a device that has never paired must
/// be able to read it. It therefore contains nothing sensitive — a public key,
/// a name the user chose, and an address already visible in every packet
/// header. The `deviceId` is what a client matches against its trust store, and
/// because it is derived from the public key, a beacon cannot lie about it
/// without failing the handshake immediately afterwards.
@immutable
final class Beacon {
  const Beacon({
    required this.kind,
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.servicePort,
    required this.protocolVersion,
    required this.publicKeyFingerprint,
    required this.capabilities,
    this.acceptsNewPairings = true,
    this.activeSessions = 0,
  });

  final BeaconKind kind;
  final DeviceId deviceId;

  /// User-chosen display name.
  final String name;

  final PlatformKind platform;
  final int servicePort;
  final int protocolVersion;

  /// First 8 bytes of the device's static public key.
  ///
  /// Enough for a client to pre-filter its trust store before connecting, and
  /// short enough to keep the datagram inside one MTU. It is never used as an
  /// authentication input — the handshake proves the full key.
  final Uint8List publicKeyFingerprint;

  final Capabilities capabilities;

  /// Whether the desktop will entertain a new pairing right now. Lets the phone
  /// grey out a computer instead of offering a flow that will be refused.
  final bool acceptsNewPairings;

  final int activeSessions;

  /// Serialises to a datagram payload.
  Uint8List encode() {
    final writer = ByteWriter(initialCapacity: 128)
      ..writeBytes(kBeaconMagic)
      ..writeUint8(protocolVersion)
      ..writeUint8(kind.wireValue)
      ..writeString(deviceId.value)
      ..writeString(name)
      ..writeUint8(platform.wireValue)
      ..writeUint16(servicePort)
      ..writeLengthPrefixedBytes(publicKeyFingerprint)
      ..writeVarUint(capabilities.bits)
      ..writeBool(acceptsNewPairings)
      ..writeVarUint(activeSessions);
    return writer.toBytes();
  }

  /// Parses a datagram, returning `null` for anything that is not a valid
  /// beacon.
  ///
  /// Returns `null` rather than throwing throughout: this parses unauthenticated
  /// input from any host on the network, and a malformed or hostile datagram
  /// must cost one dropped packet, not an exception that could take down the
  /// discovery listener.
  static Beacon? tryParse(Uint8List datagram) {
    if (datagram.length < kBeaconMagic.length + 2) return null;
    for (var i = 0; i < kBeaconMagic.length; i++) {
      if (datagram[i] != kBeaconMagic[i]) return null;
    }

    try {
      final reader = ByteReader(datagram, start: kBeaconMagic.length);
      final protocolVersion = reader.readUint8();
      if (protocolVersion < kMinSupportedProtocolVersion ||
          protocolVersion > kProtocolVersion) {
        return null;
      }

      final kind = BeaconKind.fromWire(reader.readUint8());
      if (kind == null) return null;

      final deviceId = DeviceId.tryParse(reader.readString(maxLength: 64));
      if (deviceId == null) return null;

      final name = reader.readString(maxLength: 128);
      final platform = PlatformKind.fromWire(reader.readUint8());
      final servicePort = reader.readUint16();
      if (servicePort == 0) return null;

      final fingerprint = reader.readLengthPrefixedBytes(maxLength: 32);
      final capabilities = Capabilities(reader.readVarUint());
      final acceptsNewPairings = reader.readBool();
      final activeSessions = reader.readVarUint();

      return Beacon(
        kind: kind,
        deviceId: deviceId,
        name: name,
        platform: platform,
        servicePort: servicePort,
        protocolVersion: protocolVersion,
        publicKeyFingerprint: fingerprint,
        capabilities: capabilities,
        acceptsNewPairings: acceptsNewPairings,
        activeSessions: activeSessions,
      );
    } on ProtocolError {
      return null;
    }
  }

  @override
  String toString() =>
      'Beacon(${kind.name}, ${deviceId.short}, $name:$servicePort)';
}

/// A computer found on the network, with liveness bookkeeping.
@immutable
final class DiscoveredDevice {
  const DiscoveredDevice({
    required this.beacon,
    required this.address,
    required this.firstSeen,
    required this.lastSeen,
    this.isTrusted = false,
    this.roundTripMicros,
  });

  final Beacon beacon;

  /// Address the datagram came from. Used verbatim to connect, so a desktop
  /// with several interfaces is reached on the one that can actually see us.
  final String address;

  final DateTime firstSeen;
  final DateTime lastSeen;

  /// Whether this device's fingerprint matches something in the trust store.
  /// Drives ordering in the UI — known computers first.
  final bool isTrusted;

  /// Last measured round-trip time, once connected.
  final int? roundTripMicros;

  DeviceId get id => beacon.deviceId;
  String get name => beacon.name;
  int get port => beacon.servicePort;

  /// Whether this entry has gone stale and should disappear from the list.
  bool isStale(DateTime now, Duration timeout) =>
      now.difference(lastSeen) > timeout;

  DiscoveredDevice copyWith({
    Beacon? beacon,
    String? address,
    DateTime? lastSeen,
    bool? isTrusted,
    int? roundTripMicros,
  }) =>
      DiscoveredDevice(
        beacon: beacon ?? this.beacon,
        address: address ?? this.address,
        firstSeen: firstSeen,
        lastSeen: lastSeen ?? this.lastSeen,
        isTrusted: isTrusted ?? this.isTrusted,
        roundTripMicros: roundTripMicros ?? this.roundTripMicros,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiscoveredDevice && other.id == id && other.address == address);

  @override
  int get hashCode => Object.hash(id, address);

  @override
  String toString() => 'DiscoveredDevice($name @ $address:$port)';
}
