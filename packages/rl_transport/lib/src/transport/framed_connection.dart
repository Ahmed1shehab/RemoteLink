import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';

/// Largest record accepted off the wire.
///
/// One byte above this and the connection is dropped without allocating. The
/// limit exists specifically for the pre-authentication window: before the
/// handshake completes, anyone who can reach the port can send a length prefix,
/// and without a cap a four-byte datagram would let them request a 4 GiB
/// allocation.
const int kMaxRecordSize = 17 * 1024 * 1024;

/// Length-prefixed record framing over a byte stream.
///
/// TCP is a stream, not a message channel: a single `write` can arrive as three
/// reads, and three writes can arrive as one. Every socket protocol has to
/// solve this, and a four-byte big-endian length prefix is the simplest correct
/// answer — self-describing, no escaping, no scanning for delimiters, and the
/// receiver knows exactly how much to buffer before it has to look at anything.
///
/// ## Why raw TCP rather than WebSocket
///
/// WebSocket was the alternative and would have brought a browser client for
/// free. It was rejected on latency grounds:
///
/// * An HTTP upgrade handshake adds a round trip to every connect, and
///   reconnect time is a headline requirement here.
/// * RFC 6455 requires client-to-server frames to be XOR-masked, which means
///   copying and transforming every byte of every mouse event on a phone.
/// * Its framing duplicates what this class does, so the overhead buys nothing.
///
/// Raw TCP with `TCP_NODELAY` sends a 22-byte cursor update as one segment, on
/// the wire, immediately. The browser client is not a milestone-1 requirement,
/// and if it becomes one, a WebSocket implementation of this same interface can
/// be added without touching the session layer.
final class FramedConnection {
  FramedConnection._(this._socket, this._log) {
    // Nagle's algorithm holds small writes back to coalesce them. That is
    // exactly wrong here: a 22-byte mouse event delayed 40 ms to save 18 bytes
    // of header is the single most visible latency bug this protocol could
    // have.
    _socket.setOption(SocketOption.tcpNoDelay, true);

    _subscription = _socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  /// Wraps an already-connected socket.
  factory FramedConnection.wrap(Socket socket, {Log? log}) =>
      FramedConnection._(socket, log ?? Log.scoped('transport.framed'));

  /// Dials [host]:[port].
  static Future<FramedConnection> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
    Log? log,
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      return FramedConnection.wrap(socket, log: log);
    } on SocketException catch (e) {
      throw TransportError(
        'connect_failed',
        'could not connect to $host:$port',
        cause: e,
      );
    }
  }

  final Socket _socket;
  final Log _log;

  late final StreamSubscription<Uint8List> _subscription;

  final StreamController<Uint8List> _records =
      StreamController<Uint8List>.broadcast();

  /// Accumulates partial reads until a whole record is available.
  final BytesBuilder _buffer = BytesBuilder(copy: true);

  /// Length of the record currently being assembled, or `-1` while the prefix
  /// itself is still incomplete.
  int _expected = -1;

  bool _closed = false;

  /// Complete records, in order.
  Stream<Uint8List> get records => _records.stream;

  /// Remote endpoint, for logging and for remembering a last-known address.
  String get remoteAddress => _socket.remoteAddress.address;

  int get remotePort => _socket.remotePort;

  bool get isClosed => _closed;

  /// Writes one record with its length prefix.
  ///
  /// Header and body go out in a single `add` so the OS emits one segment.
  /// Writing the prefix separately would produce two small segments and, with
  /// `TCP_NODELAY` on, two packets for every mouse move.
  void send(Uint8List payload) {
    if (_closed) {
      throw const TransportError('send_after_close', 'connection is closed');
    }
    if (payload.length > kMaxRecordSize) {
      throw TransportError(
        'record_too_large',
        'record of ${payload.length} bytes exceeds $kMaxRecordSize',
        retryable: false,
      );
    }

    final framed = Uint8List(4 + payload.length);
    ByteData.sublistView(framed).setUint32(0, payload.length, Endian.big);
    framed.setRange(4, framed.length, payload);
    _socket.add(framed);
  }

  void _onData(Uint8List chunk) {
    _buffer.add(chunk);

    // Drain every complete record the buffer now holds. A single read can
    // easily contain a dozen mouse events during a fast drag.
    while (true) {
      if (_expected < 0) {
        if (_buffer.length < 4) return;
        final bytes = _buffer.takeBytes();
        _expected = ByteData.sublistView(bytes).getUint32(0, Endian.big);

        if (_expected > kMaxRecordSize) {
          _fail(
            TransportError(
              'record_too_large',
              'peer declared a $_expected byte record',
              retryable: false,
            ),
          );
          return;
        }

        _buffer.add(Uint8List.sublistView(bytes, 4));
        continue;
      }

      if (_buffer.length < _expected) return;

      final bytes = _buffer.takeBytes();
      final record = Uint8List.sublistView(bytes, 0, _expected);
      _buffer.add(Uint8List.sublistView(bytes, _expected));
      _expected = -1;

      if (!_records.isClosed) _records.add(Uint8List.fromList(record));
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _log.debug(() => 'socket error: $error');
    _fail(
      TransportError('socket_error', 'socket failed', cause: error),
      stackTrace: stackTrace,
    );
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    unawaited(_records.close());
  }

  void _fail(TransportError error, {StackTrace? stackTrace}) {
    if (_closed) return;
    _closed = true;
    if (!_records.isClosed) {
      _records.addError(error, stackTrace ?? StackTrace.current);
      unawaited(_records.close());
    }
    _socket.destroy();
  }

  /// Flushes pending writes and closes gracefully.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _socket.flush();
      await _socket.close();
    } on SocketException {
      // The peer may already be gone; nothing useful to do about it here.
    } finally {
      await _subscription.cancel();
      _socket.destroy();
      if (!_records.isClosed) await _records.close();
    }
  }

  /// Drops the connection immediately, without flushing.
  void destroy() {
    if (_closed) return;
    _closed = true;
    unawaited(_subscription.cancel());
    _socket.destroy();
    if (!_records.isClosed) unawaited(_records.close());
  }
}
