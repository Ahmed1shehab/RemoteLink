import 'dart:convert';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:test/test.dart';

/// Records every call, so a test can assert that persistence stayed *silent*
/// rather than merely that nothing readable came back out of it.
final class RecordingStore implements ClipboardHistoryStore {
  String? document;
  int writes = 0;
  int destroys = 0;

  @override
  Future<String?> read() async => document;

  @override
  Future<void> write(String document) async {
    writes++;
    this.document = document;
  }

  @override
  Future<void> destroy() async {
    destroys++;
    document = null;
  }
}

Uint8List _hash(String seed) {
  final bytes = Uint8List(16);
  final source = utf8.encode(seed);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = source[i % source.length] ^ (i * 31);
  }
  return bytes;
}

Uint8List _text(String value) => Uint8List.fromList(utf8.encode(value));

ClipboardHistoryEntry? _record(
  ClipboardHistory history,
  String value, {
  bool isConcealed = false,
  ClipboardHistoryKind kind = ClipboardHistoryKind.text,
}) =>
    history.record(
      kind: kind,
      data: _text(value),
      contentHash: _hash(value),
      isConcealed: isConcealed,
    );

void main() {
  group('ClipboardHistory', () {
    test('concealed content is never recorded', () async {
      final history = ClipboardHistory(clock: FakeClock());

      final recorded = _record(history, 'hunter2', isConcealed: true);

      expect(recorded, isNull);
      expect(history.entries, isEmpty);

      // And nothing about it lingers: a later unconcealed copy of the very same
      // bytes is a fresh entry, not a resurrection of a suppressed one.
      _record(history, 'hunter2');
      expect(history.entries, hasLength(1));

      await history.dispose();
    });

    test('a concealed copy is not recorded even when persistence is on',
        () async {
      final store = RecordingStore();
      final history = ClipboardHistory(clock: FakeClock());
      await history.enablePersistence(store);
      final writesAfterEnable = store.writes;

      _record(history, 'correct horse battery staple', isConcealed: true);

      expect(history.entries, isEmpty);
      expect(store.writes, equals(writesAfterEnable),
          reason: 'a suppressed entry must not trigger a write');
      expect(store.document, isNot(contains('horse')));

      await history.dispose();
    });

    test('the ring evicts at 25', () async {
      final clock = FakeClock();
      final history = ClipboardHistory(clock: clock);

      for (var i = 0; i < 30; i++) {
        _record(history, 'item $i');
        clock.advance(const Duration(seconds: 1));
      }

      expect(history.entries, hasLength(kClipboardHistoryCapacity));
      expect(history.entries.first.text, equals('item 29'));
      expect(history.entries.last.text, equals('item 5'));
      expect(
        history.entries.map((entry) => entry.text),
        isNot(contains('item 4')),
      );

      await history.dispose();
    });

    test('pinned items survive eviction', () async {
      final clock = FakeClock();
      final history = ClipboardHistory(clock: clock);

      final keeper = _record(history, 'the pinned one')!;
      expect(history.setPinned(keeper.id, pinned: true), isTrue);
      clock.advance(const Duration(seconds: 1));

      // Enough traffic to have flushed it out several times over.
      for (var i = 0; i < 60; i++) {
        _record(history, 'noise $i');
        clock.advance(const Duration(seconds: 1));
      }

      expect(history.entries, hasLength(kClipboardHistoryCapacity));
      final survivor =
          history.entries.where((entry) => entry.id == keeper.id).toList();
      expect(survivor, hasLength(1));
      expect(survivor.single.pinned, isTrue);
      expect(survivor.single.text, equals('the pinned one'));

      await history.dispose();
    });

    test('the pin count is capped so eviction always has a victim', () async {
      final clock = FakeClock();
      final history = ClipboardHistory(clock: clock);

      final ids = <String>[];
      for (var i = 0; i < kClipboardHistoryCapacity; i++) {
        ids.add(_record(history, 'item $i')!.id);
        clock.advance(const Duration(seconds: 1));
      }

      var pinned = 0;
      for (final id in ids) {
        if (history.setPinned(id, pinned: true)) pinned++;
      }

      expect(pinned, equals(kMaxPinnedClipboardEntries));
      expect(history.canPinMore, isFalse);

      // The ring still accepts new content and still holds its cap.
      _record(history, 'after the pins');
      expect(history.entries, hasLength(kClipboardHistoryCapacity));
      expect(history.entries.first.text, equals('after the pins'));

      await history.dispose();
    });

    test('re-copying an item moves it to the top instead of duplicating it',
        () async {
      final clock = FakeClock();
      final history = ClipboardHistory(clock: clock);

      final first = _record(history, 'alpha')!;
      clock.advance(const Duration(seconds: 1));
      _record(history, 'beta');
      clock.advance(const Duration(seconds: 1));
      expect(history.setPinned(first.id, pinned: true), isTrue);

      _record(history, 'alpha');

      expect(history.entries, hasLength(2));
      expect(history.entries.first.text, equals('alpha'));
      // The pin follows the content, not the row.
      expect(history.entries.first.pinned, isTrue);

      await history.dispose();
    });

    test('delete removes one entry and clear removes pinned ones too',
        () async {
      final clock = FakeClock();
      final history = ClipboardHistory(clock: clock);

      final a = _record(history, 'a')!;
      clock.advance(const Duration(seconds: 1));
      final b = _record(history, 'b')!;
      clock.advance(const Duration(seconds: 1));
      history.setPinned(b.id, pinned: true);

      expect(history.remove(a.id), isTrue);
      expect(history.remove(a.id), isFalse);
      expect(history.entries, hasLength(1));

      history.clear();
      expect(history.entries, isEmpty);

      await history.dispose();
    });

    test('nothing is written anywhere when persistence is off', () async {
      final store = RecordingStore();
      final history = ClipboardHistory(clock: FakeClock());

      for (var i = 0; i < 5; i++) {
        _record(history, 'secret $i');
      }
      history.setPinned(history.entries.first.id, pinned: true);
      history.remove(history.entries.last.id);
      history.clear();

      expect(history.isPersistent, isFalse);
      expect(store.writes, isZero);
      expect(store.document, isNull);

      await history.dispose();
    });

    test('persistence round-trips entries and pins', () async {
      final clock = FakeClock();
      final store = RecordingStore();
      final history = ClipboardHistory(clock: clock);

      await history.enablePersistence(store);
      expect(history.isPersistent, isTrue);

      _record(history, 'one');
      clock.advance(const Duration(seconds: 1));
      final pinned = _record(history, 'two')!;
      clock.advance(const Duration(seconds: 1));
      _record(history, 'three');
      history.setPinned(pinned.id, pinned: true);

      await history.dispose();

      final reloaded = ClipboardHistory(clock: clock);
      expect(await reloaded.restore(store), isTrue);

      expect(reloaded.isPersistent, isTrue);
      expect(
        reloaded.entries.map((entry) => entry.text),
        equals(<String>['three', 'two', 'one']),
      );
      expect(
        reloaded.entries.singleWhere((entry) => entry.id == pinned.id).pinned,
        isTrue,
      );

      await reloaded.dispose();
    });

    test('restore reports false and stays memory-only on an empty store',
        () async {
      final history = ClipboardHistory(clock: FakeClock());

      expect(await history.restore(RecordingStore()), isFalse);
      expect(history.isPersistent, isFalse);

      await history.dispose();
    });

    test('turning persistence off destroys what was written', () async {
      final store = RecordingStore();
      final history = ClipboardHistory(clock: FakeClock());

      await history.enablePersistence(store);
      _record(history, 'remembered');
      await history.dispose();

      final second = ClipboardHistory(clock: FakeClock());
      await second.restore(store);
      await second.disablePersistence();

      expect(second.isPersistent, isFalse);
      expect(store.destroys, equals(1));
      expect(store.document, isNull);
      // Turning persistence off is not the same as forgetting.
      expect(second.entries, hasLength(1));

      await second.dispose();
    });

    test('a truncated or tampered document costs rows, not the launch',
        () async {
      final store = RecordingStore()..document = '{"version":1,"entries":[';
      final history = ClipboardHistory(clock: FakeClock());

      expect(await history.restore(store), isTrue);
      expect(history.entries, isEmpty);

      store.document = jsonEncode(<String, Object?>{
        'version': 1,
        'entries': <Object?>[
          <String, Object?>{'kind': 'nonsense'},
          <String, Object?>{
            'id': 'good',
            'kind': 'text',
            'data': base64Encode(_text('kept')),
            'hash': base64Encode(_hash('kept')),
            'copiedAt': DateTime.utc(2026).toIso8601String(),
            'pinned': false,
          },
          42,
        ],
      });

      final second = ClipboardHistory(clock: FakeClock());
      expect(await second.restore(store), isTrue);
      expect(second.entries, hasLength(1));
      expect(second.entries.single.text, equals('kept'));

      await history.dispose();
      await second.dispose();
    });

    test('changes emit a snapshot the UI can render directly', () async {
      final history = ClipboardHistory(clock: FakeClock());
      final seen = <ClipboardHistorySnapshot>[];
      final sub = history.changes.listen(seen.add);

      _record(history, 'visible');
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
      expect(seen.single.entries.single.text, equals('visible'));
      expect(seen.single.isPersistent, isFalse);

      await sub.cancel();
      await history.dispose();
    });
  });
}
