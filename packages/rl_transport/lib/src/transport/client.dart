import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'framed_connection.dart';
import 'handshake_driver.dart';
import 'reconnect.dart';
import 'session.dart';

/// Where a client stands with respect to one computer.
enum ClientState {
  /// Not trying to connect.
  idle,

  /// A connection attempt is in flight.
  connecting,

  /// Connected; waiting for the user to complete pairing.
  pairing,

  /// Connected and usable.
  connected,

  /// Disconnected and waiting out a backoff interval.
  reconnecting,

  /// Stopped for a reason retrying cannot fix.
  failed,
}

/// Target a client connects to.
@immutable
final class ConnectionTarget {
  const ConnectionTarget({
    required this.host,
    required this.port,
    required this.deviceId,
    this.serverPublicKey,
    this.displayName,
  });

  final String host;
  final int port;
  final DeviceId deviceId;

  /// The server's static key from the trust store, when this is a reconnect.
  ///
  /// Its presence turns the handshake from trust-on-first-use into strict
  /// verification, so a substituted server is rejected rather than prompting
  /// the user to re-pair.
  final Uint8List? serverPublicKey;

  final String? displayName;

  bool get isTrusted => serverPublicKey != null;

  @override
  String toString() => '${displayName ?? deviceId.short} @ $host:$port';
}

/// Maintains a connection to one computer, reconnecting as needed.
///
/// The supervisor exists because "it reconnects automatically" is the single
/// most load-bearing promise in the product. Phones roam between access points,
/// sleep their radios, and lose the network every time the user walks past a
/// microwave. Every one of those must be invisible.
final class RemoteLinkClient {
  RemoteLinkClient({
    required this.identity,
    required this.capabilities,
    required Clock clock,
    this.backoff = BackoffPolicy.responsive,
    Random? random,
  })  : _clock = clock,
        _random = random ?? Random();

  final DeviceIdentity identity;
  final Capabilities capabilities;
  final BackoffPolicy backoff;

  final Clock _clock;
  final Random _random;
  final Log _log = Log.scoped('transport.client');

  final StreamController<ClientState> _states =
      StreamController<ClientState>.broadcast();
  final StreamController<Session> _sessions =
      StreamController<Session>.broadcast();
  final StreamController<Message> _messages =
      StreamController<Message>.broadcast();

  ConnectionTarget? _target;
  Session? _session;
  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<SessionState>? _sessionStateSubscription;

  ClientState _state = ClientState.idle;
  int _attempt = 0;
  bool _stopRequested = false;
  Completer<void>? _backoffTimer;

  ClientState get state => _state;

  Stream<ClientState> get states => _states.stream;

  /// Emits each newly established session, so callers can re-subscribe to
  /// per-session streams after a reconnect.
  Stream<Session> get sessions => _sessions.stream;

  /// Application messages, flattened across reconnects.
  ///
  /// Callers listen once and keep listening. Making them re-subscribe on every
  /// reconnect would be a permanent source of "it stopped working after the
  /// Wi-Fi blipped" bugs.
  Stream<Message> get messages => _messages.stream;

  Session? get session => _session;

  bool get isConnected => _state == ClientState.connected;

  /// Connects to [target] and keeps the connection alive until [disconnect].
  Future<void> connect(ConnectionTarget target) async {
    await disconnect();
    _stopRequested = false;
    _target = target;
    _attempt = 0;
    unawaited(_runSupervisor());
  }

  Future<void> _runSupervisor() async {
    while (!_stopRequested) {
      final target = _target;
      if (target == null) return;

      if (_attempt > 0) {
        final delay = backoff.delayFor(_attempt, _random);
        _setState(ClientState.reconnecting);
        _log.info(
          'reconnecting',
          fields: <String, Object?>{
            'attempt': _attempt,
            'delayMs': delay.inMilliseconds,
            'target': target.toString(),
          },
        );

        final timer = Completer<void>();
        _backoffTimer = timer;
        unawaited(
          _clock.delay(delay).then((_) {
            if (!timer.isCompleted) timer.complete();
          }),
        );
        await timer.future;
        _backoffTimer = null;
        if (_stopRequested) return;
      }

      _setState(ClientState.connecting);
      try {
        await _attemptConnection(target);
        // _attemptConnection returns when the session ends. If the user asked
        // to stop, honour that; otherwise loop and reconnect.
        if (_stopRequested) return;
        _attempt++;
      } on SecurityError catch (e) {
        // Cryptographic failures are not transient. Retrying a key mismatch
        // just burns battery and hides a real problem from the user.
        _log.error('connection failed permanently', error: e);
        _setState(ClientState.failed);
        return;
      } on TransportError catch (e) {
        if (!e.retryable) {
          _log.error('connection failed permanently', error: e);
          _setState(ClientState.failed);
          return;
        }
        _log.warn('connection attempt failed', error: e);
        _attempt++;
      }
    }
  }

  Future<void> _attemptConnection(ConnectionTarget target) async {
    final connection = await FramedConnection.connect(target.host, target.port);

    final session = await HandshakeDriver.runClient(
      connection: connection,
      identity: identity,
      capabilities: capabilities,
      clock: _clock,
      expectedServerKey: target.serverPublicKey,
      expectedServerId: target.isTrusted ? target.deviceId : null,
    );

    _session = session;
    _attempt = 0;
    _setState(
      session.state == SessionState.pairing
          ? ClientState.pairing
          : ClientState.connected,
    );

    if (!_sessions.isClosed) _sessions.add(session);

    _messageSubscription = session.messages.listen(
      (message) {
        if (!_messages.isClosed) _messages.add(message);
      },
      cancelOnError: false,
    );

    final ended = Completer<void>();
    _sessionStateSubscription = session.stateChanges.listen(
      (state) {
        switch (state) {
          case SessionState.established:
            _setState(ClientState.connected);
          case SessionState.pairing:
            _setState(ClientState.pairing);
          case SessionState.closed:
            if (!ended.isCompleted) ended.complete();
          case SessionState.handshaking:
            break;
        }
      },
      onDone: () {
        if (!ended.isCompleted) ended.complete();
      },
      cancelOnError: false,
    );

    await ended.future;

    // A deliberate disconnect must not be undone by the supervisor helpfully
    // reconnecting. The close reason is what distinguishes "the user quit" from
    // "the Wi-Fi dropped".
    final reason = session.closeReason;
    if (reason != null && !reason.shouldReconnect) {
      _stopRequested = true;
    }

    await _detachSession();
  }

  Future<void> _detachSession() async {
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _sessionStateSubscription?.cancel();
    _sessionStateSubscription = null;
    _session = null;
  }

  /// Sends a message if a session is live.
  ///
  /// Returns `false` rather than throwing when disconnected: the caller is
  /// usually a gesture handler firing at 120 Hz, and an exception per frame
  /// during a brief outage would be both noisy and useless.
  Future<bool> send(Message message) async {
    final session = _session;
    if (session == null || session.state == SessionState.closed) return false;
    try {
      await session.send(message);
      return true;
    } on TransportError {
      return false;
    }
  }

  /// Stops and prevents further reconnection.
  Future<void> disconnect({
    CloseReason reason = CloseReason.userRequested,
  }) async {
    _stopRequested = true;

    final timer = _backoffTimer;
    if (timer != null && !timer.isCompleted) timer.complete();
    _backoffTimer = null;

    final session = _session;
    if (session != null) await session.close(reason: reason);

    await _detachSession();
    _target = null;
    _setState(ClientState.idle);
  }

  void _setState(ClientState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> dispose() async {
    await disconnect();
    await _states.close();
    await _sessions.close();
    await _messages.close();
  }
}
