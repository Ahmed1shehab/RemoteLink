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
    this.deviceId,
    this.serverPublicKey,
    this.displayName,
  });

  final String host;
  final int port;

  /// The identity this client expects to find, when it already knows it.
  ///
  /// Null for a manual connection by address: the peer's identity is genuinely
  /// unknown until the handshake proves it. Modelling that as nullable rather
  /// than inventing a placeholder keeps the "we have not verified anything yet"
  /// state visible in the type.
  final DeviceId? deviceId;

  /// The server's static key from the trust store, when this is a reconnect.
  ///
  /// Its presence turns the handshake from trust-on-first-use into strict
  /// verification, so a substituted server is rejected rather than prompting
  /// the user to re-pair.
  final Uint8List? serverPublicKey;

  final String? displayName;

  bool get isTrusted => serverPublicKey != null;

  @override
  String toString() =>
      '${displayName ?? deviceId?.short ?? 'unknown'} @ $host:$port';
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
  ProtocolErrorCode? _failureCode;
  int _connectionAttemptCount = 0;
  int _attempt = 0;
  bool _stopRequested = false;
  Completer<void>? _backoffTimer;

  /// Callers parked in [waitUntilConnected].
  final List<Completer<Session>> _readyWaiters = <Completer<Session>>[];

  ClientState get state => _state;

  /// Protocol reason for the current terminal failure, when supplied by the
  /// peer. Cleared when [connect] starts a new connection lifecycle.
  ProtocolErrorCode? get failureCode => _failureCode;

  ConnectionTarget? get target => _target;

  /// Number of socket connection attempts made during this client's lifetime.
  @visibleForTesting
  int get connectionAttemptCount => _connectionAttemptCount;

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

  /// The tier this device was last granted, or null before any grant arrives.
  ///
  /// Retained so a screen built after the grant can still find out. A UI that
  /// only watches [messages] sees nothing until the *next* grant, which for a
  /// device whose tier never changes is never.
  PermissionTier? get grantedTier => _grantedTier;

  PermissionTier? _grantedTier;

  bool get isConnected => _state == ClientState.connected;

  /// Connects to [target] and keeps the connection alive until [disconnect].
  ///
  /// Returns as soon as the attempt is *scheduled*, not when it succeeds. That
  /// is deliberate: the supervisor may need several retries, and a caller that
  /// blocked until the first success could not show a "connecting" state or
  /// offer a cancel button. Use [waitUntilConnected] when you actually need a
  /// live session.
  Future<void> connect(ConnectionTarget target) async {
    await disconnect();
    _stopRequested = false;
    _failureCode = null;
    _target = target;
    _attempt = 0;
    unawaited(_runSupervisor());
  }

  /// Points the supervisor at a new address for the *same* computer.
  ///
  /// The reconnect loop reads [_target] afresh on every pass, so this takes
  /// effect on the next attempt without disturbing a live session or resetting
  /// the backoff.
  ///
  /// It exists because a remembered address goes stale and nothing else here
  /// notices. A laptop takes a new DHCP lease and the supervisor keeps dialling
  /// the old one — observed on a real device as sixteen attempts over two
  /// minutes to an address nothing was listening on, while the machine was
  /// announcing its real address over Bonjour the whole time. Retrying harder
  /// cannot fix a wrong address; only a better one can.
  ///
  /// Refuses a target for a different computer. Redirecting a live supervisor
  /// to another machine on the strength of a discovery beacon would let anyone
  /// on the network aim this phone wherever they liked; the identity is what
  /// makes the new address safe to believe, and it is still verified by the
  /// handshake afterwards.
  bool retarget(ConnectionTarget target) {
    final current = _target;
    if (current == null) return false;
    if (current.deviceId == null || current.deviceId != target.deviceId) {
      return false;
    }
    if (current.host == target.host && current.port == target.port) {
      return false;
    }

    _log.info(
      'the computer moved; aiming at its new address',
      fields: <String, Object?>{
        'was': '${current.host}:${current.port}',
        'now': '${target.host}:${target.port}',
      },
    );
    _target = ConnectionTarget(
      host: target.host,
      port: target.port,
      deviceId: current.deviceId,
      // Kept from the original, never taken from the new target: the stored key
      // is what turns trust-on-first-use into strict verification, and letting
      // a discovery beacon replace it would undo exactly that.
      serverPublicKey: current.serverPublicKey,
      displayName: current.displayName,
    );
    return true;
  }

  /// Completes once a session is established, or throws if it cannot be.
  ///
  /// Exists because [connect] returning does not mean the handshake finished —
  /// and the mistake is a subtle one, because the *server* side completes its
  /// half first. Code that watches for the server to accept and then
  /// immediately sends will find `session` still null on the client. This
  /// checks the live session before parking a waiter, so there is no window
  /// between the check and the subscription for the event to be missed.
  Future<Session> waitUntilConnected({
    Duration timeout = const Duration(seconds: 15),
  }) {
    final existing = _session;
    if (existing != null && existing.state != SessionState.closed) {
      return Future<Session>.value(existing);
    }
    if (_state == ClientState.failed) {
      return Future<Session>.error(
        const TransportError(
          'connect_failed',
          'the client stopped for a reason retrying cannot fix',
          retryable: false,
        ),
      );
    }

    final waiter = Completer<Session>();
    _readyWaiters.add(waiter);
    return waiter.future.timeout(timeout);
  }

  void _resolveWaiters(Session session) {
    if (_readyWaiters.isEmpty) return;
    final waiting = List<Completer<Session>>.from(_readyWaiters);
    _readyWaiters.clear();
    for (final waiter in waiting) {
      if (!waiter.isCompleted) waiter.complete(session);
    }
  }

  void _failWaiters(Object error) {
    if (_readyWaiters.isEmpty) return;
    final waiting = List<Completer<Session>>.from(_readyWaiters);
    _readyWaiters.clear();
    for (final waiter in waiting) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
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
        _failWaiters(e);
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
    _connectionAttemptCount++;
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
    _resolveWaiters(session);

    _messageSubscription = session.messages.listen(
      (message) {
        // Recorded here, on the way past, rather than left to whoever happens
        // to be listening. `_messages` is a broadcast stream, so anything sent
        // before a subscriber exists is gone — and the desktop sends the tier
        // grant the instant a trusted session is established, long before any
        // screen is built to receive it. Every UI that asked "what tier am I?"
        // therefore got null and kept it forever.
        if (message case PermissionGrant(:final tier)) _grantedTier = tier;
        if (message case ErrorMessage(:final code) when !code.isRetryable) {
          _failureCode = code;
          _stopRequested = true;
          _setState(ClientState.failed);
          _failWaiters(
            TransportError(
              'protocol_${code.name}',
              'peer reported a terminal protocol error',
              retryable: false,
            ),
          );
          unawaited(session.close(reason: CloseReason.protocolError));
        }
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
      // Every screen reads `state`, not `session`. Leaving it on `connected`
      // once the supervisor has given up is what turns a dead link into a
      // send that fails at the last moment with "not connected to peer",
      // while the UI still offers a send button.
      _setState(
        reason == CloseReason.userRequested
            ? ClientState.idle
            : ClientState.failed,
      );
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

    // A deliberate disconnect must not leave a caller parked forever waiting
    // for a session that will never arrive.
    _failWaiters(
      const TransportError(
        'disconnected',
        'the client was disconnected before a session was established',
        retryable: false,
      ),
    );
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
