import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'handshake.dart';
import 'identity.dart';
import 'primitives.dart';

/// How long a pairing attempt stays open before it expires.
///
/// Short on purpose. The window is the only period in which an attacker on the
/// same network gets to try their luck against a six-digit SAS, so leaving it
/// open indefinitely would turn a 1-in-a-million guess into a certainty.
const Duration kPairingTimeout = Duration(seconds: 60);

/// Failed attempts from one peer before pairing locks out.
const int kMaxPairingAttempts = 3;

/// How long a lockout lasts.
const Duration kPairingLockout = Duration(minutes: 15);

/// Everything the QR code encodes.
///
/// Scanning it gives the phone the server's real static key *before* the
/// handshake begins, which closes the machine-in-the-middle window entirely
/// rather than merely making it detectable. That is why QR is the default and
/// numeric comparison is the fallback.
@immutable
final class PairingPayload {
  const PairingPayload({
    required this.deviceId,
    required this.publicKey,
    required this.name,
    required this.host,
    required this.port,
    required this.token,
  });

  final DeviceId deviceId;
  final Uint8List publicKey;
  final String name;
  final String host;
  final int port;

  /// Single-use token proving the phone read a *currently displayed* code.
  ///
  /// Without it, a screenshot of an old QR code would pair forever. The desktop
  /// rotates the token whenever the pairing sheet is shown.
  final Uint8List token;

  /// Encodes as a compact URI.
  ///
  /// A URI rather than raw JSON so a generic camera app can surface it as a
  /// tappable link that deep-links into the phone app, and so the format has
  /// obvious room to grow via query parameters.
  String toUri() {
    final query = <String, String>{
      'k': base64Url.encode(publicKey).replaceAll('=', ''),
      'n': name,
      'h': host,
      'p': port.toString(),
      't': base64Url.encode(token).replaceAll('=', ''),
    };
    final encoded = query.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return 'remotelink://pair/${deviceId.value}?$encoded';
  }

  /// Parses a scanned URI, returning `null` on anything malformed.
  ///
  /// Returns `null` rather than throwing because the input is whatever the
  /// camera happened to see — a QR code on a cereal box is not an exceptional
  /// condition.
  static PairingPayload? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'remotelink') return null;
    if (uri.host != 'pair') return null;

    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;

    final deviceId = DeviceId.tryParse(segments.first);
    if (deviceId == null) return null;

    final rawKey = uri.queryParameters['k'];
    final host = uri.queryParameters['h'];
    final rawPort = uri.queryParameters['p'];
    if (rawKey == null || host == null || rawPort == null) return null;

    final port = int.tryParse(rawPort);
    if (port == null || port <= 0 || port > 65535) return null;

    final publicKey = _decodeBase64Url(rawKey);
    if (publicKey == null || publicKey.length != 32) return null;

    final token = _decodeBase64Url(uri.queryParameters['t'] ?? '');

    return PairingPayload(
      deviceId: deviceId,
      publicKey: publicKey,
      name: uri.queryParameters['n'] ?? deviceId.short,
      host: host,
      port: port,
      token: token ?? Uint8List(0),
    );
  }

  static Uint8List? _decodeBase64Url(String value) {
    try {
      final padded = value.padRight((value.length + 3) & ~3, '=');
      return Uint8List.fromList(base64Url.decode(padded));
    } on FormatException {
      return null;
    }
  }
}

/// Where a pairing attempt currently stands.
enum PairingStage {
  /// Nothing in progress.
  idle,

  /// Waiting for the user to compare digits or scan the code.
  awaitingUser,

  /// The user confirmed locally; waiting on the peer.
  awaitingPeer,

  /// Trust established.
  completed,

  /// Declined, timed out, or failed verification.
  failed,
}

/// Live state of a pairing attempt, suitable for driving UI.
@immutable
final class PairingState {
  const PairingState({
    required this.stage,
    required this.method,
    this.shortAuthenticationString,
    this.peerName,
    this.peerId,
    this.rejection,
    this.attemptsRemaining,
    this.expiresAt,
  });

  const PairingState.idle()
      : stage = PairingStage.idle,
        method = PairingMethod.qrCode,
        shortAuthenticationString = null,
        peerName = null,
        peerId = null,
        rejection = null,
        attemptsRemaining = null,
        expiresAt = null;

  final PairingStage stage;
  final PairingMethod method;

  /// Six digits to show the user. Both devices must display the same value.
  final String? shortAuthenticationString;

  final String? peerName;
  final DeviceId? peerId;
  final PairRejectReason? rejection;
  final int? attemptsRemaining;
  final DateTime? expiresAt;

  bool get isTerminal =>
      stage == PairingStage.completed || stage == PairingStage.failed;

  PairingState copyWith({
    PairingStage? stage,
    PairingMethod? method,
    String? shortAuthenticationString,
    String? peerName,
    DeviceId? peerId,
    PairRejectReason? rejection,
    int? attemptsRemaining,
    DateTime? expiresAt,
  }) =>
      PairingState(
        stage: stage ?? this.stage,
        method: method ?? this.method,
        shortAuthenticationString:
            shortAuthenticationString ?? this.shortAuthenticationString,
        peerName: peerName ?? this.peerName,
        peerId: peerId ?? this.peerId,
        rejection: rejection ?? this.rejection,
        attemptsRemaining: attemptsRemaining ?? this.attemptsRemaining,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}

/// Throttles pairing attempts per peer address.
///
/// The SAS is six digits, so an attacker who can retry freely succeeds after
/// about half a million tries — which over a LAN is minutes, not years. This
/// class is what turns that into a practical impossibility, and it is why the
/// numeric methods are safe to offer at all.
final class PairingRateLimiter {
  PairingRateLimiter(
      {required Clock clock, this.maxAttempts = kMaxPairingAttempts})
      : _clock = clock;

  final Clock _clock;
  final int maxAttempts;

  final Map<String, _AttemptRecord> _records = <String, _AttemptRecord>{};

  /// Whether [peerKey] may attempt pairing now.
  bool isAllowed(String peerKey) {
    final record = _records[peerKey];
    if (record == null) return true;
    if (record.lockedUntil == null) return true;
    if (_clock.now().isAfter(record.lockedUntil!)) {
      _records.remove(peerKey);
      return true;
    }
    return false;
  }

  /// Attempts left before lockout.
  int attemptsRemaining(String peerKey) {
    final record = _records[peerKey];
    if (record == null) return maxAttempts;
    final used = record.failures;
    return used >= maxAttempts ? 0 : maxAttempts - used;
  }

  /// Seconds until [peerKey] may try again, or `null` if it may try now.
  int? retryAfterSeconds(String peerKey) {
    final lockedUntil = _records[peerKey]?.lockedUntil;
    if (lockedUntil == null) return null;
    final remaining = lockedUntil.difference(_clock.now());
    return remaining.isNegative ? null : remaining.inSeconds + 1;
  }

  /// Records a failure, locking out once [maxAttempts] is reached.
  void recordFailure(String peerKey) {
    final record = _records.putIfAbsent(peerKey, _AttemptRecord.new)
      ..failures += 1;
    if (record.failures >= maxAttempts) {
      record.lockedUntil = _clock.now().add(kPairingLockout);
    }
  }

  /// Clears history after a success.
  void recordSuccess(String peerKey) => _records.remove(peerKey);

  /// Drops expired lockouts so the map does not grow without bound.
  void prune() {
    final now = _clock.now();
    _records.removeWhere(
      (_, record) =>
          record.lockedUntil != null && now.isAfter(record.lockedUntil!),
    );
  }
}

final class _AttemptRecord {
  int failures = 0;
  DateTime? lockedUntil;
}

/// Turns a completed handshake into a persisted trust relationship.
///
/// Kept separate from the handshake itself because the two answer different
/// questions. The handshake answers "did both sides derive the same secret?",
/// which is pure cryptography. Pairing answers "should this device be allowed
/// in?", which is a policy decision involving the user, rate limits, and
/// permission tiers. Mixing them would make the cryptography untestable without
/// simulating a user.
final class PairingCoordinator {
  PairingCoordinator({
    required this.identity,
    required Clock clock,
    PairingRateLimiter? rateLimiter,
  })  : _clock = clock,
        _rateLimiter = rateLimiter ?? PairingRateLimiter(clock: clock);

  final DeviceIdentity identity;
  final Clock _clock;
  final PairingRateLimiter _rateLimiter;

  final StreamController<PairingState> _states =
      StreamController<PairingState>.broadcast();

  PairingState _state = const PairingState.idle();

  /// Current state, for a UI that attaches after pairing started.
  PairingState get state => _state;

  /// Live state updates.
  Stream<PairingState> get states => _states.stream;

  /// Begins an attempt using the SAS from a completed handshake.
  ///
  /// Returns the state to display. The caller shows
  /// [PairingState.shortAuthenticationString] and waits for the user.
  PairingState begin({
    required HandshakeResult handshake,
    required PairingMethod method,
    required String peerName,
  }) {
    _emit(
      PairingState(
        stage: PairingStage.awaitingUser,
        method: method,
        shortAuthenticationString: handshake.shortAuthenticationString,
        peerName: peerName,
        peerId: handshake.peerId,
        expiresAt: _clock.now().add(kPairingTimeout),
        attemptsRemaining: _rateLimiter.attemptsRemaining(
          handshake.peerId.value,
        ),
      ),
    );
    return _state;
  }

  /// Checks whether this peer is currently allowed to attempt pairing.
  ///
  /// Called before anything is shown to the user, so a locked-out attacker
  /// cannot even generate a prompt — which would otherwise be a way to spam the
  /// victim's screen until they tap Accept out of irritation.
  /// Returns `null` when the attempt is allowed, or the rejection to send back.
  PairReject? checkRateLimit(DeviceId peerId) {
    if (_rateLimiter.isAllowed(peerId.value)) return null;
    return PairReject(
      reason: PairRejectReason.rateLimited,
      attemptsRemaining: 0,
      retryAfterSeconds: _rateLimiter.retryAfterSeconds(peerId.value),
    );
  }

  /// The local user accepted. Produces the trust record to persist.
  ///
  /// The record is built from [handshake] rather than from anything the peer
  /// asserted, so a peer cannot claim a public key it does not hold — the key
  /// here is the one that was proven during key confirmation.
  TrustedPeer accept({
    required HandshakeResult handshake,
    required String peerName,
    required PlatformKind platform,
    required int permissionTier,
    String? lastAddress,
  }) {
    _rateLimiter.recordSuccess(handshake.peerId.value);
    _emit(
      _state.copyWith(
        stage: PairingStage.completed,
        peerId: handshake.peerId,
        peerName: peerName,
      ),
    );

    return TrustedPeer(
      id: handshake.peerId,
      publicKey: handshake.peerStaticPublicKey,
      name: peerName,
      platform: platform,
      pairedAt: _clock.now(),
      permissionTier: permissionTier,
      lastSeenAt: _clock.now(),
      lastAddress: lastAddress,
    );
  }

  /// The attempt failed or was declined.
  PairReject reject({
    required DeviceId peerId,
    required PairRejectReason reason,
  }) {
    // Only genuine verification failures count toward the lockout. A user who
    // declines a connection they did not initiate should not be locking
    // themselves out of their own devices.
    if (reason == PairRejectReason.verificationFailed) {
      _rateLimiter.recordFailure(peerId.value);
    }

    final rejection = PairReject(
      reason: reason,
      attemptsRemaining: _rateLimiter.attemptsRemaining(peerId.value),
      retryAfterSeconds: _rateLimiter.retryAfterSeconds(peerId.value),
    );

    _emit(
      _state.copyWith(
        stage: PairingStage.failed,
        rejection: reason,
        attemptsRemaining: rejection.attemptsRemaining,
      ),
    );
    return rejection;
  }

  /// Verifies a scanned QR payload against the key proven in the handshake.
  ///
  /// This is the step that makes QR pairing strong: the scanned key came over
  /// an optical channel an attacker cannot reach, so if it matches the key the
  /// handshake authenticated, there was no relay.
  bool verifyScannedPayload({
    required PairingPayload payload,
    required HandshakeResult handshake,
  }) {
    if (payload.deviceId != handshake.peerId) return false;
    return Primitives.constantTimeEquals(
      payload.publicKey,
      handshake.peerStaticPublicKey,
    );
  }

  void _emit(PairingState next) {
    _state = next;
    if (_states.hasListener) _states.add(next);
  }

  Future<void> dispose() => _states.close();
}
