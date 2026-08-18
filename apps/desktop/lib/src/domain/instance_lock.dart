import 'dart:convert';
import 'dart:io';

import 'package:rl_core/rl_core.dart';

/// Stops a second copy of the companion from starting beside the first.
///
/// ## Why this is needed at all
///
/// Two copies is not a cosmetic problem. Both advertise over Bonjour, so the
/// phone sees the same computer twice and picks one at random; both watch the
/// clipboard, so a copy on the phone arrives twice; both rewrite the login item.
/// The user sees a computer that behaves intermittently, with nothing on screen
/// saying why.
///
/// It used to be prevented by accident: the second copy could not bind port
/// 47811 and died with "could not listen on port 47811" — a message naming the
/// one thing the user cannot act on, from a window with no way out. Now that
/// the server falls back to any free port, that accident is gone and the
/// collision has to be handled deliberately.
///
/// ## How it decides
///
/// A file naming the port the running copy holds, and a bind attempt on that
/// port. Both are required. The file alone is not enough — it outlives a crash —
/// and a busy port alone is not enough either, because the port may belong to
/// something else entirely, and refusing to start because an unrelated program
/// is using a number is precisely the behaviour being removed.
///
/// The process id is recorded but not consulted. Checking it means `kill -0` or
/// `tasklist`, one more shell-out per launch, to answer a question the port has
/// already answered: a process that is alive but no longer listening is not
/// serving anybody, and this copy should take over from it.
final class InstanceLock {
  InstanceLock(this.file);

  final File file;

  final Log _log = Log.scoped('desktop.instance');

  /// Details of a copy that is already running, or null if this one may start.
  Future<RunningInstance?> otherInstance() async {
    // Not load-bearing: a missing file throws below and is caught into the same
    // answer. It is here so the very first launch — the common case — does not
    // log "could not read the instance lock", which reads like a fault and is
    // not one.
    if (!file.existsSync()) return null;

    final RunningInstance record;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) return null;
      final port = decoded['port'];
      if (port is! int) return null;
      record = RunningInstance(
        port: port,
        pid: decoded['pid'] is int ? decoded['pid']! as int : null,
        startedAt: DateTime.tryParse('${decoded['startedAt']}'),
      );
    } on Object catch (error) {
      // An unreadable lock is treated as no lock. Refusing to start because a
      // bookkeeping file is damaged would be a self-inflicted outage.
      _log.warn('could not read the instance lock', error: error);
      return null;
    }

    if (await _isFree(record.port)) {
      _log.info(
        'found a stale instance lock, taking over',
        fields: <String, Object?>{'port': record.port},
      );
      return null;
    }
    return record;
  }

  /// Records that this process holds [port].
  Future<void> claim({required int port}) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'pid': pid,
        'port': port,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  /// Removes the record, so the next launch does not have to probe a port.
  ///
  /// Best-effort by design: the lock is validated against a live port every
  /// time it is read, so one left behind by a crash costs a single failed bind
  /// and nothing else.
  Future<void> release() async {
    try {
      if (file.existsSync()) await file.delete();
    } on Object catch (error) {
      _log.warn('could not remove the instance lock', error: error);
    }
  }

  Future<bool> _isFree(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }
}

/// What the lock file says about the copy that is already running.
final class RunningInstance {
  const RunningInstance({required this.port, this.pid, this.startedAt});

  final int port;
  final int? pid;
  final DateTime? startedAt;
}
