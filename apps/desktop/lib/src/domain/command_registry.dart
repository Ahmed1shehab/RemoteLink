import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';

final class RegisteredCommand {
  RegisteredCommand._({
    required this.id,
    required this.name,
    required this.executable,
    required List<String> arguments,
    required this.workingDirectory,
    required this.minimumTier,
    required this.enabled,
  }) : arguments = List.unmodifiable(arguments);

  final String id;
  final String name;
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final PermissionTier minimumTier;
  final bool enabled;

  Map<String, Object?> _toJson() => {
        'id': id,
        'name': name,
        'executable': executable,
        'arguments': arguments,
        'workingDirectory': workingDirectory,
        'minimumTier': minimumTier.name,
        'enabled': enabled,
      };

  static RegisteredCommand _fromJson(Map<String, Object?> json) =>
      RegisteredCommand._(
        id: json['id'] as String,
        name: json['name'] as String,
        executable: json['executable'] as String,
        arguments: (json['arguments'] as List<Object?>).cast<String>(),
        workingDirectory: json['workingDirectory'] as String?,
        minimumTier:
            PermissionTier.values.byName(json['minimumTier'] as String),
        enabled: json['enabled'] as bool,
      );
}

final class CommandRegistry {
  CommandRegistry._(this._file, List<int> secret)
      : _secret = List<int>.unmodifiable(secret);

  static const fileName = 'command_registry.json';
  static final _random = Random.secure();
  final File _file;
  final List<int> _secret;
  final _changes = StreamController<void>.broadcast();
  Future<void> _writeTail = Future<void>.value();
  Map<String, RegisteredCommand> _commands = {};
  bool _loadWarning = false;

  List<RegisteredCommand> get commands => List.unmodifiable(_commands.values);
  Stream<void> get changes => _changes.stream;
  bool get loadWarning => _loadWarning;

  Future<void> dispose() => _changes.close();

  static Future<CommandRegistry> open({
    required Directory directory,
    required List<int> secret,
  }) async {
    if (secret.length < Primitives.secretLength) {
      throw ArgumentError('Registry secret must have at least 32 bytes');
    }
    final registry = CommandRegistry._(
      File('${directory.path}${Platform.pathSeparator}$fileName'),
      secret,
    );
    await registry._load();
    return registry;
  }

  Future<void> _load() async {
    try {
      if (!_file.existsSync()) return;
      final envelope =
          jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      final payload = envelope['payload'] as String;
      final tag = base64Decode(envelope['tag'] as String);
      final expected =
          await Primitives.mac(key: _secret, data: utf8.encode(payload));
      if (!Primitives.constantTimeEquals(tag, expected)) {
        throw const FormatException('Registry tag mismatch');
      }
      final entries = jsonDecode(payload) as List<Object?>;
      _commands = {
        for (final json in entries)
          (json as Map<String, Object?>)['id'] as String:
              RegisteredCommand._fromJson(json),
      };
    } on Object {
      _loadWarning = true;
      Log.scoped('desktop.command_registry')
          .warn('command registry could not be verified');
    }
  }

  Future<RegisteredCommand> add({
    required String name,
    required String executable,
    List<String> arguments = const [],
    String? workingDirectory,
    PermissionTier minimumTier = PermissionTier.extended,
  }) {
    _validate(name, executable, arguments, workingDirectory);
    final id = base64UrlEncode(List.generate(18, (_) => _random.nextInt(256)));
    final entry = RegisteredCommand._(
      id: id,
      name: name.trim(),
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      minimumTier: minimumTier,
      enabled: false,
    );
    return _mutate((commands) {
      if (commands.length >= CommandCatalog.maxEntries) {
        throw StateError('Command registry is full');
      }
      if (commands.containsKey(id)) throw StateError('Duplicate command ID');
      commands[id] = entry;
      return entry;
    });
  }

  ({RegisteredCommand? command, CommandOutcome? refusal}) resolve(
    String id,
    PermissionTier tier,
  ) {
    final command = _commands[id];
    if (command == null) {
      return (command: null, refusal: CommandOutcome.refusedUnknown);
    }
    if (!command.enabled) {
      return (command: null, refusal: CommandOutcome.refusedDisabled);
    }
    if (!tier.canRunCommands ||
        tier.wireValue < command.minimumTier.wireValue) {
      return (command: null, refusal: CommandOutcome.refusedTier);
    }
    return (command: command, refusal: null);
  }

  Future<void> setEnabled(String id, bool enabled) => _mutate((commands) {
        final command = commands[id];
        if (command == null) throw StateError('Unknown action');
        commands[id] = RegisteredCommand._(
          id: id,
          name: command.name,
          executable: command.executable,
          arguments: command.arguments,
          workingDirectory: command.workingDirectory,
          minimumTier: command.minimumTier,
          enabled: enabled,
        );
      });

  Future<void> update(
    String id, {
    required String name,
    required String executable,
    required List<String> arguments,
    required String? workingDirectory,
    required PermissionTier minimumTier,
  }) {
    _validate(name, executable, arguments, workingDirectory);
    final replacement = RegisteredCommand._(
      id: id,
      name: name.trim(),
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      minimumTier: minimumTier,
      // An edit can change what a previously shared action executes.
      enabled: false,
    );
    return _mutate((commands) {
      if (!commands.containsKey(id)) throw StateError('Unknown action');
      commands[id] = replacement;
    });
  }

  Future<void> remove(String id) => _mutate((commands) {
        commands.remove(id);
      });

  static void _validate(
    String name,
    String executable,
    List<String> arguments,
    String? workingDirectory,
  ) {
    if (name.trim().isEmpty ||
        utf8.encode(name.trim()).length > CommandCatalog.maxNameBytes) {
      throw ArgumentError('Invalid action name');
    }
    if (!_isAbsolute(executable) ||
        (workingDirectory != null && !_isAbsolute(workingDirectory)) ||
        [
          executable,
          ...arguments,
          if (workingDirectory != null) workingDirectory
        ].any((value) => value.contains('\u0000'))) {
      throw ArgumentError('Invalid executable, arguments or working directory');
    }
  }

  static bool _isAbsolute(String path) => Platform.isWindows
      ? RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path) || path.startsWith(r'\\')
      : path.startsWith('/');

  Future<T> _mutate<T>(T Function(Map<String, RegisteredCommand>) change) {
    if (_changes.isClosed) {
      return Future<T>.error(StateError('Command registry is closed'));
    }
    // Commit each complete snapshot before publishing it. Concurrent edits
    // then see the preceding committed edit, and a failed write changes neither
    // what can be run nor what is sent to the phone.
    final write = _writeTail.then((_) async {
      final next = Map<String, RegisteredCommand>.of(_commands);
      final result = change(next);
      final payload =
          jsonEncode(next.values.map((entry) => entry._toJson()).toList());
      final tag =
          await Primitives.mac(key: _secret, data: utf8.encode(payload));
      await _file.parent.create(recursive: true);
      final staging = await _file.parent.createTemp('command-registry-');
      try {
        final temporary =
            File('${staging.path}${Platform.pathSeparator}$fileName');
        await temporary.writeAsString(
          jsonEncode({'payload': payload, 'tag': base64Encode(tag)}),
          flush: true,
        );
        await temporary.rename(_file.path);
        _commands = next;
        _loadWarning = false;
        if (!_changes.isClosed) _changes.add(null);
      } finally {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // Cleanup does not change whether the atomic replacement succeeded.
        }
      }
      return result;
    });
    _writeTail =
        write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }
}
