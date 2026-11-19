import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/command_registry.dart';
import 'package:rl_protocol/rl_protocol.dart';

void main() {
  late Directory directory;
  final secret = List<int>.filled(32, 17);
  final executable =
      Platform.isWindows ? r'C:\Tools\backup.exe' : '/tools/backup';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('command-registry-test');
  });

  tearDown(() => directory.delete(recursive: true));

  test('new commands stay disabled until enabled and survive reload', () async {
    final registry =
        await CommandRegistry.open(directory: directory, secret: secret);
    final entry = await registry.add(
      name: 'Back up',
      executable: executable,
      arguments: ['notes with spaces', '--full'],
    );
    expect(entry.enabled, isFalse);
    expect(entry.minimumTier, PermissionTier.extended);

    await registry.setEnabled(entry.id, true);
    final reloaded =
        await CommandRegistry.open(directory: directory, secret: secret);
    final saved = reloaded.commands.single;
    expect(saved.id, entry.id);
    expect(saved.name, 'Back up');
    expect(saved.executable, executable);
    expect(saved.arguments, ['notes with spaces', '--full']);
    expect(saved.enabled, isTrue);
  });

  test('a hand-edited registry is empty and reports a load warning', () async {
    final registry =
        await CommandRegistry.open(directory: directory, secret: secret);
    await registry.add(name: 'Back up', executable: executable);
    final file = File('${directory.path}/${CommandRegistry.fileName}');
    await file.writeAsString(
        (await file.readAsString()).replaceFirst('Back up', 'Tampered'));
    final reloaded =
        await CommandRegistry.open(directory: directory, secret: secret);
    expect(reloaded.commands, isEmpty);
    expect(reloaded.loadWarning, isTrue);
  });

  test('resolve refuses unknown, disabled and insufficient-tier actions',
      () async {
    final registry =
        await CommandRegistry.open(directory: directory, secret: secret);
    final entry = await registry.add(name: 'Back up', executable: executable);
    expect(registry.resolve('missing', PermissionTier.admin).refusal,
        CommandOutcome.refusedUnknown);
    expect(registry.resolve(entry.id, PermissionTier.admin).refusal,
        CommandOutcome.refusedDisabled);

    await registry.setEnabled(entry.id, true);
    expect(registry.resolve(entry.id, PermissionTier.standard).refusal,
        CommandOutcome.refusedTier);
    expect(registry.resolve(entry.id, PermissionTier.extended).command?.id,
        entry.id);
  });
}
