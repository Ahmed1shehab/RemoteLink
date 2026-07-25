import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';

/// How the user is asked to authenticate a first-time connection.
///
/// Pairing exists to solve exactly one problem: the ephemeral Diffie-Hellman in
/// the handshake gives confidentiality against a passive eavesdropper, but on
/// its own it cannot detect an active machine-in-the-middle. Something outside
/// the network — the user's eyes — has to confirm that the key the phone
/// received is the key the desktop sent.
enum PairingMethod {
  /// The desktop displays a QR code containing its long-term public key; the
  /// phone scans it.
  ///
  /// Strongest option and the default. Because the phone learns the real static
  /// key over an out-of-band channel *before* the handshake, there is no window
  /// in which a machine-in-the-middle could substitute its own key — the
  /// handshake either authenticates against the scanned key or fails.
  qrCode(1),

  /// Both devices display a six-digit short authentication string derived from
  /// the handshake transcript; the user confirms they match.
  ///
  /// Secure against an active attacker for a non-obvious reason worth stating:
  /// the digits are a hash of *both* ephemeral keys, and an attacker sitting in
  /// the middle necessarily holds two different sessions, so the two screens
  /// would show different numbers. Forging a match means finding a collision in
  /// a hash the attacker cannot influence after commitment.
  ///
  /// The residual risk is a 1-in-10^6 blind guess, which is why
  /// [PairingReject.attemptsRemaining] caps retries.
  numericComparison(2),

  /// The desktop displays a six-digit code that the user types into the phone.
  ///
  /// Weaker than [numericComparison] against a sophisticated attacker, because
  /// the code is entered rather than compared and therefore commits later.
  /// Offered only as a fallback for headless or accessibility scenarios, and
  /// rate-limited more aggressively.
  numericEntry(3);

  const PairingMethod(this.wireValue);

  final int wireValue;

  static PairingMethod fromWire(int value) => values.firstWhere(
        (method) => method.wireValue == value,
        orElse: () => PairingMethod.numericComparison,
      );
}

/// Client → server. Asks to begin pairing.
@immutable
final class PairRequest extends Message {
  const PairRequest({
    required this.method,
    required this.deviceName,
    required this.platform,
    required this.staticPublicKey,
  });

  final PairingMethod method;

  /// Shown on the desktop's confirmation prompt so the user knows which phone
  /// is asking.
  final String deviceName;

  final PlatformKind platform;

  /// The client's long-term X25519 public key, which the server persists on
  /// success.
  final Uint8List staticPublicKey;

  @override
  MessageType get type => MessageType.pairRequest;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(method.wireValue)
      ..writeString(deviceName)
      ..writeUint8(platform.wireValue)
      ..writeBytes(staticPublicKey);
  }

  static PairRequest readFrom(ByteReader reader) => PairRequest(
        method: PairingMethod.fromWire(reader.readUint8()),
        deviceName: reader.readString(maxLength: 128),
        platform: PlatformKind.fromWire(reader.readUint8()),
        staticPublicKey: reader.readBytes(32),
      );
}

/// Server → client. Pairing may proceed; the user must now verify.
@immutable
final class PairChallenge extends Message {
  const PairChallenge({
    required this.method,
    required this.serverName,
    required this.staticPublicKey,
    required this.timeoutSeconds,
  });

  /// The method the server actually accepted, which may differ from the one
  /// requested — for example a headless server downgrades [PairingMethod.qrCode]
  /// to [PairingMethod.numericEntry].
  final PairingMethod method;

  final String serverName;

  /// The server's long-term public key.
  final Uint8List staticPublicKey;

  /// How long the user has to confirm before the attempt expires.
  ///
  /// Bounded deliberately: an indefinitely open pairing window is an
  /// indefinitely open opportunity for an attacker on the same network.
  final int timeoutSeconds;

  @override
  MessageType get type => MessageType.pairChallenge;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(method.wireValue)
      ..writeString(serverName)
      ..writeBytes(staticPublicKey)
      ..writeVarUint(timeoutSeconds);
  }

  static PairChallenge readFrom(ByteReader reader) => PairChallenge(
        method: PairingMethod.fromWire(reader.readUint8()),
        serverName: reader.readString(maxLength: 128),
        staticPublicKey: reader.readBytes(32),
        timeoutSeconds: reader.readVarUint(),
      );
}

/// Client → server. The user confirmed.
@immutable
final class PairConfirm extends Message {
  const PairConfirm({required this.confirmationMac});

  /// HMAC over the pairing transcript, keyed by the derived pairing secret.
  ///
  /// For [PairingMethod.numericComparison] the key is the session secret and
  /// this simply proves the client reached the same one. For
  /// [PairingMethod.numericEntry] the entered digits are mixed in, so a wrong
  /// code produces a MAC that cannot verify — the server never sees the code
  /// itself and cannot be tricked into a timing-based comparison.
  final Uint8List confirmationMac;

  @override
  MessageType get type => MessageType.pairConfirm;

  @override
  void writeTo(ByteWriter writer) => writer.writeBytes(confirmationMac);

  static PairConfirm readFrom(ByteReader reader) =>
      PairConfirm(confirmationMac: reader.readBytes(32));
}

/// Server → client. Trust established; both sides persist the peer key.
@immutable
final class PairComplete extends Message {
  const PairComplete({
    required this.serverId,
    required this.serverName,
    required this.confirmationMac,
  });

  final DeviceId serverId;
  final String serverName;

  /// The server's half of the mutual confirmation, so the client also learns
  /// that the server derived the same secret.
  final Uint8List confirmationMac;

  @override
  MessageType get type => MessageType.pairComplete;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(serverId.value)
      ..writeString(serverName)
      ..writeBytes(confirmationMac);
  }

  static PairComplete readFrom(ByteReader reader) {
    final rawId = reader.readString(maxLength: 64);
    final serverId = DeviceId.tryParse(rawId);
    if (serverId == null) {
      throw const ProtocolError('bad_device_id', 'malformed server device id');
    }
    return PairComplete(
      serverId: serverId,
      serverName: reader.readString(maxLength: 128),
      confirmationMac: reader.readBytes(32),
    );
  }
}

/// Why a pairing attempt failed.
enum PairRejectReason {
  /// The user pressed Deny.
  declined(1),

  /// Nobody confirmed within the window.
  timedOut(2),

  /// The confirmation MAC did not verify — wrong code, or an active attacker.
  verificationFailed(3),

  /// Too many failures from this address; try later.
  rateLimited(4),

  /// The desktop is configured to refuse new pairings.
  pairingDisabled(5),

  /// The server has reached its trusted-device limit.
  deviceLimitReached(6);

  const PairRejectReason(this.wireValue);

  final int wireValue;

  static PairRejectReason fromWire(int value) => values.firstWhere(
        (reason) => reason.wireValue == value,
        orElse: () => PairRejectReason.declined,
      );
}

/// Pairing was refused.
@immutable
final class PairReject extends Message {
  const PairReject({
    required this.reason,
    this.attemptsRemaining,
    this.retryAfterSeconds,
  });

  final PairRejectReason reason;

  /// Attempts left before the server locks pairing out for this peer.
  ///
  /// Surfaced to the user so a mistyped code is obviously recoverable, while
  /// making the lockout predictable rather than mysterious.
  final int? attemptsRemaining;

  final int? retryAfterSeconds;

  @override
  MessageType get type => MessageType.pairReject;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(reason.wireValue)
      ..writeVarUint(attemptsRemaining ?? 0)
      ..writeVarUint(retryAfterSeconds ?? 0);
  }

  static PairReject readFrom(ByteReader reader) {
    final reason = PairRejectReason.fromWire(reader.readUint8());
    final attempts = reader.readVarUint();
    final retryAfter = reader.readVarUint();
    return PairReject(
      reason: reason,
      attemptsRemaining: attempts == 0 ? null : attempts,
      retryAfterSeconds: retryAfter == 0 ? null : retryAfter,
    );
  }
}

/// Revokes an existing trust relationship.
///
/// Either side may send it. The desktop sends it when the user taps "Forget" in
/// the device manager; the phone sends it when the user removes a computer. On
/// receipt the peer key is deleted, every live session for that device is
/// closed, and any outstanding resumption ticket is invalidated.
@immutable
final class Unpair extends Message {
  const Unpair({required this.deviceId, this.reason});

  final DeviceId deviceId;
  final String? reason;

  @override
  MessageType get type => MessageType.unpair;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(deviceId.value)
      ..writeOptionalString(reason);
  }

  static Unpair readFrom(ByteReader reader) {
    final rawId = reader.readString(maxLength: 64);
    final deviceId = DeviceId.tryParse(rawId);
    if (deviceId == null) {
      throw const ProtocolError('bad_device_id', 'malformed device id');
    }
    return Unpair(
      deviceId: deviceId,
      reason: reader.readOptionalString(maxLength: 256),
    );
  }
}
