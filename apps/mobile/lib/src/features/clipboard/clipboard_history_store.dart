import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';

import '../../app/providers.dart';

/// Where the history key lives inside [IdentityStore].
///
/// On a phone that is the hardware-backed keystore — the Keychain on iOS, the
/// Android keystore behind `EncryptedSharedPreferences` — which is the whole
/// point: the ciphertext can sit in ordinary app storage because the key it
/// needs cannot be lifted out of a filesystem dump.
const String kClipboardHistoryKeyName = 'remotelink.clipboard.historykey';

/// Associated data binding a ciphertext to this file's purpose and version.
const String _kAad = 'remotelink.clipboard.history.v1';

const int _kFormatVersion = 1;

/// The opt-in, encrypted-at-rest clipboard history on the phone.
///
/// Key in the keystore, ciphertext in a file. The split matters both ways: bulk
/// data does not belong in a keychain item, and clipboard contents do not
/// belong in a file that a backup or a `adb backup` could carry off in the
/// clear.
///
/// Sealed with ChaCha20-Poly1305 as `[version][nonce][ciphertext‖tag]`, the
/// same framing the desktop's `EncryptedFileClipboardHistoryStore` uses. The
/// two are deliberately separate implementations rather than one shared class:
/// the layering forbids a common home (the ring buffer lives in `rl_core`,
/// which sits *beneath* `rl_crypto` and may not import it), and the halves that
/// would be shared — where the key comes from, where the bytes go — are the
/// halves that genuinely differ per platform.
///
/// **Nothing here writes clipboard contents as plaintext.** The document is
/// sealed before it reaches the filesystem, with no fallback path that skips
/// the seal.
final class EncryptedClipboardHistoryStore implements ClipboardHistoryStore {
  EncryptedClipboardHistoryStore({required this.keys, required this.file});

  /// The keystore, used only to hold the 32-byte content key.
  final IdentityStore keys;

  /// Where the sealed document lives.
  final File file;

  final Log _log = Log.scoped('mobile.clipboard.history');

  Uint8List? _cachedKey;

  @override
  Future<String?> read() async {
    if (!file.existsSync()) return null;

    final Uint8List sealed;
    try {
      sealed = await file.readAsBytes();
    } on FileSystemException catch (error) {
      _log.warn(
        'could not read the stored clipboard history',
        fields: <String, Object?>{'error': error.message},
      );
      return null;
    }

    if (sealed.length < 1 + Primitives.nonceLength + Primitives.macLength) {
      _log.warn('stored clipboard history is truncated; ignoring it');
      return null;
    }
    if (sealed[0] != _kFormatVersion) {
      _log.warn('stored clipboard history has an unknown format; ignoring it');
      return null;
    }

    final key = await _readKey();
    if (key == null) {
      _log.warn('clipboard history key is missing; the stored history is lost');
      return null;
    }

    try {
      final plaintext = await Primitives.openAtNonce(
        key: key,
        nonce: Uint8List.sublistView(sealed, 1, 1 + Primitives.nonceLength),
        sealed: Uint8List.sublistView(sealed, 1 + Primitives.nonceLength),
        aad: utf8.encode(_kAad),
      );
      return utf8.decode(plaintext);
    } on SecurityError catch (error) {
      _log.warn(
        'stored clipboard history failed authentication; ignoring it',
        fields: <String, Object?>{'error': error.code},
      );
      return null;
    }
  }

  @override
  Future<void> write(String document) async {
    final key = await _readKey() ?? await _createKey();

    // Fresh nonce per write. Under a long-lived key a repeated nonce is the one
    // unrecoverable mistake available with ChaCha20-Poly1305, and a counter
    // would have to survive process death to be safe.
    final nonce = _randomBytes(Primitives.nonceLength);
    final sealed = await Primitives.sealAtNonce(
      key: key,
      nonce: nonce,
      plaintext: utf8.encode(document),
      aad: utf8.encode(_kAad),
    );

    final out = Uint8List(1 + nonce.length + sealed.length)
      ..[0] = _kFormatVersion
      ..setRange(1, 1 + nonce.length, nonce)
      ..setRange(1 + nonce.length, 1 + nonce.length + sealed.length, sealed);

    final parent = file.parent;
    if (!parent.existsSync()) await parent.create(recursive: true);
    await file.writeAsBytes(out, flush: true);
  }

  @override
  Future<void> destroy() async {
    _cachedKey = null;

    if (file.existsSync()) {
      try {
        await file.delete();
      } on FileSystemException catch (error) {
        _log.warn(
          'could not delete the stored clipboard history',
          fields: <String, Object?>{'error': error.message},
        );
      }
    }

    // Overwritten rather than removed: [IdentityStore] is a two-method
    // interface with three implementations, and widening it with a `delete`
    // that exactly one caller needs would be a worse trade than an empty slot.
    // An empty value fails the length check in [_readKey] and so reads as
    // "no key", which is the behaviour a delete would have produced.
    await keys.write(kClipboardHistoryKeyName, '');
  }

  Future<Uint8List?> _readKey() async {
    final cached = _cachedKey;
    if (cached != null) return cached;

    final stored = await keys.read(kClipboardHistoryKeyName);
    if (stored == null || stored.isEmpty) return null;

    try {
      final decoded = base64Decode(stored);
      if (decoded.length != Primitives.secretLength) return null;
      return _cachedKey = Uint8List.fromList(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<Uint8List> _createKey() async {
    final key = _randomBytes(Primitives.secretLength);
    await keys.write(kClipboardHistoryKeyName, base64Encode(key));
    return _cachedKey = key;
  }
}

/// `Random.secure()` is the OS CSPRNG on every platform RemoteLink targets.
Uint8List _randomBytes(int length) {
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}
