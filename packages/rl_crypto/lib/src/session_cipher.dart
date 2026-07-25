import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:rl_core/rl_core.dart';

import 'primitives.dart';

/// Maximum number of messages sealed under one key before it must be rotated.
///
/// ChaCha20-Poly1305's safety margin is far above this, but 2^32 is a
/// comfortable ceiling that a long-lived session driving 240 Hz input would
/// take roughly six months of continuous use to reach. Hitting it is treated as
/// a fatal condition rather than silently wrapping, because a repeated nonce
/// with the same key destroys confidentiality outright.
const int kMaxMessagesPerKey = 0xFFFFFFFF;

/// Size of the sliding window used to reject replayed sequence numbers.
///
/// Only relevant on the unreliable datagram channel; TCP already delivers in
/// order, so on that path the window never sees an out-of-order arrival.
const int kReplayWindowSize = 64;

/// One direction of an encrypted session.
///
/// Each direction has its own key and its own strictly increasing counter, so
/// the two sides can never collide on a nonce even though both are encrypting
/// concurrently. This is why there are two of these objects per session rather
/// than one shared cipher.
final class DirectionalCipher {
  DirectionalCipher({required Uint8List key, required this.label})
      : _key = SecretKey(key),
        _keyBytes = key;

  final SecretKey _key;
  final Uint8List _keyBytes;

  /// Human-readable direction, e.g. `c2s`. Diagnostics only.
  final String label;

  int _counter = 0;

  /// Number of messages processed under this key.
  int get counter => _counter;

  /// Reusable nonce buffer.
  ///
  /// The first four bytes stay zero and the counter occupies the last eight in
  /// big-endian order. Deriving the nonce from a counter rather than random
  /// bytes removes any chance of a birthday collision and costs nothing to
  /// verify: strictly increasing counter, therefore never repeated.
  final Uint8List _nonce = Uint8List(Primitives.nonceLength);

  void _setNonce(int counter) {
    ByteData.sublistView(_nonce).setUint64(4, counter, Endian.big);
  }

  /// Seals [plaintext], binding [aad] into the authentication tag.
  ///
  /// [aad] carries the frame header, so an attacker cannot take a valid
  /// ciphertext and re-present it under a different message type or sequence
  /// number — the tag would no longer verify.
  ///
  /// Returns `ciphertext || tag` and advances the counter.
  Future<Uint8List> seal(List<int> plaintext, {List<int>? aad}) async {
    if (_counter >= kMaxMessagesPerKey) {
      throw SecurityError(
        'nonce_exhausted',
        'direction $label reached the message limit for one key',
      );
    }
    _setNonce(_counter);
    final box = await Primitives.aead.encrypt(
      plaintext,
      secretKey: _key,
      nonce: _nonce,
      aad: aad ?? const <int>[],
    );
    _counter++;

    final cipherLength = box.cipherText.length;
    final result = Uint8List(cipherLength + Primitives.macLength);
    result.setRange(0, cipherLength, box.cipherText);
    result.setRange(cipherLength, result.length, box.mac.bytes);
    return result;
  }

  /// Opens a sealed message produced by the peer's matching direction.
  ///
  /// [counter] must be supplied explicitly rather than inferred, because on the
  /// datagram channel messages can arrive out of order and the receiver needs
  /// to reconstruct the exact nonce the sender used.
  Future<Uint8List> open(
    Uint8List sealed, {
    required int counter,
    List<int>? aad,
  }) async {
    if (sealed.length < Primitives.macLength) {
      throw const SecurityError(
        'ciphertext_too_short',
        'sealed message shorter than the authentication tag',
      );
    }
    final splitAt = sealed.length - Primitives.macLength;
    _setNonce(counter);

    try {
      final opened = await Primitives.aead.decrypt(
        SecretBox(
          Uint8List.sublistView(sealed, 0, splitAt),
          nonce: _nonce,
          mac: Mac(Uint8List.sublistView(sealed, splitAt)),
        ),
        secretKey: _key,
        aad: aad ?? const <int>[],
      );
      return Uint8List.fromList(opened);
    } on SecretBoxAuthenticationError catch (e) {
      // Deliberately opaque. Distinguishing "wrong key" from "tampered frame"
      // to anything that can observe the failure is an oracle.
      throw SecurityError(
        'authentication_failed',
        'AEAD tag verification failed on $label',
        cause: e,
      );
    }
  }

  /// Advances the counter without encrypting, used when a message is dropped
  /// after the nonce was allocated.
  void skip() => _counter++;

  /// Zeroes the key material. Called on session teardown.
  void dispose() => Primitives.wipe(_keyBytes);
}

/// Rejects duplicate and too-old sequence numbers.
///
/// Implements the sliding bitmap from RFC 6479 (IPsec anti-replay). TCP makes
/// this redundant, but the unreliable input channel needs it: without it, an
/// attacker could capture a "mouse button down" datagram and replay it
/// endlessly.
final class ReplayWindow {
  ReplayWindow({this.size = kReplayWindowSize});

  final int size;

  int _highest = -1;
  int _bitmap = 0;

  /// Highest accepted sequence number so far.
  int get highest => _highest;

  /// Records [sequence], returning `false` if it is a replay or too old.
  bool accept(int sequence) {
    if (sequence < 0) return false;

    if (sequence > _highest) {
      final shift = sequence - _highest;
      // Dart's `<<` on the VM wraps at 64 bits, which is exactly the bitmap
      // width, so a shift of 64 or more must be special-cased to clear it
      // rather than relying on the shift itself.
      _bitmap = shift >= 64 ? 0 : _bitmap << shift;
      _bitmap |= 1;
      _highest = sequence;
      return true;
    }

    final age = _highest - sequence;
    if (age >= size) return false;

    final mask = 1 << age;
    if (_bitmap & mask != 0) return false;

    _bitmap |= mask;
    return true;
  }

  void reset() {
    _highest = -1;
    _bitmap = 0;
  }
}

/// Both directions of an established session, plus the secrets derived
/// alongside them.
final class SessionKeys {
  SessionKeys({
    required this.send,
    required this.receive,
    required this.resumptionSecret,
    required this.exporterSecret,
  });

  final DirectionalCipher send;
  final DirectionalCipher receive;

  /// Seeds an abbreviated reconnect. Rotated on every full handshake so that
  /// compromising it cannot unlock past sessions.
  final Uint8List resumptionSecret;

  /// Available to higher layers that need a key bound to this session — the
  /// file-transfer subsystem uses it to derive per-transfer content keys.
  final Uint8List exporterSecret;

  final ReplayWindow replayWindow = ReplayWindow();

  void dispose() {
    send.dispose();
    receive.dispose();
    Primitives.wipe(resumptionSecret);
    Primitives.wipe(exporterSecret);
  }
}
