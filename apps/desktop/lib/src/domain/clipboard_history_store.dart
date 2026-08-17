import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';

/// Associated data binding a ciphertext to this file's purpose and version.
///
/// A blob lifted out of another RemoteLink file and dropped in here fails
/// authentication rather than decrypting into something the parser then has to
/// be defensive about.
const String _kAad = 'remotelink.clipboard.history.v1';

/// Leading byte of the sealed file, so a future format change is detectable
/// rather than being read as a nonce.
const int _kFormatVersion = 1;

/// The opt-in, encrypted-at-rest clipboard history file.
///
/// ## What is on disk, and what is not
///
/// Two files, and only when the user has turned persistence on:
///
/// * `clipboard_history.key` — 32 bytes from `Random.secure()`, base64, mode
///   0600. This is the desktop half of "a key from the platform keystore on
///   mobile and the equivalent file store on desktop": the same trade-off the
///   identity key already makes, documented as gap 1 in `docs/SECURITY.md`.
///   An attacker with read access to the user's profile can read this key —
///   but that attacker can also read the clipboard directly, so the file buys
///   protection against the cases that actually differ: a backup, a synced
///   profile directory, a stolen disk image, and anything that greps the
///   application-support folder for interesting strings.
/// * `clipboard_history.enc` — `[version][nonce][ciphertext‖tag]`, sealed with
///   ChaCha20-Poly1305 under that key.
///
/// **Nothing here ever writes the clipboard contents as plaintext.** The store
/// is handed a JSON document by [ClipboardHistory] and seals it before it
/// touches the filesystem; there is no debug path, no temp file, and no
/// fallback that skips the seal.
///
/// The absence of these files is what "persistence is off" means. There is no
/// preference flag that could disagree with the data — off means there is
/// nothing on disk to find.
final class EncryptedFileClipboardHistoryStore
    implements ClipboardHistoryStore {
  EncryptedFileClipboardHistoryStore({
    required this.file,
    required this.keyFile,
  });

  /// Builds the pair of files inside an application-support directory.
  factory EncryptedFileClipboardHistoryStore.inDirectory(Directory directory) =>
      EncryptedFileClipboardHistoryStore(
        file: File('${directory.path}/clipboard_history.enc'),
        keyFile: File('${directory.path}/clipboard_history.key'),
      );

  final File file;
  final File keyFile;

  final Log _log = Log.scoped('desktop.clipboard.history');

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
      _log.warn(
        'stored clipboard history has an unknown format version; ignoring it',
        fields: <String, Object?>{'version': sealed[0]},
      );
      return null;
    }

    final key = await _readKey();
    if (key == null) {
      // A history file with no key is unrecoverable. Say so once and move on
      // rather than failing the launch over a convenience feature.
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

    // A fresh nonce per write. Nonce reuse under a fixed key is the one fatal
    // mistake available with ChaCha20-Poly1305, and a counter would have to
    // survive restarts to be safe — random is both simpler and correct here.
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

    await file.writeAsBytes(out, flush: true);
    await _restrictToOwner(file);
  }

  @override
  Future<void> destroy() async {
    _cachedKey = null;
    // The key goes with the data. Leaving it behind would mean a later "turn
    // persistence back on" silently re-adopted a key whose lifetime the user
    // thought they had ended.
    for (final target in <File>[file, keyFile]) {
      if (!target.existsSync()) continue;
      try {
        await target.delete();
      } on FileSystemException catch (error) {
        _log.warn(
          'could not delete a clipboard history file',
          fields: <String, Object?>{
            'path': target.path,
            'error': error.message,
          },
        );
      }
    }
  }

  Future<Uint8List?> _readKey() async {
    final cached = _cachedKey;
    if (cached != null) return cached;
    if (!keyFile.existsSync()) return null;

    try {
      final decoded = base64Decode((await keyFile.readAsString()).trim());
      if (decoded.length != Primitives.secretLength) return null;
      return _cachedKey = Uint8List.fromList(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<Uint8List> _createKey() async {
    final key = _randomBytes(Primitives.secretLength);
    await keyFile.writeAsString(base64Encode(key), flush: true);
    await _restrictToOwner(keyFile);
    return _cachedKey = key;
  }

  /// Owner-only, best effort — a no-op on filesystems without POSIX bits,
  /// which is the same honest limitation `identity.key` carries.
  Future<void> _restrictToOwner(File target) async {
    if (Platform.isWindows) return;
    await Process.run('chmod', <String>['600', target.path]);
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
