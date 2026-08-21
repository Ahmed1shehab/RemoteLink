import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/transfer/file_name_text.dart';

void main() {
  group('splitFileName', () {
    test('separates an ordinary extension', () {
      final parts = splitFileName('Screenshot_20260819-222940.png');
      expect(parts.stem, 'Screenshot_20260819-222940');
      expect(parts.extension, '.png');
    });

    test('leaves a name with no extension whole', () {
      expect(splitFileName('README').extension, isEmpty);
      expect(splitFileName('trailing.').extension, isEmpty);
    });

    test('a dotfile is a name, not an extension', () {
      // `.gitignore` has no stem to shorten, and treating the whole thing as an
      // extension would pin it and elide to nothing.
      expect(splitFileName('.gitignore').extension, isEmpty);
    });

    test('a long tail after a dot is not an extension', () {
      // Otherwise `report.final version` would keep the tail pinned and elide
      // the part the user reads.
      expect(splitFileName('report.final version').extension, isEmpty);
    });
  });

  group('elideFileName', () {
    test('leaves a name that fits exactly as it is', () {
      expect(elideFileName('Quarterly report.pdf'), 'Quarterly report.pdf');
    });

    test('keeps the extension when it shortens', () {
      const name =
          'Screenshot_20260819-222940_a_very_long_camera_export_name.png';
      final elided = elideFileName(name);

      expect(elided, endsWith('.png'));
      expect(elided, startsWith('Screenshot_20260819'));
      expect(elided, contains('…'));
      expect(elided.characters.length, lessThanOrEqualTo(44));
    });

    test('shortens a long name with no extension too', () {
      final elided = elideFileName('a' * 80);
      expect(elided, endsWith('…'));
      expect(elided.characters.length, lessThanOrEqualTo(44));
    });

    test('does not cut a name in half through a character', () {
      // Emoji are ordinary in camera-roll names; cutting between the halves of
      // a surrogate pair renders as a replacement glyph.
      final elided = elideFileName('${'🌅' * 40}.jpg');
      expect(elided, isNot(contains('�')));
      expect(elided, endsWith('.jpg'));
    });

    test('a budget the extension alone cannot fit is left to the ellipsis', () {
      // Nothing sensible to return here: cutting the stem to nothing would
      // leave a bare `…`, so the Text overflow deals with it instead.
      expect(
        elideFileName('archive.tar.gzip', maxCharacters: 4),
        'archive.tar.gzip',
      );
    });
  });

  testWidgets('the rendered name is bounded to two lines', (tester) async {
    const name = 'Screenshot_20260819-222940_from_the_phone_camera_roll.png';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 140, child: FileNameText(name)),
          ),
        ),
      ),
    );

    final rendered = tester.widget<Text>(find.byType(Text));
    expect(rendered.data, endsWith('.png'));
    expect(rendered.maxLines, 2);
    expect(rendered.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('it survives a dialog, which lays out by intrinsics',
      (tester) async {
    // Material sizes an AlertDialog with IntrinsicWidth, which throws on any
    // child that measures its own box during layout. The incoming-transfer
    // prompt is a dialog, and this widget names the files in it.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => const AlertDialog(
                  content: Row(
                    children: <Widget>[
                      Expanded(child: FileNameText('a_long_photo_name.jpeg')),
                    ],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('a_long_photo_name.jpeg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
