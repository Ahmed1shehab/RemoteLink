import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'identity.dart';
import 'primitives.dart';
import 'session_cipher.dart';

/// Domain separator mixed into the first transcript hash.
///
/// Includes the protocol version so that a future v2 handshake produces
/// entirely different keys even if every other input were identical. That
/// removes cross-version confusion attacks by construction.
const String kHandshakeLabel = 'RemoteLink/1/handshake';

// HKDF context labels. Each derived secret gets its own, which is what keeps
// them independent despite sharing one input keying material. Never reuse a
// label for a different purpose.
const String _labelHandshakeC2S = 'rl1 hs c2s';
const String _labelHandshakeS2C = 'rl1 hs s2c';
const String _labelDataC2S = 'rl1 data c2s';
const String _labelDataS2C = 'rl1 data s2c';
const String _labelConfirmClient = 'rl1 confirm c';
const String _labelConfirmServer = 'rl1 confirm s';
const String _labelResumption = 'rl1 resumption';
const String _labelExporter = 'rl1 exporter';
const String _labelSas = 'rl1 sas';

/// Outcome of a completed handshake.
@immutable
final class HandshakeResult {
  const HandshakeResult({
    required this.keys,
    required this.peerId,
    required this.peerStaticPublicKey,
    required this.negotiatedVersion,
    required this.capabilities,
    required this.requiresPairing,
    required this.shortAuthenticationString,
    required this.peerWasKnown,
  });

  final SessionKeys keys;
  final DeviceId peerId;
  final Uint8List peerStaticPublicKey;
  final int negotiatedVersion;

  /// Capabilities supported by *both* sides.
  final Capabilities capabilities;

  /// True when the peer's static key was not previously trusted, so the user
  /// must complete pairing before the session is usable.
  final bool requiresPairing;

  /// Six digits derived from the handshake transcript.
  ///
  /// Identical on both devices if and only if no machine-in-the-middle is
  /// present, because an attacker relaying the connection necessarily runs two
  /// separate key agreements and cannot make both transcripts hash alike.
  final String shortAuthenticationString;

  /// True when the peer's static key matched a stored, non-revoked entry —
  /// in other words, a silent reconnect with no user interaction.
  final bool peerWasKnown;
}

/// Shared state and key schedule for both sides of the handshake.
///
/// The design is a simplified Noise XX pattern:
///
/// ```text
/// 1. client → server   e_c, nonce_c, versions, capabilities   (plaintext)
/// 2. server → client   e_s, nonce_s, serverId, version        (plaintext)
///                      ── both derive handshake keys from ee ──
/// 3. server → client   seal(s_s)                              (encrypted)
///                      ── both derive master from ee|es|se|ss ──
/// 4. client → server   seal(s_c ‖ confirm_c)                  (encrypted)
/// 5. server → client   seal(confirm_s)                        (encrypted)
/// ```
///
/// Why this shape:
///
/// * **Static keys are never sent in the clear.** A passive observer on the
///   café Wi-Fi cannot fingerprint which devices are talking, only that someone
///   is. This is why step 3 exists at all instead of putting `s_s` in step 2.
/// * **The ephemeral exchange comes first** so everything after it is already
///   confidential, and it gives forward secrecy: recovering both long-term keys
///   later does not decrypt a recorded session.
/// * **Authentication is mutual and deferred to the last two messages**, since
///   neither side can compute the static-static term until both statics have
///   arrived. Confirmation tokens are HKDF outputs of the master secret, so
///   presenting one proves possession of the matching private key over this
///   exact transcript.
/// * **Every step is bound into a running transcript hash** used as HKDF salt
///   and AEAD associated data, so tampering with any earlier byte breaks every
///   later step.
abstract base class _HandshakeCore {
  _HandshakeCore({required this.identity, required this.capabilities});

  final DeviceIdentity identity;
  final Capabilities capabilities;

  late final SimpleKeyPair _ephemeral;
  Uint8List _ephemeralPublic = Uint8List(0);

  Uint8List _transcript = Uint8List(0);
  Uint8List _peerEphemeralPublic = Uint8List(0);
  Uint8List _peerStaticPublic = Uint8List(0);

  Uint8List _sharedEphemeral = Uint8List(0);
  Uint8List _masterIkm = Uint8List(0);

  /// Transcript hash frozen at the moment the master secret is formed.
  ///
  /// Every master-derived secret salts with *this*, not with the live
  /// [_transcript]. The two sides reach that moment at different points in
  /// their own message ordering — the client after opening the server's static,
  /// the server after opening the client's finish — so salting with the live
  /// value would silently derive different keys on each side and surface only
  /// as an authentication failure two messages later.
  Uint8List _masterSalt = Uint8List(0);

  DirectionalCipher? _handshakeSend;
  DirectionalCipher? _handshakeReceive;

  Capabilities _negotiated = const Capabilities(0);
  int _version = kProtocolVersion;
  bool _complete = false;

  bool get isComplete => _complete;

  Future<void> _initEphemeral() async {
    _ephemeral = await Primitives.generateKeyPair();
    _ephemeralPublic =
        Uint8List.fromList((await _ephemeral.extractPublicKey()).bytes);
    _transcript = await Primitives.sha256(kHandshakeLabel.codeUnits);
  }

  /// Folds [data] into the running transcript hash.
  Future<void> _absorb(List<int> data) async {
    final combined = Uint8List(_transcript.length + data.length)
      ..setRange(0, _transcript.length, _transcript)
      ..setRange(_transcript.length, _transcript.length + data.length, data);
    _transcript = await Primitives.sha256(combined);
  }

  /// Derives the two provisional keys that protect handshake steps 3 to 5.
  Future<void> _deriveHandshakeKeys() async {
    _sharedEphemeral = await Primitives.sharedSecret(
      keyPair: _ephemeral,
      remotePublicKey: _peerEphemeralPublic,
    );

    final c2s = await Primitives.hkdf(
      secret: _sharedEphemeral,
      salt: _transcript,
      info: _labelHandshakeC2S,
    );
    final s2c = await Primitives.hkdf(
      secret: _sharedEphemeral,
      salt: _transcript,
      info: _labelHandshakeS2C,
    );

    final isClient = this is ClientHandshake;
    _handshakeSend = DirectionalCipher(
      key: isClient ? c2s : s2c,
      label: isClient ? 'hs-c2s' : 'hs-s2c',
    );
    _handshakeReceive = DirectionalCipher(
      key: isClient ? s2c : c2s,
      label: isClient ? 'hs-s2c' : 'hs-c2s',
    );
  }

  /// Concatenates every Diffie-Hellman output into the master input keying
  /// material.
  ///
  /// All four terms are required. Dropping `ss` would lose authentication;
  /// dropping `es` or `se` would let an attacker who compromised one side's
  /// long-term key impersonate the other; dropping `ee` would lose forward
  /// secrecy.
  Future<void> _deriveMasterIkm({required bool asClient}) async {
    final es = asClient
        // Client: its ephemeral against the server's static.
        ? await Primitives.sharedSecret(
            keyPair: _ephemeral,
            remotePublicKey: _peerStaticPublic,
          )
        // Server: its static against the client's ephemeral.
        : await Primitives.sharedSecret(
            keyPair: identity.keyPair,
            remotePublicKey: _peerEphemeralPublic,
          );

    final se = asClient
        // Client: its static against the server's ephemeral.
        ? await Primitives.sharedSecret(
            keyPair: identity.keyPair,
            remotePublicKey: _peerEphemeralPublic,
          )
        // Server: its ephemeral against the client's static.
        : await Primitives.sharedSecret(
            keyPair: _ephemeral,
            remotePublicKey: _peerStaticPublic,
          );

    final ss = await Primitives.sharedSecret(
      keyPair: identity.keyPair,
      remotePublicKey: _peerStaticPublic,
    );

    final ikm = Uint8List(Primitives.keyLength * 4)
      ..setRange(0, 32, _sharedEphemeral)
      ..setRange(32, 64, es)
      ..setRange(64, 96, se)
      ..setRange(96, 128, ss);

    Primitives.wipe(es);
    Primitives.wipe(se);
    Primitives.wipe(ss);

    _masterIkm = ikm;
    _masterSalt = Uint8List.fromList(_transcript);
  }

  Future<Uint8List> _derive(String label, {int length = 32}) =>
      Primitives.hkdf(
        secret: _masterIkm,
        salt: _masterSalt,
        info: label,
        length: length,
      );

  /// Builds the final session keys once both confirmations have verified.
  Future<SessionKeys> _buildSessionKeys({required bool asClient}) async {
    final c2s = await _derive(_labelDataC2S);
    final s2c = await _derive(_labelDataS2C);
    return SessionKeys(
      send: DirectionalCipher(
        key: asClient ? c2s : s2c,
        label: asClient ? 'c2s' : 's2c',
      ),
      receive: DirectionalCipher(
        key: asClient ? s2c : c2s,
        label: asClient ? 's2c' : 'c2s',
      ),
      resumptionSecret: await _derive(_labelResumption),
      exporterSecret: await _derive(_labelExporter),
    );
  }

  /// Derives the six-digit short authentication string.
  ///
  /// Eight bytes are folded into a 64-bit integer before the modulo, so the
  /// bias toward low digits is on the order of 10^-13 rather than the 10^-4 a
  /// 32-bit source would give. Not that the bias would be exploitable either
  /// way, but a uniform SAS is free here.
  Future<String> _deriveSas() async {
    final seed = await _derive(_labelSas, length: 8);
    final value = ByteData.sublistView(seed).getUint64(0, Endian.big);
    return (value % 1000000).toString().padLeft(6, '0');
  }

  Future<DeviceId> _peerIdFromStatic() async =>
      DeviceId.fromDigest(await Primitives.sha256(_peerStaticPublic));

  void _requireIncomplete() {
    if (_complete) {
      throw const SecurityError(
        'handshake_reused',
        'handshake object cannot be reused after completion',
      );
    }
  }
}

/// Client side of the handshake. Runs on the phone.
final class ClientHandshake extends _HandshakeCore {
  ClientHandshake({
    required super.identity,
    required super.capabilities,
    this.expectedServerKey,
    this.expectedServerId,
  });

  /// The server's static key from the trust store, when this is a reconnect.
  ///
  /// When present it is enforced: a server presenting a different key is
  /// rejected outright rather than triggering a pairing prompt. That is the
  /// defence against an attacker who takes over the server's address and hopes
  /// the user will tap through a re-pair dialog.
  final Uint8List? expectedServerKey;

  final DeviceId? expectedServerId;

  Uint8List _serverConfirmExpected = Uint8List(0);
  bool _serverWasKnown = false;

  /// Step 1. Builds the opening message.
  Future<ClientHello> createHello() async {
    _requireIncomplete();
    await _initEphemeral();

    final nonce = _randomBytes(32);
    final hello = ClientHello(
      minVersion: kMinSupportedProtocolVersion,
      maxVersion: kProtocolVersion,
      ephemeralPublicKey: _ephemeralPublic,
      clientNonce: nonce,
      capabilities: capabilities,
      knownServerId: expectedServerId,
    );

    await _absorb(hello.encodePayload());
    return hello;
  }

  /// Step 2. Consumes the server's reply and derives the handshake keys.
  Future<void> receiveServerHello(ServerHello hello) async {
    _requireIncomplete();

    if (hello.selectedVersion < kMinSupportedProtocolVersion ||
        hello.selectedVersion > kProtocolVersion) {
      throw SecurityError(
        'version_rejected',
        'server selected unsupported version ${hello.selectedVersion}',
      );
    }
    if (hello.ephemeralPublicKey.length != Primitives.keyLength) {
      throw const SecurityError(
        'bad_ephemeral',
        'server ephemeral key has the wrong length',
      );
    }

    _version = hello.selectedVersion;
    _negotiated = capabilities.intersect(hello.capabilities);
    _peerEphemeralPublic = hello.ephemeralPublicKey;

    await _absorb(hello.encodePayload());
    await _deriveHandshakeKeys();
  }

  /// Step 3. Opens the server's static key and derives the master secret.
  Future<void> receiveServerStatic(Uint8List sealedPayload) async {
    _requireIncomplete();
    final aad = Uint8List.fromList(_transcript);

    final plaintext = await _handshakeReceive!.open(
      sealedPayload,
      counter: 0,
      aad: aad,
    );
    if (plaintext.length != Primitives.keyLength) {
      throw const SecurityError(
        'bad_static',
        'sealed server static key has the wrong length',
      );
    }

    final expected = expectedServerKey;
    if (expected != null) {
      if (!Primitives.constantTimeEquals(expected, plaintext)) {
        throw const SecurityError(
          'server_key_mismatch',
          'server presented a key that does not match the trusted one',
        );
      }
      _serverWasKnown = true;
    }

    _peerStaticPublic = plaintext;
    await _absorb(sealedPayload);
    await _deriveMasterIkm(asClient: true);
  }

  /// Step 4. Produces the sealed client static key and confirmation token.
  Future<Uint8List> createClientFinish() async {
    _requireIncomplete();

    final confirmClient = await _derive(_labelConfirmClient);
    _serverConfirmExpected = await _derive(_labelConfirmServer);

    final payload = Uint8List(Primitives.keyLength + 32)
      ..setRange(0, 32, identity.publicKey)
      ..setRange(32, 64, confirmClient);

    final aad = Uint8List.fromList(_transcript);
    final sealed = await _handshakeSend!.seal(payload, aad: aad);
    await _absorb(sealed);
    return sealed;
  }

  /// Step 5. Verifies the server's confirmation and finalises the session.
  ///
  /// Until this returns, the client has *not* authenticated the server. Any
  /// application data accepted before this point would be data from an
  /// unauthenticated peer, which is why the session layer refuses to dispatch
  /// anything until the handshake reports completion.
  Future<HandshakeResult> receiveServerConfirm(Uint8List sealedPayload) async {
    _requireIncomplete();

    final plaintext = await _handshakeReceive!.open(
      sealedPayload,
      counter: 1,
      aad: Uint8List.fromList(_transcript),
    );

    if (!Primitives.constantTimeEquals(plaintext, _serverConfirmExpected)) {
      throw const SecurityError(
        'server_confirm_failed',
        'server confirmation token did not verify',
      );
    }

    final keys = await _buildSessionKeys(asClient: true);
    final sas = await _deriveSas();
    final peerId = await _peerIdFromStatic();

    _complete = true;
    _cleanupHandshakeKeys();

    return HandshakeResult(
      keys: keys,
      peerId: peerId,
      peerStaticPublicKey: _peerStaticPublic,
      negotiatedVersion: _version,
      capabilities: _negotiated,
      requiresPairing: !_serverWasKnown,
      shortAuthenticationString: sas,
      peerWasKnown: _serverWasKnown,
    );
  }

  void _cleanupHandshakeKeys() {
    _handshakeSend?.dispose();
    _handshakeReceive?.dispose();
    Primitives.wipe(_masterIkm);
    Primitives.wipe(_sharedEphemeral);
  }
}

/// Resolves a peer's static key to a trust decision.
///
/// Returning `null` means "not trusted" and puts the session into pairing.
/// Implemented by the desktop against its trust store.
typedef PeerLookup = Future<TrustedPeer?> Function(Uint8List staticPublicKey);

/// Server side of the handshake. Runs on the desktop.
final class ServerHandshake extends _HandshakeCore {
  ServerHandshake({
    required super.identity,
    required super.capabilities,
    required this.lookupPeer,
  });

  final PeerLookup lookupPeer;

  Uint8List _clientConfirmExpected = Uint8List(0);
  TrustedPeer? _knownPeer;

  /// Steps 1 to 3. Consumes the client's hello and produces both the plaintext
  /// reply and the sealed static key.
  ///
  /// These are returned together because they always travel together; splitting
  /// them into separate calls would let a caller send one without the other and
  /// leave the state machine wedged.
  Future<(ServerHello, Uint8List)> receiveClientHello(ClientHello hello) async {
    _requireIncomplete();

    final version = _negotiateVersion(hello);
    if (hello.ephemeralPublicKey.length != Primitives.keyLength) {
      throw const SecurityError(
        'bad_ephemeral',
        'client ephemeral key has the wrong length',
      );
    }
    if (hello.knownServerId != null && hello.knownServerId != identity.id) {
      throw SecurityError(
        'wrong_server',
        'client expected server ${hello.knownServerId} but this is '
            '${identity.id}',
      );
    }

    await _initEphemeral();
    _version = version;
    _negotiated = capabilities.intersect(hello.capabilities);
    _peerEphemeralPublic = hello.ephemeralPublicKey;

    await _absorb(hello.encodePayload());

    // requiresPairing is answered optimistically here because the client's
    // static key has not arrived yet. It is authoritative only after step 4;
    // this value exists so the phone can prepare its pairing UI a round trip
    // earlier, and it is corrected in the final result.
    final reply = ServerHello(
      selectedVersion: version,
      serverId: identity.id,
      ephemeralPublicKey: _ephemeralPublic,
      serverNonce: _randomBytes(32),
      capabilities: capabilities,
      requiresPairing: true,
    );

    await _absorb(reply.encodePayload());
    await _deriveHandshakeKeys();

    final sealedStatic = await _handshakeSend!.seal(
      identity.publicKey,
      aad: Uint8List.fromList(_transcript),
    );
    await _absorb(sealedStatic);

    return (reply, sealedStatic);
  }

  /// Step 4 and 5. Verifies the client and produces the server confirmation.
  Future<(Uint8List, HandshakeResult)> receiveClientFinish(
    Uint8List sealedPayload,
  ) async {
    _requireIncomplete();

    final plaintext = await _handshakeReceive!.open(
      sealedPayload,
      counter: 0,
      aad: Uint8List.fromList(_transcript),
    );
    if (plaintext.length != Primitives.keyLength + 32) {
      throw const SecurityError(
        'bad_client_finish',
        'client finish payload has the wrong length',
      );
    }

    _peerStaticPublic = Uint8List.sublistView(plaintext, 0, 32);
    final presentedConfirm = Uint8List.sublistView(plaintext, 32, 64);

    await _deriveMasterIkm(asClient: false);
    _clientConfirmExpected = await _derive(_labelConfirmClient);

    if (!Primitives.constantTimeEquals(
      presentedConfirm,
      _clientConfirmExpected,
    )) {
      throw const SecurityError(
        'client_confirm_failed',
        'client confirmation token did not verify',
      );
    }

    final peer = await lookupPeer(_peerStaticPublic);
    if (peer != null && peer.revoked) {
      throw const SecurityError(
        'peer_revoked',
        'this device was revoked and may not reconnect',
      );
    }
    _knownPeer = peer;

    await _absorb(sealedPayload);

    final confirmServer = await _derive(_labelConfirmServer);
    final sealedConfirm = await _handshakeSend!.seal(
      confirmServer,
      aad: Uint8List.fromList(_transcript),
    );

    final keys = await _buildSessionKeys(asClient: false);
    final sas = await _deriveSas();
    final peerId = await _peerIdFromStatic();

    _complete = true;
    _cleanupHandshakeKeys();

    final result = HandshakeResult(
      keys: keys,
      peerId: peerId,
      peerStaticPublicKey: _peerStaticPublic,
      negotiatedVersion: _version,
      capabilities: _negotiated,
      requiresPairing: peer == null,
      shortAuthenticationString: sas,
      peerWasKnown: peer != null,
    );
    return (sealedConfirm, result);
  }

  /// The trust-store entry matched during step 4, if any.
  TrustedPeer? get knownPeer => _knownPeer;

  int _negotiateVersion(ClientHello hello) {
    final highest = hello.maxVersion < kProtocolVersion
        ? hello.maxVersion
        : kProtocolVersion;
    if (highest < hello.minVersion || highest < kMinSupportedProtocolVersion) {
      throw SecurityError(
        'version_mismatch',
        'client supports [${hello.minVersion}, ${hello.maxVersion}], '
            'server supports [$kMinSupportedProtocolVersion, '
            '$kProtocolVersion]',
      );
    }
    return highest;
  }

  void _cleanupHandshakeKeys() {
    _handshakeSend?.dispose();
    _handshakeReceive?.dispose();
    Primitives.wipe(_masterIkm);
    Primitives.wipe(_sharedEphemeral);
  }
}

/// Cryptographically secure random bytes.
///
/// `Random.secure()` is backed by the OS CSPRNG on every platform RemoteLink
/// targets — `BCryptGenRandom`, `/dev/urandom`, `SecRandomCopyBytes`. Used in
/// preference to the `cryptography` package's fast generator, which is
/// explicitly documented as not suitable for key material.
Uint8List _randomBytes(int length) {
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}
