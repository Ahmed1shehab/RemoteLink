import 'dart:async';
import 'dart:io';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'framed_connection.dart';
import 'handshake_driver.dart';
import 'session.dart';

/// Concurrent handshakes allowed before new connections are refused.
///
/// A handshake costs four X25519 operations, so an unauthenticated peer opening
/// connections in a loop is a cheap way to saturate a laptop's CPU. Capping
/// *in-flight handshakes* rather than total connections is the right knob:
/// established sessions are almost free, and the expensive window is the one
/// before we know who is calling.
const int kMaxConcurrentHandshakes = 8;

/// Default cap on simultaneously connected devices.
const int kMaxSessions = 16;

/// An accepted, authenticated peer.
final class ServerSession {
  ServerSession({
    required this.session,
    required this.handshake,
    required this.acceptedAt,
    required this.address,
  });

  final Session session;
  final HandshakeResult handshake;
  final DateTime acceptedAt;
  final String address;

  DeviceId get peerId => session.peerId;

  /// True while the peer is authenticated but not yet approved by the user.
  bool get awaitingPairing => session.state == SessionState.pairing;
}

/// Accepts connections and turns them into authenticated sessions.
final class RemoteLinkServer {
  RemoteLinkServer({
    required this.identity,
    required this.capabilities,
    required this.trustStore,
    required Clock clock,
    this.port = 47811,
    this.maxSessions = kMaxSessions,
  }) : _clock = clock;

  final DeviceIdentity identity;

  /// Capabilities offered to new sessions.
  ///
  /// Mutable because capability is not a static property of the build. On macOS
  /// the input backend only works once the user grants Accessibility, and that
  /// can happen at any moment while the server is already running. A `final`
  /// field here would freeze "no mouse, no keyboard" into every handshake until
  /// the app was restarted.
  Capabilities capabilities;

  final TrustStore trustStore;
  final int port;
  final int maxSessions;

  final Clock _clock;
  final Log _log = Log.scoped('transport.server');

  final StreamController<ServerSession> _accepted =
      StreamController<ServerSession>.broadcast();
  final StreamController<ServerSession> _ended =
      StreamController<ServerSession>.broadcast();

  final Map<String, ServerSession> _sessions = <String, ServerSession>{};
  final Map<String, StreamSubscription<SessionState>> _watchers =
      <String, StreamSubscription<SessionState>>{};

  ServerSocket? _socket;
  StreamSubscription<Socket>? _subscription;
  int _handshakesInFlight = 0;

  /// Newly authenticated sessions.
  Stream<ServerSession> get accepted => _accepted.stream;

  /// Sessions that have ended.
  Stream<ServerSession> get ended => _ended.stream;

  List<ServerSession> get sessions => _sessions.values.toList();

  int get sessionCount => _sessions.length;

  bool get isRunning => _socket != null;

  /// The port actually bound, which differs from [port] if that was in use.
  int get boundPort => _socket?.port ?? port;

  /// Starts listening.
  ///
  /// Binds to all interfaces because the whole point is to be reachable from
  /// the phone, which is on a different address than the desktop. Access
  /// control is the trust store's job, not the bind address's — binding to a
  /// single interface would break the moment the user switched from Ethernet to
  /// Wi-Fi.
  Future<void> start() async {
    if (_socket != null) return;

    try {
      _socket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        shared: false,
      );
    } on SocketException catch (e) {
      throw TransportError(
        'bind_failed',
        'could not listen on port $port',
        cause: e,
        retryable: false,
      );
    }

    _subscription = _socket!.listen(
      (socket) => unawaited(_onSocket(socket)),
      onError: (Object error, StackTrace stack) =>
          _log.warn('listener error', error: error, stackTrace: stack),
      cancelOnError: false,
    );

    _log.info('listening', fields: <String, Object?>{'port': boundPort});
  }

  Future<void> _onSocket(Socket socket) async {
    final address = socket.remoteAddress.address;

    if (_handshakesInFlight >= kMaxConcurrentHandshakes) {
      _log.warn(
        'refusing connection: handshake queue full',
        fields: <String, Object?>{'address': address},
      );
      socket.destroy();
      return;
    }
    if (_sessions.length >= maxSessions) {
      _log.warn(
        'refusing connection: session limit reached',
        fields: <String, Object?>{'address': address},
      );
      socket.destroy();
      return;
    }

    _handshakesInFlight++;
    final connection = FramedConnection.wrap(socket);

    try {
      final (session, result) = await HandshakeDriver.runServer(
        connection: connection,
        identity: identity,
        capabilities: capabilities,
        clock: _clock,
        lookupPeer: trustStore.findByPublicKey,
      );

      await _register(
        ServerSession(
          session: session,
          handshake: result,
          acceptedAt: _clock.now(),
          address: address,
        ),
      );
    } on SecurityError catch (e) {
      // Expected in normal operation: an unpaired device, a revoked one, or a
      // stale client. Logged at warn, not error, and never surfaced as a crash.
      _log.warn(
        'handshake rejected',
        fields: <String, Object?>{'address': address, 'code': e.code},
      );
      connection.destroy();
    } on TransportError catch (e) {
      _log.debug(() => 'handshake aborted from $address: ${e.code}');
      connection.destroy();
    } finally {
      _handshakesInFlight--;
    }
  }

  Future<void> _register(ServerSession accepted) async {
    // One session per device. A phone that reconnects after a Wi-Fi drop would
    // otherwise accumulate ghost sessions that still hold input state — leaving
    // a modifier key latched from a connection that no longer exists.
    final existing = _sessions[accepted.peerId.value];
    if (existing != null) {
      _log.info(
        'replacing an earlier session for the same device',
        fields: <String, Object?>{'peer': accepted.peerId.value},
      );
      await existing.session.close(reason: CloseReason.replaced);
      await _unregister(accepted.peerId);
    }

    _sessions[accepted.peerId.value] = accepted;
    _watchers[accepted.peerId.value] = accepted.session.stateChanges.listen(
      (state) {
        if (state == SessionState.closed) {
          unawaited(_onSessionClosed(accepted));
        }
      },
      onDone: () => unawaited(_onSessionClosed(accepted)),
      cancelOnError: false,
    );

    if (!_accepted.isClosed) _accepted.add(accepted);
  }

  Future<void> _onSessionClosed(ServerSession session) async {
    if (_sessions[session.peerId.value] != session) return;
    await _unregister(session.peerId);
    if (!_ended.isClosed) _ended.add(session);
  }

  Future<void> _unregister(DeviceId peerId) async {
    _sessions.remove(peerId.value);
    await _watchers.remove(peerId.value)?.cancel();
  }

  /// Closes the session belonging to [peerId], if any.
  Future<void> disconnectPeer(
    DeviceId peerId, {
    CloseReason reason = CloseReason.userRequested,
  }) async {
    final session = _sessions[peerId.value];
    if (session == null) return;
    await session.session.close(reason: reason);
    await _unregister(peerId);
  }

  /// Revokes a device and drops it immediately.
  ///
  /// Revoking without disconnecting would leave a device the user just removed
  /// still controlling their computer until it happened to reconnect — which is
  /// the opposite of what "Forget this device" means.
  Future<void> revokePeer(DeviceId peerId) async {
    await trustStore.revoke(peerId);
    await disconnectPeer(peerId, reason: CloseReason.revoked);
  }

  /// Sends [message] to every established session.
  Future<void> broadcast(Message message) async {
    for (final entry in _sessions.values.toList()) {
      if (!entry.session.isEstablished) continue;
      try {
        await entry.session.send(message);
      } on TransportError {
        // The session is already tearing down; its watcher will clean up.
      }
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;

    for (final session in _sessions.values.toList()) {
      await session.session.close(reason: CloseReason.shuttingDown);
    }
    for (final watcher in _watchers.values) {
      await watcher.cancel();
    }
    _sessions.clear();
    _watchers.clear();

    await _accepted.close();
    await _ended.close();
  }
}
