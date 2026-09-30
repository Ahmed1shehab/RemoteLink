import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'framed_connection.dart';
import 'session.dart';

/// How long the whole handshake may take before it is abandoned.
///
/// Generous enough for a slow phone doing four X25519 operations, tight enough
/// that a half-open connection cannot pin a server slot indefinitely — which is
/// the cheapest denial-of-service available against a listener.
const Duration kHandshakeTimeout = Duration(seconds: 10);

/// Runs the handshake over a [FramedConnection] and produces a [Session].
///
/// ## Record layout during the handshake
///
/// Every handshake record is an ordinary [Frame], so a peer can abort with an
/// `error` frame at any point and the receiver can still parse it. Records 1
/// and 2 carry normal encoded messages. Records 3 to 5 carry the sealed
/// handshake blobs *as the frame payload* — there is no inner message encoding,
/// because the state machine already knows what each step must be and adding a
/// type tag would be a field an attacker could vary.
///
/// ```text
/// 1  client → server   Frame(clientHello)       plaintext
/// 2  server → client   Frame(serverHello)       plaintext
/// 3  server → client   Frame(handshakeFinish)   payload = sealed server static
/// 4  client → server   Frame(handshakeFinish)   payload = sealed client finish
/// 5  server → client   Frame(handshakeFinish)   payload = sealed server confirm
/// ```
abstract final class HandshakeDriver {
  /// Client side. Runs to completion and returns a live session.
  static Future<Session> runClient({
    required FramedConnection connection,
    required DeviceIdentity identity,
    required Capabilities capabilities,
    required Clock clock,
    Uint8List? expectedServerKey,
    DeviceId? expectedServerId,
    ClientResumption? resumption,
    Duration timeout = kHandshakeTimeout,
  }) async {
    final log = Log.scoped('transport.handshake.client');
    final handshake = ClientHandshake(
      identity: identity,
      capabilities: capabilities,
      expectedServerKey: expectedServerKey,
      expectedServerId: expectedServerId,
    );

    final reader = _RecordReader(connection);
    final codec = MessageCodec(clock: clock, compressionEnabled: false);

    try {
      return await _withTimeout(timeout, () async {
        if (resumption != null && expectedServerKey != null) {
          final ephemeral = await Primitives.generateKeyPair();
          final publicKey =
              Uint8List.fromList((await ephemeral.extractPublicKey()).bytes);
          final nonce = _secureBytes(32);
          final mac = await Primitives.mac(
              key: resumption.secret,
              data: <int>[...resumption.ticket, ...nonce]);
          connection.send(codec
              .encode(ResumeSession(
                  ticket: resumption.ticket,
                  clientNonce: nonce,
                  bindingMac: mac,
                  clientEphemeral: publicKey,
                  capabilities: capabilities))
              .encode());
          final response = await reader.next();
          if (response.type == MessageType.handshakeFinish &&
              response.payload.length == 72) {
            final serverEphemeral =
                Uint8List.fromList(response.payload.sublist(0, 32));
            final negotiatedBytes = response.payload.sublist(32, 40);
            final advertised = Capabilities(
                ByteData.sublistView(Uint8List.fromList(negotiatedBytes))
                    .getUint64(0));
            final negotiated = advertised.intersect(capabilities);
            final transcript = await ResumeKeys.transcript(resumption.ticket,
                nonce, publicKey, serverEphemeral, negotiatedBytes);
            final proof =
                await ResumeKeys.serverProof(resumption.secret, transcript);
            if (Primitives.constantTimeEquals(
                    proof, response.payload.sublist(40)) &&
                negotiated.bits == advertised.bits) {
              final shared = await Primitives.sharedSecret(
                  keyPair: ephemeral, remotePublicKey: serverEphemeral);
              final keys = await ResumeKeys.derive(
                  secret: resumption.secret,
                  shared: shared,
                  transcript: transcript,
                  client: true);
              final peerId = DeviceId.fromDigest(
                  await Primitives.sha256(expectedServerKey));
              final session = Session(
                  connection: connection,
                  keys: keys,
                  clock: clock,
                  peerId: peerId,
                  peerStaticPublicKey: expectedServerKey,
                  shortAuthenticationString: '',
                  capabilities: negotiated,
                  isServer: false,
                  wasResumed: true,
                  initialRecords: reader.takePendingRecords());
              await reader.detach();
              return session;
            }
            throw const TransportError(
                'resume_proof_failed', 'server resume proof failed');
          }
          // A normal ServerHello is the explicit rejection. Start the full
          // exchange on this same socket; no connection-level error is shown.
          _requireType(response, MessageType.serverHello);
        }
        connection.send(codec.encode(await handshake.createHello()).encode());

        final serverHelloFrame = await reader.next();
        final serverHello = _expect<ServerHello>(
          codec,
          serverHelloFrame,
          MessageType.serverHello,
        );
        await handshake.receiveServerHello(serverHello);

        final staticFrame = await reader.next();
        _requireType(staticFrame, MessageType.handshakeFinish);
        await handshake.receiveServerStatic(staticFrame.payload);

        final finish = await handshake.createClientFinish();
        connection.send(_rawFrame(finish, codec).encode());

        final confirmFrame = await reader.next();
        _requireType(confirmFrame, MessageType.handshakeFinish);
        final result =
            await handshake.receiveServerConfirm(confirmFrame.payload);

        log.info(
          'handshake complete',
          fields: <String, Object?>{
            'peer': result.peerId.value,
            'known': result.peerWasKnown,
            'pairing': result.requiresPairing,
          },
        );

        // Attach the encrypted-session listener before detaching the handshake
        // reader. A server may send its first session record immediately after
        // the confirmation, and broadcast records have no replay buffer.
        final session = Session(
          connection: connection,
          keys: result.keys,
          clock: clock,
          peerId: result.peerId,
          peerStaticPublicKey: result.peerStaticPublicKey,
          shortAuthenticationString: result.shortAuthenticationString,
          capabilities: result.capabilities,
          isServer: false,
          requiresPairing: result.requiresPairing,
          initialRecords: reader.takePendingRecords(),
        );
        await reader.detach();
        return session;
      });
    } on Object {
      await reader.detach();
      connection.destroy();
      rethrow;
    }
  }

  /// Server side. Returns the session and the handshake result, since the
  /// caller needs the peer's static key to complete pairing.
  ///
  /// [holdKnownPeers] starts an *already trusted* session blocked as well, so
  /// the caller can ask a person whether to let this connection in. It has no
  /// effect on a peer that was going to be held for pairing anyway, which is
  /// why one flag covers both: the question "may it through" is the same one,
  /// and only the reason for asking differs.
  static Future<(Session, HandshakeResult)> runServer({
    required FramedConnection connection,
    required DeviceIdentity identity,
    required Capabilities capabilities,
    required Clock clock,
    required PeerLookup lookupPeer,
    PeerLookup? lookupResumePeer,
    ResumptionTickets? tickets,
    bool holdKnownPeers = false,
    Duration timeout = kHandshakeTimeout,
  }) async {
    final log = Log.scoped('transport.handshake.server');
    final handshake = ServerHandshake(
      identity: identity,
      capabilities: capabilities,
      lookupPeer: lookupPeer,
    );

    final reader = _RecordReader(connection);
    final codec = MessageCodec(clock: clock, compressionEnabled: false);

    try {
      return await _withTimeout(timeout, () async {
        var helloFrame = await reader.next();
        if (helloFrame.type == MessageType.resumeSession && tickets != null) {
          final request = _expect<ResumeSession>(
              codec, helloFrame, MessageType.resumeSession);
          final opened = await tickets
              .open(request.ticket, request.clientNonce, request.bindingMac,
                  (key, tier) async {
            final peer = await (lookupResumePeer ?? lookupPeer)(key);
            return peer != null && !peer.revoked && peer.permissionTier == tier;
          });
          if (opened != null) {
            final ephemeral = await Primitives.generateKeyPair();
            final publicKey =
                Uint8List.fromList((await ephemeral.extractPublicKey()).bytes);
            Uint8List? shared;
            try {
              shared = await Primitives.sharedSecret(
                  keyPair: ephemeral, remotePublicKey: request.clientEphemeral);
            } on Object {
              // Even a valid ticket can carry a malformed ephemeral. Treat it
              // like every other rejected resume and run the full handshake.
            }
            if (shared != null) {
              final negotiated = capabilities.intersect(request.capabilities);
              final negotiatedBytes = Uint8List(8);
              ByteData.sublistView(negotiatedBytes)
                  .setUint64(0, negotiated.bits);
              final transcript = await ResumeKeys.transcript(
                  request.ticket,
                  request.clientNonce,
                  request.clientEphemeral,
                  publicKey,
                  negotiatedBytes);
              final proof =
                  await ResumeKeys.serverProof(opened.secret, transcript);
              final keys = await ResumeKeys.derive(
                  secret: opened.secret,
                  shared: shared,
                  transcript: transcript,
                  client: false);
              final peerId =
                  DeviceId.fromDigest(await Primitives.sha256(opened.peerKey));
              connection.send(_rawFrame(
                      Uint8List.fromList(<int>[
                        ...publicKey,
                        ...negotiatedBytes,
                        ...proof,
                      ]),
                      codec)
                  .encode());
              final result = HandshakeResult(
                  keys: keys,
                  peerId: peerId,
                  peerStaticPublicKey: opened.peerKey,
                  negotiatedVersion: kProtocolVersion,
                  capabilities: negotiated,
                  requiresPairing: false,
                  shortAuthenticationString: '',
                  peerWasKnown: true);
              final session = Session(
                  connection: connection,
                  keys: keys,
                  clock: clock,
                  peerId: peerId,
                  peerStaticPublicKey: opened.peerKey,
                  shortAuthenticationString: '',
                  capabilities: negotiated,
                  isServer: true,
                  wasResumed: true,
                  requiresPairing: holdKnownPeers,
                  initialRecords: reader.takePendingRecords());
              await reader.detach();
              return (session, result);
            }
          }
          // Do not reveal which validation failed. The client treats this
          // ordinary hello as a request to send a fresh ClientHello.
          connection.send(codec
              .encode(ServerHello(
                  selectedVersion: kProtocolVersion,
                  serverId: identity.id,
                  ephemeralPublicKey: Uint8List(32),
                  serverNonce: Uint8List(32),
                  capabilities: capabilities,
                  requiresPairing: true))
              .encode());
          helloFrame = await reader.next();
        }
        final clientHello = _expect<ClientHello>(
          codec,
          helloFrame,
          MessageType.clientHello,
        );

        final (serverHello, sealedStatic) =
            await handshake.receiveClientHello(clientHello);
        connection
          ..send(codec.encode(serverHello).encode())
          ..send(_rawFrame(sealedStatic, codec).encode());

        final finishFrame = await reader.next();
        _requireType(finishFrame, MessageType.handshakeFinish);
        final (sealedConfirm, result) =
            await handshake.receiveClientFinish(finishFrame.payload);

        connection.send(_rawFrame(sealedConfirm, codec).encode());

        log.info(
          'handshake complete',
          fields: <String, Object?>{
            'peer': result.peerId.value,
            'known': result.peerWasKnown,
            'address': connection.remoteAddress,
          },
        );

        // Attach before detaching, and carry over whatever arrived in between,
        // for the same reason the client does: `records` is a broadcast stream,
        // so a record delivered while no one is listening is dropped without a
        // trace. A phone that pipelines its first session record behind its
        // handshake finish — which it does, the two are written back to back —
        // would lose it here, and a lost record is not a lost message: both
        // sides derive the AEAD nonce from the record count, so the next record
        // fails to authenticate and the session dies claiming corruption.
        final session = Session(
          connection: connection,
          keys: result.keys,
          clock: clock,
          peerId: result.peerId,
          peerStaticPublicKey: result.peerStaticPublicKey,
          shortAuthenticationString: result.shortAuthenticationString,
          capabilities: result.capabilities,
          isServer: true,
          // Held from the first record, never admitted and then retracted.
          // The peer writes its first session record immediately behind its
          // handshake finish — a clipboard update, a file offer — and a gate
          // raised one turn later would have let that one through. Deciding
          // here means there is no such turn.
          requiresPairing: result.requiresPairing || holdKnownPeers,
          initialRecords: reader.takePendingRecords(),
        );
        await reader.detach();
        return (session, result);
      });
    } on Object {
      await reader.detach();
      connection.destroy();
      rethrow;
    }
  }

  /// Wraps a raw sealed blob in a frame without an inner message encoding.
  static Frame _rawFrame(Uint8List sealed, MessageCodec codec) => Frame(
        type: MessageType.handshakeFinish,
        sequence: codec.nextSequence,
        timestampMicros: 0,
        payload: sealed,
      );

  static T _expect<T extends Message>(
    MessageCodec codec,
    Frame frame,
    MessageType expected,
  ) {
    _requireType(frame, expected);
    final message = codec.decode(frame);
    if (message is! T) {
      throw SecurityError(
        'handshake_unexpected',
        // `message.type.name` rather than `runtimeType`: the enum name is
        // stable under minification, where a class name is not.
        'expected ${expected.name}, decoded ${message.type.name}',
      );
    }
    return message;
  }

  static void _requireType(Frame frame, MessageType expected) {
    if (frame.type == expected) return;
    if (frame.type == MessageType.error) {
      throw const SecurityError(
        'handshake_rejected',
        'peer rejected the handshake',
      );
    }
    throw SecurityError(
      'handshake_out_of_order',
      'expected ${expected.name}, received ${frame.type.name}',
    );
  }

  static Future<T> _withTimeout<T>(
    Duration timeout,
    Future<T> Function() body,
  ) =>
      body().timeout(
        timeout,
        onTimeout: () => throw const TransportError(
          'handshake_timeout',
          'handshake did not complete in time',
        ),
      );
}

/// Pulls handshake records off a connection one at a time.
///
/// The handshake is inherently sequential, so a request/response reader is a
/// better fit than a listener with a state machine — the control flow reads
/// exactly like the specification. [detach] must be called before the
/// [Session] takes over, or both would consume from the same broadcast stream.
final class _RecordReader {
  _RecordReader(this._connection) {
    _subscription = _connection.records.listen(
      (record) {
        _pendingRecords.add(record);
        _queue.add(record);
      },
      onError: (Object error, StackTrace stack) {
        if (_queue.hasListener) _queue.addError(error, stack);
      },
      onDone: () => unawaited(_queue.close()),
      cancelOnError: false,
    );
    _iterator = StreamIterator<Uint8List>(_queue.stream);
  }

  final FramedConnection _connection;
  final StreamController<Uint8List> _queue = StreamController<Uint8List>();
  final List<Uint8List> _pendingRecords = <Uint8List>[];
  late final StreamSubscription<Uint8List> _subscription;
  late final StreamIterator<Uint8List> _iterator;

  /// Next record, decoded as a frame.
  Future<Frame> next() async {
    if (!await _iterator.moveNext()) {
      throw const TransportError(
        'handshake_closed',
        'peer closed the connection during the handshake',
      );
    }
    _pendingRecords.removeAt(0);
    return Frame.readFrom(ByteReader(_iterator.current));
  }

  /// Records that arrived after the last handshake step but before [Session]
  /// could attach to the broadcast connection stream.
  List<Uint8List> takePendingRecords() {
    final pending = List<Uint8List>.of(_pendingRecords);
    _pendingRecords.clear();
    return pending;
  }

  Future<void> detach() async {
    await _subscription.cancel();
    await _iterator.cancel();
    if (!_queue.isClosed) await _queue.close();
  }
}

Uint8List _secureBytes(int length) {
  final source = Random.secure();
  return Uint8List.fromList(
      List<int>.generate(length, (_) => source.nextInt(256)));
}
