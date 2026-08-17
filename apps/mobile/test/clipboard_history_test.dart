import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/clipboard/clipboard_history_store.dart';
import 'package:rl_core/rl_core.dart';

import 'support/fakes.dart';

/// Distinctive enough that finding it in a file's bytes proves plaintext.
const String _secret = 'sentinel-9c1d-never-in-plaintext';

/// A 16-byte stand-in for the sync path's truncated SHA-256, folding the whole
/// string so seeds differing only in their last character do not collide.
Uint8List _hash(String seed) {
  final bytes = Uint8List(16);
  final source = utf8.encode(seed);
  for (var i = 0; i < source.length; i++) {
    bytes[i % bytes.length] = (bytes[i % bytes.length] * 31 + source[i]) & 0xff;
  }
  return bytes;
}

void _record(
  ClipboardHistory history,
  String value, {
  bool isConcealed = false,
}) =>
    history.record(
      kind: ClipboardHistoryKind.text,
      data: Uint8List.fromList(utf8.encode(value)),
      contentHash: _hash(value),
      isConcealed: isConcealed,
    );

void main() {
  late Directory directory;
  late InMemoryIdentityStore keys;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('rl_mobile_history');
    keys = InMemoryIdentityStore();
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  EncryptedClipboardHistoryStore buildStore() => EncryptedClipboardHistoryStore(
        keys: keys,
        file: File('${directory.path}/clipboard_history.enc'),
      );

  List<String> filesInDirectory() =>
      directory.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  group('EncryptedClipboardHistoryStore', () {
    test('round-trips a document with a key from the keystore', () async {
      final store = buildStore();

      expect(await store.read(), isNull);
      await store.write('{"entry":"$_secret"}');

      expect(await store.read(), equals('{"entry":"$_secret"}'));
      // The key went to the keystore, not the file.
      expect(keys.values.keys, contains(kClipboardHistoryKeyName));
      expect(
        base64Decode(keys.values[kClipboardHistoryKeyName]!),
        hasLength(32),
      );
    });

    test('what lands in the file is ciphertext, not the document', () async {
      final store = buildStore();
      await store.write(jsonEncode(<String, Object?>{'entry': _secret}));

      final bytes = store.file.readAsBytesSync();
      final needle = utf8.encode(_secret);
      var found = false;
      for (var i = 0; i + needle.length <= bytes.length && !found; i++) {
        found = true;
        for (var j = 0; j < needle.length; j++) {
          if (bytes[i + j] != needle[j]) {
            found = false;
            break;
          }
        }
      }
      expect(found, isFalse, reason: 'the document reached the file in plain');
      // And the key never sits beside the ciphertext.
      expect(filesInDirectory(), equals(<String>['clipboard_history.enc']));
    });

    test('a file that survives without its key is lost, not fatal', () async {
      final store = buildStore();
      await store.write('{"entry":"$_secret"}');

      // What a keystore wipe looks like: the file is still there, the key is
      // not. Reading must degrade to "nothing", never throw on launch.
      await keys.write(kClipboardHistoryKeyName, '');

      expect(await buildStore().read(), isNull);
    });

    test('destroy removes the file and clears the key', () async {
      final store = buildStore();
      await store.write('{"entry":"$_secret"}');

      await store.destroy();

      expect(filesInDirectory(), isEmpty);
      expect(keys.values[kClipboardHistoryKeyName], isEmpty);
      expect(await buildStore().read(), isNull);
    });
  });

  group('ClipboardHistory on the phone', () {
    test('nothing is written when persistence is off', () async {
      final clock = FakeClock();
      final history = ClipboardHistory(clock: clock);

      for (var i = 0; i < 4; i++) {
        _record(history, '$_secret $i');
        clock.advance(const Duration(seconds: 1));
      }

      expect(history.entries, hasLength(4));
      expect(history.isPersistent, isFalse);
      expect(filesInDirectory(), isEmpty);
      expect(keys.values, isEmpty);

      await history.dispose();
    });

    test('entries survive a restart once persistence is enabled', () async {
      final clock = FakeClock();
      final history = ClipboardHistory(clock: clock);
      await history.enablePersistence(buildStore());

      _record(history, _secret);
      clock.advance(const Duration(seconds: 1));
      _record(history, 'https://example.test/thing');
      final pinned = history.entries.first;
      expect(history.setPinned(pinned.id, pinned: true), isTrue);
      await history.dispose();

      final reopened = ClipboardHistory(clock: clock);
      expect(await reopened.restore(buildStore()), isTrue);
      expect(reopened.entries, hasLength(2));
      expect(reopened.entries.first.pinned, isTrue);
      expect(reopened.entries.last.text, equals(_secret));

      await reopened.dispose();
    });

    test('a concealed entry is never persisted', () async {
      final history = ClipboardHistory(clock: FakeClock());
      await history.enablePersistence(buildStore());

      _record(history, _secret, isConcealed: true);
      await history.dispose();

      final reopened = ClipboardHistory(clock: FakeClock());
      await reopened.restore(buildStore());
      expect(reopened.entries, isEmpty);

      await reopened.dispose();
    });
  });
}
