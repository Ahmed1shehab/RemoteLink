import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/ui/clipboard_history_panel.dart';
import 'package:rl_core/rl_core.dart';

import 'support/fakes.dart';

Uint8List _hash(String seed) {
  final bytes = Uint8List(16);
  final source = utf8.encode(seed);
  for (var i = 0; i < source.length; i++) {
    bytes[i % bytes.length] = (bytes[i % bytes.length] * 31 + source[i]) & 0xff;
  }
  return bytes;
}

void _record(ClipboardHistory history, String value) => history.record(
      kind: ClipboardHistoryKind.text,
      data: Uint8List.fromList(utf8.encode(value)),
      contentHash: _hash(value),
      isConcealed: false,
    );

Future<void> _pumpPanel(
  WidgetTester tester, {
  required ClipboardHistory history,
  List<ClipboardHistoryEntry>? recopied,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: desktopHomeOverridesWith(
        clipboardHistory: history,
        recopy: (entry) async {
          recopied?.add(entry);
          return true;
        },
      ),
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ClipboardHistoryPanel()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('says the list is memory-only when it is', (tester) async {
    final history = ClipboardHistory(clock: FakeClock());
    await _pumpPanel(tester, history: history);

    expect(find.text('Clipboard history'), findsOneWidget);
    expect(
      find.textContaining('Kept in memory only'),
      findsOneWidget,
      reason: 'the user must be able to tell where this list lives',
    );
    expect(find.textContaining('Nothing copied yet'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await history.dispose();
  });

  testWidgets('lists entries newest first and re-copies the tapped one',
      (tester) async {
    final clock = FakeClock();
    final history = ClipboardHistory(clock: clock);
    _record(history, 'the older note');
    clock.advance(const Duration(minutes: 5));
    _record(history, 'the newer note');

    final recopied = <ClipboardHistoryEntry>[];
    await _pumpPanel(tester, history: history, recopied: recopied);

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles, hasLength(2));
    expect((tiles.first.title! as Text).data, equals('the newer note'));

    await tester.tap(find.text('the older note'));
    await tester.pump();

    expect(recopied, hasLength(1));
    expect(recopied.single.text, equals('the older note'));
    expect(tester.takeException(), isNull);

    await history.dispose();
  });

  testWidgets('pins and deletes an entry from the list', (tester) async {
    final clock = FakeClock();
    final history = ClipboardHistory(clock: clock);
    _record(history, 'worth keeping');
    clock.advance(const Duration(minutes: 1));
    _record(history, 'disposable');

    await _pumpPanel(tester, history: history);

    // Pin the second row — the older of the two.
    await tester.tap(find.byIcon(Icons.push_pin_outlined).last);
    await tester.pump();
    await tester.pump();

    expect(history.pinnedCount, equals(1));
    expect(
      history.entries
          .singleWhere((entry) => entry.text == 'worth keeping')
          .pinned,
      isTrue,
    );
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    // Remove the first row.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pump();
    await tester.pump();

    expect(history.entries, hasLength(1));
    expect(history.entries.single.text, equals('worth keeping'));
    expect(find.text('disposable'), findsNothing);
    expect(tester.takeException(), isNull);

    await history.dispose();
  });

  testWidgets('clear all empties the list, pinned rows included',
      (tester) async {
    final clock = FakeClock();
    final history = ClipboardHistory(clock: clock);
    _record(history, 'first');
    clock.advance(const Duration(minutes: 1));
    _record(history, 'second');
    history.setPinned(history.entries.first.id, pinned: true);

    await _pumpPanel(tester, history: history);

    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await tester.pump();

    expect(history.entries, isEmpty);
    expect(find.textContaining('Nothing copied yet'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await history.dispose();
  });
}
