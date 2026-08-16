import 'dart:async';
import 'dart:typed_data';

import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

/// Pluggable background workload driver used during latency measurements.
abstract interface class LoadProfile {
  String get name;
  String get description;

  /// Starts the concurrent background load against [session].
  Future<void> start(Session session);

  /// Stops background load generation and cleans up resources.
  Future<void> stop();
}

/// Factory and registry for available load profiles.
abstract final class LoadProfiles {
  static const String idle = 'idle';
  static const String clipboard = 'clipboard';

  static final Map<String, LoadProfile Function()> _registry =
      <String, LoadProfile Function()>{
    idle: () => const IdleLoadProfile(),
    clipboard: () => ClipboardLoadProfile(),
  };

  /// Names of all registered load profiles.
  static List<String> get available => _registry.keys.toList();

  /// Instantiates a load profile by name.
  ///
  /// Throws [ArgumentError] if [name] is not registered.
  static LoadProfile create(String name) {
    final factory = _registry[name.toLowerCase()];
    if (factory == null) {
      throw ArgumentError.value(
        name,
        'name',
        'Unknown load profile. Available: ${available.join(', ')}',
      );
    }
    return factory();
  }
}

/// Baseline profile: no concurrent background load.
final class IdleLoadProfile implements LoadProfile {
  const IdleLoadProfile();

  @override
  String get name => LoadProfiles.idle;

  @override
  String get description => 'Idle link with no concurrent traffic';

  @override
  Future<void> start(Session session) async {}

  @override
  Future<void> stop() async {}
}

/// Background load driver generating continuous ~5 MB clipboard transfers.
final class ClipboardLoadProfile implements LoadProfile {
  ClipboardLoadProfile({
    this.payloadSizeBytes = 5 * 1024 * 1024,
    this.interval = const Duration(milliseconds: 500),
  });

  /// Size of each synthetic clipboard payload in bytes (default ~5 MB).
  final int payloadSizeBytes;

  /// Interval between consecutive clipboard broadcasts.
  final Duration interval;

  Timer? _timer;
  bool _running = false;

  @override
  String get name => LoadProfiles.clipboard;

  @override
  String get description =>
      'Concurrent ${payloadSizeBytes ~/ (1024 * 1024)} MB clipboard transfers';

  @override
  Future<void> start(Session session) async {
    _running = true;
    final payload = Uint8List(payloadSizeBytes);
    for (var i = 0; i < payload.length; i++) {
      payload[i] = i & 0xFF;
    }

    var sequence = 1;
    _timer = Timer.periodic(interval, (_) async {
      if (!_running || session.state == SessionState.closed) return;
      try {
        final hash = Uint8List(16);
        for (var i = 0; i < 16; i++) {
          hash[i] = (sequence + i) & 0xFF;
        }

        final update = ClipboardUpdate(
          items: <ClipboardItem>[
            ClipboardItem(
              contentType: ClipboardContentType.imagePng,
              data: payload,
            ),
          ],
          contentHash: hash,
          originDeviceId: session.peerId.value,
          originSequence: sequence++,
        );
        await session.send(update);
      } on Object {
        // Suppress send errors if the session disconnects during testing
      }
    });
  }

  @override
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }
}
