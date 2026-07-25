import 'package:meta/meta.dart';

/// Which side of the connection a process is on.
enum PeerRole {
  /// Desktop companion. Listens, owns the input/clipboard/screen backends.
  server,

  /// Phone or tablet. Initiates connections and sends commands.
  client,
}

/// Operating system of a peer. Sent during the handshake so each side can
/// adapt: modifier naming (Ctrl vs Cmd), path separators, media key semantics.
enum PlatformKind {
  windows,
  macos,
  linux,
  android,
  ios,
  unknown;

  static PlatformKind fromWire(int value) => switch (value) {
        1 => PlatformKind.windows,
        2 => PlatformKind.macos,
        3 => PlatformKind.linux,
        4 => PlatformKind.android,
        5 => PlatformKind.ios,
        _ => PlatformKind.unknown,
      };

  int get wireValue => switch (this) {
        PlatformKind.windows => 1,
        PlatformKind.macos => 2,
        PlatformKind.linux => 3,
        PlatformKind.android => 4,
        PlatformKind.ios => 5,
        PlatformKind.unknown => 0,
      };

  /// True when the platform uses Command rather than Control as the primary
  /// shortcut modifier. Drives modifier remapping on the desktop side.
  bool get usesCommandModifier => this == PlatformKind.macos;
}

/// Stable identity of a peer, derived from its long-term X25519 public key.
///
/// The ID is `SHA-256(staticPublicKey)` rendered as 26 Crockford base32
/// characters (130 bits). It is deliberately derived rather than random: a peer
/// cannot claim an ID it does not hold the private key for, so the trust store
/// can key on the ID alone without a separate binding step.
@immutable
final class DeviceId {
  const DeviceId(this.value);

  /// 26-character Crockford base32 string, uppercase, no separators.
  final String value;

  static const int length = 26;
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Encodes the first 130 bits of [digest] (a SHA-256 of the static public
  /// key) as Crockford base32.
  factory DeviceId.fromDigest(List<int> digest) {
    if (digest.length < 17) {
      throw ArgumentError.value(
        digest.length,
        'digest',
        'need at least 17 bytes to derive a 130-bit id',
      );
    }
    final buffer = StringBuffer();
    var accumulator = 0;
    var bits = 0;
    for (var i = 0; buffer.length < length; i++) {
      accumulator = (accumulator << 8) | digest[i];
      bits += 8;
      while (bits >= 5 && buffer.length < length) {
        bits -= 5;
        buffer.write(_alphabet[(accumulator >> bits) & 0x1f]);
      }
    }
    return DeviceId(buffer.toString());
  }

  /// Validates and normalises user- or wire-supplied text.
  ///
  /// Crockford aliases are folded (`I`/`L` → `1`, `O` → `0`) so a hand-typed ID
  /// still resolves. Returns `null` when the input cannot be a valid ID.
  static DeviceId? tryParse(String raw) {
    final cleaned = raw
        .toUpperCase()
        .replaceAll(RegExp('[- ]'), '')
        .replaceAll(RegExp('[IL]'), '1')
        .replaceAll('O', '0');
    if (cleaned.length != length) return null;
    for (final unit in cleaned.codeUnits) {
      if (!_alphabet.contains(String.fromCharCode(unit))) return null;
    }
    return DeviceId(cleaned);
  }

  /// Short form for UI where the full ID would not fit, e.g. `A1B2C…9XYZ`.
  String get short => '${value.substring(0, 5)}…${value.substring(21)}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DeviceId && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Everything one peer advertises about itself during discovery and handshake.
@immutable
final class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.role,
    required this.appVersion,
    this.model,
  });

  final DeviceId id;

  /// User-visible name, e.g. "Ahmed's MacBook Pro". Editable in settings.
  final String name;

  final PlatformKind platform;
  final PeerRole role;

  /// Semantic version of the RemoteLink build, e.g. `0.1.0`.
  final String appVersion;

  /// Hardware model string when available, e.g. `Mac16,7` or `Pixel 9`.
  final String? model;

  DeviceInfo copyWith({String? name, String? model}) => DeviceInfo(
        id: id,
        name: name ?? this.name,
        platform: platform,
        role: role,
        appVersion: appVersion,
        model: model ?? this.model,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceInfo &&
          other.id == id &&
          other.name == name &&
          other.platform == platform &&
          other.role == role &&
          other.appVersion == appVersion &&
          other.model == model);

  @override
  int get hashCode => Object.hash(id, name, platform, role, appVersion, model);

  @override
  String toString() => 'DeviceInfo(${id.short}, $name, ${platform.name})';
}
