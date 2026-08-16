import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:rl_core/rl_core.dart';

/// Thin wrappers over `package:cryptography` with RemoteLink's parameters baked
/// in.
///
/// Centralising them here means the algorithm choices are stated once and can
/// be audited in one place, rather than being re-specified at every call site
/// where a mistaken parameter would be invisible.
abstract final class Primitives {
  /// Key agreement. X25519 over Curve25519.
  ///
  /// Chosen over P-256 because it has no invalid-curve or point-validation
  /// pitfalls, needs no parameter validation, and every implementation is
  /// constant-time by construction. Over P-521 or X448 because 128-bit security
  /// is the right target here and the extra latency would be visible on a
  /// phone's first connect.
  static final X25519 keyExchange = X25519();

  /// Authenticated encryption. ChaCha20-Poly1305 (RFC 8439).
  ///
  /// Preferred over AES-GCM for one decisive reason: this runs on phones and on
  /// desktops, and while every modern desktop has AES-NI, a software AES-GCM
  /// fallback on a low-end Android device is both slower and vulnerable to
  /// cache-timing attacks. ChaCha20 is fast and constant-time everywhere with
  /// no hardware dependency.
  ///
  /// Poly1305 also fails cleanly: a tampered frame produces an authentication
  /// error rather than plausible-looking plaintext.
  static final Cipher aead = Chacha20.poly1305Aead();

  /// Hash used for the transcript and for device-ID derivation.
  static final Sha256 hash = Sha256();

  /// MAC used inside HKDF and for pairing confirmation.
  static final Hmac hmac = Hmac.sha256();

  /// Length of an X25519 public or private key.
  static const int keyLength = 32;

  /// ChaCha20-Poly1305 nonce length.
  static const int nonceLength = 12;

  /// Poly1305 tag length.
  static const int macLength = 16;

  /// Symmetric key length.
  static const int secretLength = 32;

  /// Generates a fresh X25519 key pair.
  static Future<SimpleKeyPair> generateKeyPair() => keyExchange.newKeyPair();

  /// Reconstructs a key pair from stored private key bytes.
  static Future<SimpleKeyPair> keyPairFromSeed(List<int> privateKeyBytes) =>
      keyExchange.newKeyPairFromSeed(privateKeyBytes);

  /// X25519 shared secret between [keyPair] and [remotePublicKey].
  static Future<Uint8List> sharedSecret({
    required SimpleKeyPair keyPair,
    required Uint8List remotePublicKey,
  }) async {
    final secret = await keyExchange.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        remotePublicKey,
        type: KeyPairType.x25519,
      ),
    );
    return Uint8List.fromList(await secret.extractBytes());
  }

  /// SHA-256 of [data].
  static Future<Uint8List> sha256(List<int> data) async =>
      Uint8List.fromList((await hash.hash(data)).bytes);

  /// SHA-256 of a byte stream without retaining the whole input in memory.
  static Future<Uint8List> sha256Stream(Stream<List<int>> data) async {
    final sink = hash.toSync().newHashSink();
    await for (final chunk in data) {
      sink.add(chunk);
    }
    sink.close();
    return Uint8List.fromList((await sink.hash()).bytes);
  }

  /// HKDF (RFC 5869) with SHA-256.
  ///
  /// [salt] is the extract salt and [info] the expand context string. Distinct
  /// [info] values are what keep the send key, receive key, confirmation
  /// tokens, and SAS cryptographically independent despite sharing one input
  /// secret — reusing a label anywhere would collapse that separation.
  static Future<Uint8List> hkdf({
    required List<int> secret,
    required List<int> salt,
    required String info,
    int length = secretLength,
  }) async {
    final derived = await Hkdf(hmac: hmac, outputLength: length).deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
      info: info.codeUnits,
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  /// Seals one independently addressed payload with ChaCha20-Poly1305.
  ///
  /// Unlike [DirectionalCipher], the caller supplies the nonce. This is used
  /// for file chunks whose address must survive reconnects and random access.
  static Future<Uint8List> sealAtNonce({
    required List<int> key,
    required List<int> nonce,
    required List<int> plaintext,
    List<int> aad = const <int>[],
  }) async {
    final box = await aead.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return Uint8List.fromList(<int>[...box.cipherText, ...box.mac.bytes]);
  }

  /// Opens a payload produced by [sealAtNonce].
  static Future<Uint8List> openAtNonce({
    required List<int> key,
    required List<int> nonce,
    required List<int> sealed,
    List<int> aad = const <int>[],
  }) async {
    if (sealed.length < macLength) {
      throw const SecurityError(
        'ciphertext_too_short',
        'sealed payload shorter than the authentication tag',
      );
    }
    final splitAt = sealed.length - macLength;
    try {
      final opened = await aead.decrypt(
        SecretBox(
          sealed.sublist(0, splitAt),
          nonce: nonce,
          mac: Mac(sealed.sublist(splitAt)),
        ),
        secretKey: SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(opened);
    } on SecretBoxAuthenticationError catch (error) {
      throw SecurityError(
        'authentication_failed',
        'payload authentication failed',
        cause: error,
      );
    }
  }

  /// HMAC-SHA256 of [data] under [key].
  static Future<Uint8List> mac({
    required List<int> key,
    required List<int> data,
  }) async {
    final result = await hmac.calculateMac(data, secretKey: SecretKey(key));
    return Uint8List.fromList(result.bytes);
  }

  /// Length-independent equality.
  ///
  /// Every comparison of a MAC, tag, or key uses this. A `==` on lists exits at
  /// the first differing byte, and that timing difference is enough to forge a
  /// MAC one byte at a time given enough attempts.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    // The length itself is not secret, but returning early still leaks nothing
    // useful — a wrong-length candidate is rejected without a byte comparison.
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  /// Overwrites [buffer] with zeros.
  ///
  /// Best-effort only: Dart's GC may already have copied the bytes elsewhere,
  /// and there is no `mlock`. It still shortens the window in which a key sits
  /// in a heap dump, which is worth the two lines.
  static void wipe(Uint8List buffer) => buffer.fillRange(0, buffer.length, 0);
}
