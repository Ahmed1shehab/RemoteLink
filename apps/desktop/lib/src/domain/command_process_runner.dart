import 'dart:io';

import 'command_registry.dart';

typedef CommandProcessRunner = Future<void> Function(
  String executable,
  List<String> arguments, {
  required String? workingDirectory,
  required bool runInShell,
});

Future<void> startRegisteredCommand(
  RegisteredCommand command, {
  CommandProcessRunner? runner,
}) =>
    (runner ?? _startProcess)(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
      runInShell: false,
    );

Future<void> _startProcess(
  String executable,
  List<String> arguments, {
  required String? workingDirectory,
  required bool runInShell,
}) async {
  // Win32 can start batch files through cmd.exe even with runInShell false.
  if (Platform.isWindows && !executable.toLowerCase().endsWith('.exe')) {
    throw const ProcessException(
        '', [], 'Quick Actions require a Windows executable');
  }
  await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: runInShell,
    mode: ProcessStartMode.detached,
  );
}
