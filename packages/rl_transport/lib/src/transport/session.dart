import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'framed_connection.dart';

/// How often a keepalive goes out.
///
/// One second, tuned against the sub-two-second reconnect requirement: a
/// failure has to be *detected* before reconnection can even start, so the
/// detection budget is roughly half the total.
const Duration kHeartbeatInterval = Duration(seconds: 1);

/// Missed heartbeats before the peer is declared gone.
///
/// Two and a half seconds of silence. Lower would false-positive when a phone's
/// radio power-saves briefly; higher would blow the reconnect budget.
const Duration kHeartbeatTimeout = Duration(milliseconds: 2500);

/// Pending lossy messages tolerated before coalescing kicks in.
///
/// Reached only when the network stalls. At that point the newest cursor
/// position is the only one that matters, so older deltas are folded into it
/// rather than queued — the cursor arrives where the finger is instead of
/// replaying the whole gesture late.
const int kCoalesceThreshold = 4;

/// Lifecycle of a session.
enum SessionState {
  /// Socket open, handshake not finished. No application data is dispatched.
  handshaking,

  /// Handshake done, but the peer is unpaired and awaiting user confirmation.
  pairing,

  /// Fully usable.
  established,

  /// Closing or closed.
  closed,
}

/// Rolling connection health, surfaced in the UI.
@immutable
final class ConnectionQuality {
  const ConnectionQuality({
    required this.roundTripMicros,
    required this.jitterMicros,
    required this.sentMessages,
    required this.receivedMessages,
    required this.sentBytes,
    required this.receivedBytes,
    required this.missedHeartbeats,
  });

  static const ConnectionQuality unknown = ConnectionQuality(
    roundTripMicros: 0,
    jitterMicros: 0,
    sentMessages: 0,
    receivedMessages: 0,
    sentBytes: 0,
    receivedBytes: 0,
    missedHeartbeats: 0,
  );

  final int roundTripMicros;

  /// Mean deviation of recent RTT samples.
  ///
  /// Reported alongside latency because they mean different things to the user:
  /// steady 30 ms feels fine, while 5 ms averaging with occasional 80 ms spikes
  /// feels broken. Only jitter distinguishes them.
  final int jitterMicros;

  final int sentMessages;
  final int receivedMessages;
  final int sentBytes;
  final int receivedBytes;
  final int missedHeartbeats;

  double get roundTripMillis => roundTripMicros / 1000.0;

  /// Coarse quality bucket for a signal-strength style indicator.
  ///
  /// Thresholds come from perception, not from round numbers: under 20 ms a
  /// remote cursor is indistinguishable from a local one, and past 150 ms
  /// pointing becomes a guessing game.
  int get bars => switch (roundTripMicros) {
        0 => 0,
        < 20000 => 4,
        < 60000 => 3,
        < 150000 => 2,
        _ => 1,
      };
}

/// An authenticated, encrypted, message-oriented connection to one peer.
///
/// Everything above this layer deals in [Message] objects and never sees a
/// byte, a nonce, or a socket. Everything below deals in bytes and never sees a
/// message type. That split is what lets the protocol be tested without I/O and
/// the transport be tested without cryptography.
final class Session {
  Session({
    required FramedConnection connection,
    required SessionKeys keys,
    required Clock clock,
    required this.peerId,
    required this.peerStaticPublicKey,
    required this.shortAuthenticationString,
    required this.capabilities,
    required this.isServer,
    bool requiresPairing = false,
    List<Uint8List> initialRecords = const <Uint8List>[],
  })  : _connection = connection,
        _keys = keys,
        _clock = clock,
        _codec = MessageCodec(clock: clock),
        _state =
            requiresPairing ? SessionState.pairing : SessionState.established {
    // The handlers are async, but `listen` expects void callbacks. Wrapping in
    // `unawaited` states that the fire-and-forget is intentional rather than an
    // accidentally dropped Future — the analyzer treats those as errors here.
    // Records are chained rather than each handled independently. Decryption is
    // asynchronous, so without this two records arriving in one event-loop turn
    // could finish out of order and be dispatched out of order — a mouse-up
    // delivered before its mouse-down, which the desktop would apply literally.
    for (final record in initialRecords) {
      _enqueueRecord(record);
    }
    _subscription = _connection.records.listen(
      _enqueueRecord,
      onError: (Object error, StackTrace stack) =>
          unawaited(_onTransportError(error, stack)),
      // TCP may deliver the final records and EOF in the same event-loop turn.
      // Drain records already handed to us before disposing the receive key,
      // or a terminal error immediately followed by close can be lost.
      onDone: () => unawaited(
        _readChain.then((_) => _teardown(CloseReason.shuttingDown)),
      ),
      cancelOnError: false,
    );
    _startHeartbeat();
  }

  void _enqueueRecord(Uint8List record) {
    _readChain = _readChain.then((_) => _onRecord(record)).then((_) {},
        onError: (Object error, StackTrace stack) {
      _log.error('record handling failed', error: error, stackTrace: stack);
    });
  }

  final FramedConnection _connection;
  final SessionKeys _keys;
  final Clock _clock;
  final MessageCodec _codec;

  final DeviceId peerId;

  /// The peer's long-term public key, as proven during the handshake.
  ///
  /// This — not anything the peer asserted about itself, and not the truncated
  /// fingerprint from the discovery beacon — is what a trust record must store.
  /// The beacon fingerprint is 8 bytes and exists only to pre-filter the device
  /// list; storing it as the trust key would mean accepting any device that
  /// could produce a matching 64-bit prefix.
  final Uint8List peerStaticPublicKey;

  /// Six digits derived from the handshake transcript.
  ///
  /// Shown during first-time pairing so the user can compare it against the
  /// other device's screen. Identical on both ends if and only if no
  /// machine-in-the-middle is relaying the connection.
  final String shortAuthenticationString;

  final Capabilities capabilities;

  /// True on the desktop. Determines which direction key is used for sending.
  final bool isServer;

  final Log _log = Log.scoped('transport.session');

  late final StreamSubscription<Uint8List> _subscription;

  final StreamController<Message> _messages =
      StreamController<Message>.broadcast();
  final StreamController<SessionState> _stateChanges =
      StreamController<SessionState>.broadcast();
  final StreamController<ConnectionQuality> _quality =
      StreamController<ConnectionQuality>.broadcast();

  /// Receive-side nonce counter.
  ///
  /// Implicit rather than transmitted: TCP delivers in order, so both sides
  /// count the same records. Sending it would waste eight bytes per frame and
  /// give an attacker a field to play with.
  int _receiveCounter = 0;

  /// Serialises inbound record handling. See the constructor for why.
  Future<void> _readChain = Future<void>.value();

  Timer? _heartbeat;
  int _lastPingMicros = 0;
  int _lastPongMicros = 0;
  int _missedHeartbeats = 0;

  final List<int> _rttSamples = <int>[];
  int _sentMessages = 0;
  int _receivedMessages = 0;
  int _sentBytes = 0;
  int _receivedBytes = 0;

  /// Lossy messages waiting to go out, keyed by type for coalescing.
  final Map<MessageType, Message> _pendingLossy = <MessageType, Message>{};
  final Map<int, Completer<void>> _pendingAcknowledgements =
      <int, Completer<void>>{};
  bool _flushScheduled = false;

  SessionState _state;
  CloseReason? _closeReason;

  /// Decoded inbound messages. Handshake traffic never appears here.
  Stream<Message> get messages => _messages.stream;

  Stream<SessionState> get stateChanges => _stateChanges.stream;

  /// Emitted once per heartbeat round trip.
  Stream<ConnectionQuality> get quality => _quality.stream;

  SessionState get state => _state;

  CloseReason? get closeReason => _closeReason;

  bool get isEstablished => _state == SessionState.established;

  String get remoteAddress => _connection.remoteAddress;

  /// A defensive copy of the handshake exporter for session-bound features.
  Uint8List get exporterSecret => Uint8List.fromList(_keys.exporterSecret);

  /// Snapshot of current health.
  ConnectionQuality get currentQuality => ConnectionQuality(
        roundTripMicros: _medianRtt(),
        jitterMicros: _jitter(),
        sentMessages: _sentMessages,
        receivedMessages: _receivedMessages,
        sentBytes: _sentBytes,
        receivedBytes: _receivedBytes,
        missedHeartbeats: _missedHeartbeats,
      );

  /// Sends [message].
  ///
  /// Lossy messages are buffered for a microtask and coalesced when the queue
  /// is backing up; everything else goes out immediately. The distinction is
  /// declared once on [MessageType.isLossy] rather than decided here, so adding
  /// a message type forces the author to state which it is.
  Future<void> send(Message message, {bool requireAck = false}) async {
    if (_state == SessionState.closed) {
      throw const TransportError('session_closed', 'session is closed');
    }

    if (message.type.isLossy && !requireAck) {
      _enqueueLossy(message);
      return;
    }
    await _writeNow(message, requireAck: requireAck);
  }

  /// Sends a reliable application message and waits for the peer's frame ack.
  Future<void> sendAcknowledged(
    Message message, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_state == SessionState.closed) {
      throw const TransportError('session_closed', 'session is closed');
    }
    final acknowledged = Completer<void>();
    // Attach an error handler immediately. A transport failure can tear the
    // session down while the write itself is still being awaited.
    unawaited(acknowledged.future.catchError((Object _) {}));
    int? sequence;
    final queued = _writeChain.then((_) async {
      final frame = _codec.encode(message, requireAck: true);
      sequence = frame.sequence;
      _pendingAcknowledgements[frame.sequence] = acknowledged;
      await _performFrameWrite(frame);
    });
    _writeChain = queued.then((_) {}, onError: (Object _) {});
    try {
      await queued;
      await acknowledged.future.timeout(timeout);
    } on TimeoutException catch (error) {
      throw TransportError(
        'ack_timeout',
        'peer did not acknowledge ${message.type.name}',
        cause: error,
      );
    } finally {
      if (sequence case final value?) {
        _pendingAcknowledgements.remove(value);
      }
    }
  }

  void _enqueueLossy(Message message) {
    final existing = _pendingLossy[message.type];
    _pendingLossy[message.type] = switch ((existing, message)) {
      // Relative deltas sum exactly, so folding them is not an approximation —
      // the cursor ends up in precisely the same place.
      (final MouseMove a, final MouseMove b) => a.merge(b),
      (final MouseScroll a, final MouseScroll b) => a.merge(b),
      // Everything else lossy is a snapshot; the newest one wins.
      _ => message,
    };

    if (_pendingLossy.length >= kCoalesceThreshold) {
      unawaited(_flushLossy());
      return;
    }
    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(() => unawaited(_flushLossy()));
    }
  }

  Future<void> _flushLossy() async {
    _flushScheduled = false;
    if (_pendingLossy.isEmpty) return;

    final batch = _pendingLossy.values.toList();
    _pendingLossy.clear();
    for (final message in batch) {
      if (_state == SessionState.closed) return;
      await _writeNow(message, requireAck: false);
    }
  }

  /// Serialises writes so that sealing and sending stay in the same order.
  ///
  /// This is load-bearing, not tidiness. `seal` is asynchronous, so the nonce
  /// is allocated before the `await` and the socket write happens after it. Two
  /// overlapping sends therefore take nonces 0 and 1 but can reach the socket
  /// in either order, and the peer — which derives the nonce from arrival
  /// order — fails to authenticate the first record it sees.
  ///
  /// It is easy to assume this cannot happen in single-threaded Dart. It
  /// happens constantly: the one-second heartbeat fires while the application
  /// is sending, or a `pong` is written while a clipboard update is in flight.
  /// The failure looks like a corrupted stream or an active attacker, which is
  /// exactly the wrong place to start debugging.
  Future<void> _writeChain = Future<void>.value();

  Future<void> _writeNow(Message message, {required bool requireAck}) {
    final queued = _writeChain.then(
      (_) => _performWrite(message, requireAck: requireAck),
    );
    // The chain must survive a failed write. Without swallowing the error here,
    // one broken send would leave every later send awaiting a rejected future.
    _writeChain = queued.then((_) {}, onError: (Object _) {});
    return queued;
  }

  Future<void> _performWrite(
    Message message, {
    required bool requireAck,
  }) async {
    if (_state == SessionState.closed) return;

    final frame = _codec.encode(message, requireAck: requireAck);
    await _performFrameWrite(frame);
  }

  Future<void> _performFrameWrite(Frame frame) async {
    // The whole frame — header included — is encrypted, so an observer learns
    // only that a message of some size was sent. Message types stay private,
    // which matters because a stream of 22-byte frames at 120 Hz would
    // otherwise announce "the user is moving the mouse right now".
    final sealed = await _keys.send.seal(frame.encode());

    try {
      _connection.send(sealed);
    } on TransportError catch (e) {
      _log.warn('write failed', error: e);
      await _teardown(CloseReason.protocolError);
      rethrow;
    }

    _sentMessages++;
    _sentBytes += sealed.length + 4;
  }

  Future<void> _onRecord(Uint8List sealed) async {
    _receivedBytes += sealed.length + 4;

    // Claimed synchronously, before any `await`. Reading the field and
    // incrementing it after the asynchronous `open` would let two records that
    // arrive in the same event-loop turn both decrypt against counter 0.
    final counter = _receiveCounter++;

    final Frame frame;
    try {
      final plaintext = await _keys.receive.open(sealed, counter: counter);
      frame = Frame.readFrom(ByteReader(plaintext), copyPayload: false);
    } on SecurityError catch (e) {
      // A failed AEAD tag means either corruption TCP should have caught or an
      // active attacker. Neither is recoverable, and continuing would leave the
      // nonce counters desynchronised.
      _log.error('record failed authentication', error: e);
      await _teardown(CloseReason.protocolError);
      return;
    } on ProtocolError catch (e) {
      _log.error('malformed frame', error: e);
      await _teardown(CloseReason.protocolError);
      return;
    }

    _receivedMessages++;

    final Message message;
    try {
      message = _codec.decode(frame);
    } on ProtocolError catch (e) {
      if (e.code == 'protocol.file_chunk_checksum_mismatch') {
        _log.warn('dropping file chunk with a bad CRC-32C');
        return;
      }
      _log.error('payload decode failed', error: e);
      await _teardown(CloseReason.protocolError);
      return;
    }

    if (frame.flags.needsAck) {
      unawaited(
        _writeNow(
          Ack(
            acknowledgedSequence: frame.sequence,
            receivedMicros: _clock.monotonicMicros(),
          ),
          requireAck: false,
        ),
      );
    }

    // Control traffic is handled here and never surfaces to the application.
    switch (message) {
      case Ping():
        await _writeNow(
          Pong(
            originalSenderMicros: message.senderMicros,
            responderMicros: _clock.monotonicMicros(),
          ),
          requireAck: false,
        );
        return;
      case Pong():
        _onPong(message);
        return;
      case CloseMessage():
        _closeReason = message.reason;
        await _teardown(message.reason);
        return;
      case Ack():
        _pendingAcknowledgements
            .remove(message.acknowledgedSequence)
            ?.complete();
        return;
      // The code is destructured out of the pattern rather than read as
      // `message.code` inside the closure: pattern promotion does not reach
      // into a deferred closure body, so the promoted type is not visible there
      // and only the `Message` supertype would be in scope.
      case UnknownMessage(:final code):
        // A newer peer sent something this build does not know. Dropping it is
        // the forward-compatibility contract, not an error.
        _log.debug(() => 'ignoring unknown message 0x'
            '${code.toRadixString(16)}');
        return;
      default:
        break;
    }

    if (_state == SessionState.pairing &&
        message.type.subsystem != 0x01 &&
        message.type.subsystem != 0x00) {
      // Until pairing completes the peer is authenticated but not authorised.
      // Silently dropping is deliberate: replying would confirm to an
      // unapproved device that it reached a real server.
      _log.debug(() => 'dropping ${message.type.name} during pairing');
      return;
    }

    if (!_messages.isClosed) _messages.add(message);
  }

  void _onPong(Pong pong) {
    _lastPongMicros = _clock.monotonicMicros();
    _missedHeartbeats = 0;

    final rtt = _lastPongMicros - pong.originalSenderMicros;
    if (rtt >= 0) {
      _rttSamples.add(rtt);
      // A short window tracks real changes quickly; a long one would keep
      // reporting "excellent" for ten seconds after the user walked out of
      // Wi-Fi range.
      if (_rttSamples.length > 16) _rttSamples.removeAt(0);
    }

    if (!_quality.isClosed) _quality.add(currentQuality);
  }

  void _startHeartbeat() {
    _heartbeat = Timer.periodic(
      kHeartbeatInterval,
      (_) => unawaited(_onHeartbeatTick()),
    );
  }

  Future<void> _onHeartbeatTick() async {
    if (_state == SessionState.closed) return;

    final now = _clock.monotonicMicros();
    final silentFor = now - _lastPongMicros;

    if (_lastPingMicros > 0 && silentFor > kHeartbeatTimeout.inMicroseconds) {
      _missedHeartbeats++;
      _log.warn(
        'peer silent past the heartbeat deadline',
        fields: <String, Object?>{
          'silentMicros': silentFor,
          'missed': _missedHeartbeats,
        },
      );
      await _teardown(CloseReason.idleTimeout);
      return;
    }

    _lastPingMicros = now;
    try {
      await _writeNow(Ping(senderMicros: now), requireAck: false);
    } on TransportError {
      // _writeNow has already torn the session down.
    }
  }

  /// Marks pairing complete, unblocking application traffic.
  void completePairing() {
    if (_state != SessionState.pairing) return;
    _setState(SessionState.established);
  }

  /// Sends a close notice and shuts down.
  ///
  /// Announcing the reason lets the peer decide whether to reconnect. Without
  /// it, a deliberate disconnect is indistinguishable from a crash and the
  /// supervisor would helpfully reconnect to a server the user just quit.
  Future<void> close({
    CloseReason reason = CloseReason.userRequested,
    String? detail,
  }) async {
    if (_state == SessionState.closed) return;
    try {
      await _writeNow(
        CloseMessage(reason: reason, detail: detail),
        requireAck: false,
      );
    } on Object {
      // Best effort; the socket may already be gone.
    }
    _closeReason = reason;
    await _teardown(reason);
  }

  Future<void> _onTransportError(Object error, StackTrace stackTrace) async {
    _log.warn('transport error', error: error, stackTrace: stackTrace);
    await _teardown(CloseReason.protocolError);
  }

  Future<void> _teardown(CloseReason reason) async {
    if (_state == SessionState.closed) return;
    _closeReason ??= reason;
    _setState(SessionState.closed);

    _heartbeat?.cancel();
    _heartbeat = null;
    _pendingLossy.clear();
    final pending = _pendingAcknowledgements.values.toList();
    _pendingAcknowledgements.clear();
    for (final acknowledgement in pending) {
      if (!acknowledgement.isCompleted) {
        acknowledgement.completeError(
          const TransportError('session_closed', 'session closed before ack'),
        );
      }
    }

    await _subscription.cancel();
    await _connection.close();

    _keys.dispose();

    await _messages.close();
    await _stateChanges.close();
    await _quality.close();
  }

  void _setState(SessionState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateChanges.isClosed) _stateChanges.add(next);
  }

  /// Median rather than mean RTT.
  ///
  /// One 300 ms stall — a Wi-Fi scan, a GC pause — would drag a mean upward for
  /// the whole window and make a healthy link look bad. The median ignores it.
  int _medianRtt() {
    if (_rttSamples.isEmpty) return 0;
    final sorted = List<int>.from(_rttSamples)..sort();
    return sorted[sorted.length ~/ 2];
  }

  int _jitter() {
    if (_rttSamples.length < 2) return 0;
    final median = _medianRtt();
    var total = 0;
    for (final sample in _rttSamples) {
      total += (sample - median).abs();
    }
    return total ~/ _rttSamples.length;
  }
}
