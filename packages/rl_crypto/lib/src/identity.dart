import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

import 'primitives.dart';

/// A device's long-term cryptographic identity.
///
/// Generated once on first launch and persisted for the lifetime of the
/// installation. Everything else — the device ID shown in the UI, the QR code,
/// every trust relationship — is derived from this key pair, so losing it is
/// equivalent to becoming a new device and re-pairing everywhere.
final class DeviceIdentity {
  DeviceIdentity._({
    required this.id,
    required this.publicKey,
    required SimpleKeyPair keyPair,
  }) : _keyPair = keyPair;

  /// Stable identity derived from [publicKey].
  final DeviceId id;

  /// X25519 public key, 32 bytes.
  final Uint8List publicKey;

  final SimpleKeyPair _keyPair;

  /// Creates a brand-new identity from the platform CSPRNG.
  static Future<DeviceIdentity> generate() async {
    final keyPair = await Primitives.generateKeyPair();
    return _fromKeyPair(keyPair);
  }

  /// Restores an identity from persisted private key bytes.
  ///
  /// Throws [SecurityError] on a wrong-length seed rather than silently
  /// producing a different identity, which would look to the user like every
  /// paired device had spontaneously forgotten them.
  static Future<DeviceIdentity> fromPrivateKey(List<int> privateKeyBytes) async {
    if (privateKeyBytes.length != Primitives.keyLength) {
      throw SecurityError(
        'bad_identity_seed',
        'private key must be ${Primitives.keyLength} bytes, '
            'got ${privateKeyBytes.length}',
      );
    }
    final keyPair = await Primitives.keyPairFromSeed(privateKeyBytes);
    return _fromKeyPair(keyPair);
  }

  static Future<DeviceIdentity> _fromKeyPair(SimpleKeyPair keyPair) async {
    final publicKey = Uint8List.fromList(
      (await keyPair.extractPublicKey()).bytes,
    );
    final digest = await Primitives.sha256(publicKey);
    return DeviceIdentity._(
      id: DeviceId.fromDigest(digest),
      publicKey: publicKey,
      keyPair: keyPair,
    );
  }

  /// The underlying key pair, for use in key agreement only.
  ///
  /// Marked internal by convention: nothing outside `rl_crypto` should hold a
  /// reference to private key material.
  @internal
  SimpleKeyPair get keyPair => _keyPair;

  /// Raw private key bytes, for persistence.
  ///
  /// The caller is responsible for storing these somewhere the OS protects —
  /// DPAPI-backed storage on Windows, the Keychain on macOS, the Keystore on
  /// Android, and the Secure Enclave-backed Keychain on iOS.
  Future<Uint8List> extractPrivateKey() async =>
      Uint8List.fromList(await _keyPair.extractPrivateKeyBytes());

  @override
  String toString() => 'DeviceIdentity(${id.short})';
}

/// A remote device this one has paired with.
@immutable
final class TrustedPeer {
  const TrustedPeer({
    required this.id,
    required this.publicKey,
    required this.name,
    required this.platform,
    required this.pairedAt,
    required this.permissionTier,
    this.lastSeenAt,
    this.lastAddress,
    this.revoked = false,
  });

  final DeviceId id;

  /// The peer's long-term X25519 public key.
  ///
  /// This is the entire basis of trust: a handshake authenticates by proving
  /// possession of the matching private key. If this value is wrong, the peer
  /// simply cannot connect — there is no fallback path that ignores it.
  final Uint8List publicKey;

  final String name;
  final PlatformKind platform;
  final DateTime pairedAt;

  /// Wire value of the granted `PermissionTier`.
  ///
  /// Stored as an integer rather than the enum so that the persisted trust file
  /// stays readable by a build that adds or removes tiers.
  final int permissionTier;

  final DateTime? lastSeenAt;

  /// Last known address, used to try a direct reconnect before falling back to
  /// discovery. Purely an optimisation — never a trust input.
  final String? lastAddress;

  /// Revoked peers are retained rather than deleted so that a reconnect can be
  /// answered with a definitive "revoked" instead of an ambiguous "unknown
  /// device", which would send the user into a pairing flow that then fails.
  final bool revoked;

  TrustedPeer copyWith({
    String? name,
    DateTime? lastSeenAt,
    String? lastAddress,
    int? permissionTier,
    bool? revoked,
  }) =>
      TrustedPeer(
        id: id,
        publicKey: publicKey,
        name: name ?? this.name,
        platform: platform,
        pairedAt: pairedAt,
        permissionTier: permissionTier ?? this.permissionTier,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        lastAddress: lastAddress ?? this.lastAddress,
        revoked: revoked ?? this.revoked,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TrustedPeer && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'TrustedPeer(${id.short}, $name${revoked ? ', revoked' : ''})';
}
