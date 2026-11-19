import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/command_registry.dart';
import 'package:remotelink_desktop/src/ui/command_editor.dart';

void main() {
  testWidgets('adding a Quick Action shows it disabled', (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('quick-actions-editor');
    addTearDown(() => directory.deleteSync(recursive: true));
    final registry = (await tester.runAsync(() => CommandRegistry.open(
          directory: directory,
          secret: List.filled(32, 23),
        )))!;
    addTearDown(registry.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CommandEditor(
          registry: registry,
          pickExecutable: () async =>
              Platform.isWindows ? r'C:\Tools\backup.exe' : '/tools/backup',
        ),
      ),
    ));

    await tester.tap(find.text('Add action'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Action name'), 'Back up');
    await tester.tap(find.text('Choose executable'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final saved = registry.changes.first.timeout(const Duration(seconds: 10));
      await tester.tap(find.text('Save'));
      await saved;
    });
    await tester.pumpAndSettle();

    final row = find.widgetWithText(SwitchListTile, 'Back up');
    expect(row, findsOneWidget);
    expect(tester.widget<SwitchListTile>(row).value, isFalse);
    expect(find.text('Disabled'), findsOneWidget);
  });
}
