import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';

/// Optional capabilities a peer advertises in its hello.
///
/// Capabilities, not version numbers, gate every feature. A desktop without
/// screen-capture permission simply omits `screenCapture`, and the phone's UI
/// hides the button — no version sniffing, no runtime failures.
extension type const Capabilities(int bits) {
  static const int mouse = 1 << 0;
  static const int keyboard = 1 << 1;
  static const int clipboardText = 1 << 2;
  static const int clipboardImage = 1 << 3;
  static const int clipboardFiles = 1 << 4;
  static const int screenCapture = 1 << 5;
  static const int mediaControl = 1 << 6;
  static const int mediaMetadata = 1 << 7;
  static const int fileTransfer = 1 << 8;
  static const int powerControl = 1 << 9;
  static const int launchApps = 1 << 10;
  static const int runCommands = 1 << 11;
  static const int gamepad = 1 << 12;
  static const int presentation = 1 << 13;
  static const int compression = 1 << 14;
  static const int unreliableChannel = 1 << 15;
  static const int sessionResumption = 1 << 16;

  /// Display brightness adjustment.
  ///
  /// Set only where a working path was detected — a DDC/CI-capable external
  /// monitor or a panel the OS exposes. A phone that never sees this bit shows
  /// no slider, which is better than a slider that moves and changes nothing.
  static const int brightness = 1 << 18;

  /// Desktop controlling the phone.
  ///
  /// Advertised by the phone if its backend supports it, and by the desktop
  /// to indicate it has the UI to inject inputs.
  static const int phoneControl = 1 << 19;

  /// Pinch, rotate, and multi-finger swipe.
  ///
  /// Advertised only where the host can express them as real gestures. Windows
  /// has no synthetic gesture API, so its backend approximates with the
  /// shortcuts a person would press and does not set this bit — a phone that
  /// never sees it can decline to offer pinch-zoom rather than offering one
  /// that behaves subtly differently.
  static const int gestures = 1 << 17;

  bool has(int capability) => bits & capability != 0;

  /// Capabilities present on both sides — the effective feature set.
  Capabilities intersect(Capabilities other) => Capabilities(bits & other.bits);

  /// Returns a copy with [capability] added.
  Capabilities plus(int capability) => Capabilities(bits | capability);
}

/// Client → server. First message on every connection.
///
/// Sent in the clear (the AEAD is not yet established), so it carries nothing
/// secret: an ephemeral public key, a version range, and a nonce. The device
/// name is deliberately *not* here — it is sent encrypted after the handshake,
/// so a passive observer on the LAN cannot enumerate who is connecting.
@immutable
final class ClientHello extends Message {
  const ClientHello({
    required this.minVersion,
    required this.maxVersion,
    required this.ephemeralPublicKey,
    required this.clientNonce,
    required this.capabilities,
    this.knownServerId,
  });

  final int minVersion;
  final int maxVersion;

  /// X25519 public key, 32 bytes. Fresh per connection.
  final Uint8List ephemeralPublicKey;

  /// 32 random bytes mixed into the transcript hash to guarantee freshness even
  /// if an ephemeral key is ever repeated by a broken RNG.
  final Uint8List clientNonce;

  final Capabilities capabilities;

  /// The server identity this client believes it is talking to.
  ///
  /// Present when the client has paired before. The server uses it to look up
  /// which of its identities to authenticate with, and to fail fast with a
  /// clear error if the client has stale trust data.
  final DeviceId? knownServerId;

  @override
  MessageType get type => MessageType.clientHello;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(minVersion)
      ..writeUint8(maxVersion)
      ..writeBytes(ephemeralPublicKey)
      ..writeBytes(clientNonce)
      ..writeVarUint(capabilities.bits)
      ..writeOptionalString(knownServerId?.value);
  }

  static ClientHello readFrom(ByteReader reader) {
    final minVersion = reader.readUint8();
    final maxVersion = reader.readUint8();
    final ephemeralPublicKey = reader.readBytes(32);
    final clientNonce = reader.readBytes(32);
    final capabilities = Capabilities(reader.readVarUint());
    final rawId = reader.readOptionalString(maxLength: 64);
    return ClientHello(
      minVersion: minVersion,
      maxVersion: maxVersion,
      ephemeralPublicKey: ephemeralPublicKey,
      clientNonce: clientNonce,
      capabilities: capabilities,
      knownServerId: rawId == null ? null : DeviceId.tryParse(rawId),
    );
  }
}

/// Server → client. Selects the protocol version and returns key material.
@immutable
final class ServerHello extends Message {
  const ServerHello({
    required this.selectedVersion,
    required this.serverId,
    required this.ephemeralPublicKey,
    required this.serverNonce,
    required this.capabilities,
    required this.requiresPairing,
  });

  final int selectedVersion;

  /// The server's stable identity, derived from its long-term key.
  ///
  /// Sent in the clear because it is already broadcast in the mDNS TXT record.
  final DeviceId serverId;

  final Uint8List ephemeralPublicKey;
  final Uint8List serverNonce;
  final Capabilities capabilities;

  /// True when this client is not in the trust store and must pair first.
  final bool requiresPairing;

  @override
  MessageType get type => MessageType.serverHello;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(selectedVersion)
      ..writeString(serverId.value)
      ..writeBytes(ephemeralPublicKey)
      ..writeBytes(serverNonce)
      ..writeVarUint(capabilities.bits)
      ..writeBool(requiresPairing);
  }

  static ServerHello readFrom(ByteReader reader) {
    final selectedVersion = reader.readUint8();
    final rawId = reader.readString(maxLength: 64);
    final serverId = DeviceId.tryParse(rawId);
    if (serverId == null) {
      throw const ProtocolError('bad_device_id', 'malformed server device id');
    }
    return ServerHello(
      selectedVersion: selectedVersion,
      serverId: serverId,
      ephemeralPublicKey: reader.readBytes(32),
      serverNonce: reader.readBytes(32),
      capabilities: Capabilities(reader.readVarUint()),
      requiresPairing: reader.readBool(),
    );
  }
}

/// Either direction. Proves possession of the long-term key over the transcript.
///
/// This is the message that turns an anonymous Diffie-Hellman into an
/// authenticated one. The MAC covers every byte exchanged so far, so an
/// attacker who tampered with either hello cannot produce a matching tag.
@immutable
final class HandshakeFinish extends Message {
  const HandshakeFinish({
    required this.staticPublicKey,
    required this.transcriptMac,
  });

  /// The sender's long-term X25519 public key, 32 bytes.
  ///
  /// Sent under the freshly derived AEAD, never in the clear — otherwise a
  /// passive observer could fingerprint devices across networks.
  final Uint8List staticPublicKey;

  /// 32-byte HMAC-SHA256 over the handshake transcript.
  final Uint8List transcriptMac;

  @override
  MessageType get type => MessageType.handshakeFinish;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeBytes(staticPublicKey)
      ..writeBytes(transcriptMac);
  }

  static HandshakeFinish readFrom(ByteReader reader) => HandshakeFinish(
        staticPublicKey: reader.readBytes(32),
        transcriptMac: reader.readBytes(32),
      );
}

/// Liveness probe. Also the RTT measurement primitive.
@immutable
final class Ping extends Message {
  const Ping({required this.senderMicros, this.echoPayload});

  /// The sender's monotonic clock reading at transmit time.
  final int senderMicros;

  /// Optional padding, used by the connection-quality probe to measure
  /// throughput and MTU behaviour without opening a second channel.
  final Uint8List? echoPayload;

  @override
  MessageType get type => MessageType.ping;

  @override
  void writeTo(ByteWriter writer) {
    writer.writeUint64(senderMicros);
    final payload = echoPayload;
    writer.writeBool(payload != null);
    if (payload != null) writer.writeLengthPrefixedBytes(payload);
  }

  static Ping readFrom(ByteReader reader) {
    final senderMicros = reader.readUint64();
    final hasPayload = reader.readBool();
    return Ping(
      senderMicros: senderMicros,
      echoPayload: hasPayload
          ? reader.readLengthPrefixedBytes(maxLength: 64 * 1024)
          : null,
    );
  }
}

/// Reply to a [Ping], echoing the original timestamp.
///
/// Echoing rather than stamping means RTT is computed entirely against the
/// initiator's own monotonic clock. The two devices never need synchronised
/// time, which removes an entire class of "negative latency" bugs.
@immutable
final class Pong extends Message {
  const Pong({
    required this.originalSenderMicros,
    required this.responderMicros,
  });

  final int originalSenderMicros;

  /// The responder's own clock, used to estimate one-way delay asymmetry.
  final int responderMicros;

  @override
  MessageType get type => MessageType.pong;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint64(originalSenderMicros)
      ..writeUint64(responderMicros);
  }

  static Pong readFrom(ByteReader reader) => Pong(
        originalSenderMicros: reader.readUint64(),
        responderMicros: reader.readUint64(),
      );
}

/// Acknowledges a frame that requested one.
@immutable
final class Ack extends Message {
  const Ack({required this.acknowledgedSequence, required this.receivedMicros});

  final int acknowledgedSequence;
  final int receivedMicros;

  @override
  MessageType get type => MessageType.ack;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint32(acknowledgedSequence)
      ..writeUint64(receivedMicros);
  }

  static Ack readFrom(ByteReader reader) => Ack(
        acknowledgedSequence: reader.readUint32(),
        receivedMicros: reader.readUint64(),
      );
}

/// Wire-stable error codes.
///
/// Coarse by design. A remote peer learns only enough to decide whether to
/// retry, re-pair, or give up; anything finer would help an attacker probe the
/// trust store. Detailed diagnostics stay in the local log.
enum ProtocolErrorCode {
  /// No mutually supported protocol version.
  versionMismatch(1),

  /// Handshake MAC did not verify, or the peer is not who it claimed.
  authenticationFailed(2),

  /// The peer is not paired and pairing was not offered or was declined.
  notPaired(3),

  /// A previously trusted device was revoked.
  revoked(4),

  /// Too many attempts; back off.
  rateLimited(5),

  /// The message was well-formed but not permitted for this session's tier.
  permissionDenied(6),

  /// The requested capability is unavailable on this host.
  unsupportedCapability(7),

  /// Frame violated the wire format.
  malformedFrame(8),

  /// Server is shutting down or at its session limit.
  serverUnavailable(9),

  /// The resumption ticket was unknown or expired.
  invalidTicket(10),

  /// Anything else.
  internal(255);

  const ProtocolErrorCode(this.wireValue);

  final int wireValue;

  static ProtocolErrorCode fromWire(int value) => values.firstWhere(
        (code) => code.wireValue == value,
        orElse: () => ProtocolErrorCode.internal,
      );

  /// Whether reconnecting without user intervention could succeed.
  bool get isRetryable => switch (this) {
        ProtocolErrorCode.serverUnavailable ||
        ProtocolErrorCode.internal ||
        ProtocolErrorCode.invalidTicket =>
          true,
        _ => false,
      };
}

/// Structured error report.
@immutable
final class ErrorMessage extends Message {
  const ErrorMessage({
    required this.code,
    required this.detail,
    this.retryAfterMillis,
  });

  final ProtocolErrorCode code;

  /// Human-readable detail for logs. Never rendered directly in the UI, which
  /// localises from [code] instead.
  final String detail;

  /// Hint for rate limiting, in milliseconds.
  final int? retryAfterMillis;

  @override
  MessageType get type => MessageType.error;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(code.wireValue)
      ..writeString(detail)
      ..writeVarUint(retryAfterMillis ?? 0);
  }

  static ErrorMessage readFrom(ByteReader reader) {
    final code = ProtocolErrorCode.fromWire(reader.readUint8());
    final detail = reader.readString(maxLength: 4096);
    final retryAfter = reader.readVarUint();
    return ErrorMessage(
      code: code,
      detail: detail,
      retryAfterMillis: retryAfter == 0 ? null : retryAfter,
    );
  }
}

/// Why a peer is closing the connection.
enum CloseReason {
  /// User pressed disconnect.
  userRequested(1),

  /// Application is exiting.
  shuttingDown(2),

  /// Idle past the configured timeout.
  idleTimeout(3),

  /// Superseded by a newer connection from the same device.
  replaced(4),

  /// Trust was revoked mid-session.
  revoked(5),

  /// Protocol violation.
  protocolError(6);

  const CloseReason(this.wireValue);

  final int wireValue;

  static CloseReason fromWire(int value) => values.firstWhere(
        (reason) => reason.wireValue == value,
        orElse: () => CloseReason.protocolError,
      );

  /// Whether the client should attempt to reconnect automatically.
  ///
  /// A deliberate disconnect must not trigger the reconnect supervisor —
  /// otherwise "disconnect" would be a button that does nothing.
  bool get shouldReconnect => switch (this) {
        CloseReason.shuttingDown || CloseReason.idleTimeout => true,
        _ => false,
      };
}

/// Graceful shutdown notice.
@immutable
final class CloseMessage extends Message {
  const CloseMessage({required this.reason, this.detail});

  final CloseReason reason;
  final String? detail;

  @override
  MessageType get type => MessageType.close;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(reason.wireValue)
      ..writeOptionalString(detail);
  }

  static CloseMessage readFrom(ByteReader reader) => CloseMessage(
        reason: CloseReason.fromWire(reader.readUint8()),
        detail: reader.readOptionalString(maxLength: 1024),
      );
}

/// Server → client. An opaque ticket enabling an abbreviated handshake.
///
/// The ticket is the server's own state, sealed with a key only the server
/// holds. Resumption therefore costs the server no per-client storage, and a
/// stolen ticket is useless without the session key it is bound to.
@immutable
final class ResumptionTicket extends Message {
  const ResumptionTicket({
    required this.ticket,
    required this.lifetimeSeconds,
  });

  final Uint8List ticket;
  final int lifetimeSeconds;

  @override
  MessageType get type => MessageType.resumptionTicket;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeLengthPrefixedBytes(ticket)
      ..writeVarUint(lifetimeSeconds);
  }

  static ResumptionTicket readFrom(ByteReader reader) => ResumptionTicket(
        ticket: reader.readLengthPrefixedBytes(maxLength: 512),
        lifetimeSeconds: reader.readVarUint(),
      );
}

/// Client → server. Presents a ticket to skip the full handshake.
@immutable
final class ResumeSession extends Message {
  const ResumeSession({
    required this.ticket,
    required this.clientNonce,
    required this.bindingMac,
  });

  final Uint8List ticket;
  final Uint8List clientNonce;

  /// MAC over `ticket || clientNonce` keyed by the resumption secret, proving
  /// the client actually holds the session key the ticket refers to.
  final Uint8List bindingMac;

  @override
  MessageType get type => MessageType.resumeSession;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeLengthPrefixedBytes(ticket)
      ..writeBytes(clientNonce)
      ..writeBytes(bindingMac);
  }

  static ResumeSession readFrom(ByteReader reader) => ResumeSession(
        ticket: reader.readLengthPrefixedBytes(maxLength: 512),
        clientNonce: reader.readBytes(32),
        bindingMac: reader.readBytes(32),
      );
}
