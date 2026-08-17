import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/providers.dart';
import 'package:remotelink_desktop/src/domain/clipboard_history_store.dart';
import 'package:rl_core/rl_core.dart';

/// A string distinctive enough that finding it anywhere in a file's bytes is
/// proof the file is plaintext, not a coincidence.
const String _secret = 'sentinel-4f3a-never-in-plaintext';

/// A 16-byte stand-in for the sync path's truncated SHA-256.
///
/// Folds the whole string rather than its first sixteen bytes: seeds here
/// differ in their last character, and a prefix-only digest would collide and
/// quietly turn a five-entry test into a one-entry one.
Uint8List _hash(String seed) {
  final bytes = Uint8List(16);
  final source = utf8.encode(seed);
  for (var i = 0; i < source.length; i++) {
    bytes[i % bytes.length] = (bytes[i % bytes.length] * 31 + source[i]) & 0xff;
  }
  return bytes;
}

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('rl_clipboard_history');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  List<String> filesInDirectory() => directory
      .listSync()
      .map((entity) => entity.uri.pathSegments.last)
      .where((name) => name.isNotEmpty)
      .toList()
    ..sort();

  group('EncryptedFileClipboardHistoryStore', () {
    test('round-trips a document', () async {
      final store = EncryptedFileClipboardHistoryStore.inDirectory(directory);

      expect(await store.read(), isNull);
      await store.write('{"hello":"$_secret"}');
      expect(await store.read(), equals('{"hello":"$_secret"}'));
    });

    test('what lands on disk is ciphertext, not the document', () async {
      final store = EncryptedFileClipboardHistoryStore.inDirectory(directory);
      await store.write(jsonEncode(<String, Object?>{'entry': _secret}));

      final bytes = store.file.readAsBytesSync();
      expect(bytes.length, greaterThan(0));

      // Byte-level, not string-level: a naive writer would leave the secret
      // sitting in the file even if the surrounding JSON were mangled.
      final needle = utf8.encode(_secret);
      var found = false;
      for (var i = 0; i + needle.length <= bytes.length; i++) {
        var matches = true;
        for (var j = 0; j < needle.length; j++) {
          if (bytes[i + j] != needle[j]) {
            matches = false;
            break;
          }
        }
        if (matches) {
          found = true;
          break;
        }
      }
      expect(found, isFalse, reason: 'the document reached disk in plaintext');

      // The key is a separate file, and it is not the document.
      expect(filesInDirectory(),
          equals(<String>['clipboard_history.enc', 'clipboard_history.key']));
    });

    test('a tampered file is refused rather than parsed', () async {
      final store = EncryptedFileClipboardHistoryStore.inDirectory(directory);
      await store.write('{"entry":"$_secret"}');

      final bytes = store.file.readAsBytesSync();
      // Flip a bit inside the ciphertext, past the version byte and nonce.
      bytes[bytes.length - 20] ^= 0x01;
      store.file.writeAsBytesSync(bytes);

      expect(await store.read(), isNull);
    });

    test('a history file whose key is gone is lost, not fatal', () async {
      final store = EncryptedFileClipboardHistoryStore.inDirectory(directory);
      await store.write('{"entry":"$_secret"}');
      store.keyFile.deleteSync();

      final reopened =
          EncryptedFileClipboardHistoryStore.inDirectory(directory);
      expect(await reopened.read(), isNull);
    });

    test('destroy removes the ciphertext and the key with it', () async {
      final store = EncryptedFileClipboardHistoryStore.inDirectory(directory);
      await store.write('{"entry":"$_secret"}');
      expect(filesInDirectory(), hasLength(2));

      await store.destroy();

      expect(filesInDirectory(), isEmpty);
      expect(await store.read(), isNull);
    });
  });

  group('ClipboardHistory persistence', () {
    test('nothing is written to disk when persistence is off', () async {
      final clock = FakeClock();
      final history = ClipboardHistory(clock: clock);

      for (var i = 0; i < 5; i++) {
        history.record(
          kind: ClipboardHistoryKind.text,
          data: Uint8List.fromList(utf8.encode('$_secret $i')),
          contentHash: _hash('$_secret $i'),
          isConcealed: false,
        );
        clock.advance(const Duration(seconds: 1));
      }
      history.setPinned(history.entries.first.id, pinned: true);

      expect(history.entries, hasLength(5));
      expect(history.isPersistent, isFalse);
      expect(filesInDirectory(), isEmpty);

      await history.dispose();
      expect(filesInDirectory(), isEmpty);
    });

    test('entries survive a restart once persistence is enabled', () async {
      final clock = FakeClock();
      final history = ClipboardHistory(clock: clock);

      await setClipboardHistoryPersistence(
        history: history,
        directory: directory,
        enabled: true,
      );

      history.record(
        kind: ClipboardHistoryKind.text,
        data: Uint8List.fromList(utf8.encode(_secret)),
        contentHash: _hash(_secret),
        isConcealed: false,
      );
      clock.advance(const Duration(seconds: 1));
      history.record(
        kind: ClipboardHistoryKind.url,
        data: Uint8List.fromList(utf8.encode('https://example.test/page')),
        contentHash: _hash('url'),
        isConcealed: false,
      );
      final pinned = history.entries.first;
      expect(history.setPinned(pinned.id, pinned: true), isTrue);

      // dispose() drains the write queue, which is what a clean quit does.
      await history.dispose();

      final reopened = ClipboardHistory(clock: clock);
      final restored = await reopened.restore(
        EncryptedFileClipboardHistoryStore.inDirectory(directory),
      );

      expect(restored, isTrue);
      expect(reopened.isPersistent, isTrue);
      expect(reopened.entries, hasLength(2));
      expect(reopened.entries.first.kind, equals(ClipboardHistoryKind.url));
      expect(reopened.entries.first.pinned, isTrue);
      expect(reopened.entries.last.text, equals(_secret));

      await reopened.dispose();
    });

    test('turning persistence off leaves nothing behind', () async {
      final history = ClipboardHistory(clock: FakeClock());
      await setClipboardHistoryPersistence(
        history: history,
        directory: directory,
        enabled: true,
      );
      history.record(
        kind: ClipboardHistoryKind.text,
        data: Uint8List.fromList(utf8.encode(_secret)),
        contentHash: _hash(_secret),
        isConcealed: false,
      );
      await history.dispose();

      final second = ClipboardHistory(clock: FakeClock());
      await second.restore(
        EncryptedFileClipboardHistoryStore.inDirectory(directory),
      );
      await setClipboardHistoryPersistence(
        history: second,
        directory: directory,
        enabled: false,
      );

      expect(filesInDirectory(), isEmpty);
      expect(second.isPersistent, isFalse);

      // A later restore finds nothing, which is how "off" is represented.
      final third = ClipboardHistory(clock: FakeClock());
      expect(
        await third.restore(
          EncryptedFileClipboardHistoryStore.inDirectory(directory),
        ),
        isFalse,
      );

      await second.dispose();
      await third.dispose();
    });

    test('a concealed entry is never persisted', () async {
      final history = ClipboardHistory(clock: FakeClock());
      await setClipboardHistoryPersistence(
        history: history,
        directory: directory,
        enabled: true,
      );

      history.record(
        kind: ClipboardHistoryKind.text,
        data: Uint8List.fromList(utf8.encode(_secret)),
        contentHash: _hash(_secret),
        isConcealed: true,
      );
      await history.dispose();

      final reopened = ClipboardHistory(clock: FakeClock());
      await reopened.restore(
        EncryptedFileClipboardHistoryStore.inDirectory(directory),
      );
      expect(reopened.entries, isEmpty);

      await reopened.dispose();
    });
  });
}
