import 'dart:math';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';

import 'primitives.dart';
import 'session_cipher.dart';

/// The client must keep both fields together; the opaque ticket alone cannot
/// prove possession of the session that received it.
final class ClientResumption {
  ClientResumption({required this.ticket, required this.secret});
  final Uint8List ticket;
  final Uint8List secret;
}

final class OpenedTicket {
  OpenedTicket(
      {required this.peerKey, required this.tier, required this.secret});
  final Uint8List peerKey;
  final int tier;
  final Uint8List secret;
}

/// Process-lifetime ticket keys and replay state. The service must create a new
/// instance on restart; persisting either keys or consumed IDs would turn a
/// short-lived reconnect hint into a durable credential.
final class ResumptionTickets {
  ResumptionTickets({required this.clock}) : _current = _random(32);
  final Clock clock;
  Uint8List _current;
  Uint8List? _previous;
  int _generation = 0;
  DateTime? _rotatedAt;
  final Set<String> _used = <String>{};
  final Set<String> _previousUsed = <String>{};

  /// Erase process-local key material when the listener stops.
  void dispose() {
    _current.fillRange(0, _current.length, 0);
    _previous?.fillRange(0, _previous!.length, 0);
    _used.clear();
    _previousUsed.clear();
  }

  void _rotate() {
    final now = clock.now();
    _rotatedAt ??= now;
    while (now.difference(_rotatedAt!) >= const Duration(hours: 1)) {
      _previous?.fillRange(0, _previous!.length, 0);
      _previous = _current;
      _current = _random(32);
      _generation++;
      _previousUsed
        ..clear()
        ..addAll(_used);
      _used.clear();
      _rotatedAt = _rotatedAt!.add(const Duration(hours: 1));
    }
  }

  /// Bind the current grant and session secret into an opaque, short-lived
  /// credential. Re-reading the grant at presentation prevents a later
  /// downgrade from being bypassed by an earlier ticket.
  Future<Uint8List> issue(
      {required Uint8List peerKey,
      required int tier,
      required Uint8List secret}) async {
    if (peerKey.length != 32 || secret.length != 32 || tier < 1 || tier > 255) {
      throw ArgumentError('invalid ticket peer key, tier, or secret');
    }
    _rotate();
    final id = _random(16);
    final data = Uint8List(89)..setRange(0, 32, peerKey);
    data[32] = tier;
    ByteData.sublistView(data)
        .setUint64(33, clock.now().toUtc().millisecondsSinceEpoch);
    data.setRange(41, 73, secret);
    data.setRange(73, 89, id);
    final header = ByteData(8)..setUint64(0, _generation);
    final nonce = _random(12);
    final sealed = await Primitives.sealAtNonce(
        key: _current,
        nonce: nonce,
        plaintext: data,
        aad: header.buffer.asUint8List());
    return Uint8List.fromList(
        <int>[...header.buffer.asUint8List(), ...nonce, ...sealed]);
  }

  /// Returns null for every rejection, giving callers a single fallback path.
  /// The ID is consumed only after the proof MAC and trust lookup succeed.
  Future<OpenedTicket?> open(Uint8List ticket, Uint8List nonce, Uint8List proof,
      Future<bool> Function(Uint8List, int) trusted) async {
    _rotate();
    if (ticket.length != 125 || nonce.length != 32 || proof.length != 32) {
      return null;
    }
    final generation = ByteData.sublistView(ticket).getUint64(0);
    final key = generation == _generation
        ? _current
        : generation + 1 == _generation
            ? _previous
            : null;
    if (key == null) return null;
    Uint8List data;
    try {
      data = await Primitives.openAtNonce(
          key: key,
          nonce: ticket.sublist(8, 20),
          sealed: ticket.sublist(20),
          aad: ticket.sublist(0, 8));
    } on SecurityError {
      return null;
    }
    if (data.length != 89) return null;
    final issued = DateTime.fromMillisecondsSinceEpoch(
        ByteData.sublistView(data).getUint64(33),
        isUtc: true);
    final age = clock.now().toUtc().difference(issued);
    if (age.isNegative || age > const Duration(hours: 24)) return null;
    final secret = Uint8List.fromList(data.sublist(41, 73));
    final expected =
        await Primitives.mac(key: secret, data: <int>[...ticket, ...nonce]);
    if (!Primitives.constantTimeEquals(expected, proof)) return null;
    final id = data.sublist(73, 89).join(',');
    final peer = Uint8List.fromList(data.sublist(0, 32));
    final tier = data[32];
    try {
      if (!await trusted(peer, tier)) return null;
    } on Object {
      // A temporarily unavailable trust store is a rejection, never consent.
      return null;
    }
    // No await may separate this check from insertion: concurrent sockets can
    // present the same ticket while both trust lookups are in flight.
    _rotate();
    if (generation != _generation && generation + 1 != _generation) {
      return null;
    }
    if (_used.contains(id) || _previousUsed.contains(id)) return null;
    _used.add(id);
    return OpenedTicket(peerKey: peer, tier: tier, secret: secret);
  }
}

/// The salt is frozen after both ephemeral keys are known, before either side
/// derives keys. A server proof authenticates that exact transcript; no app
/// data is accepted until the client verifies it.
abstract final class ResumeKeys {
  static Future<Uint8List> transcript(
          List<int> ticket,
          List<int> nonce,
          List<int> clientEphemeral,
          List<int> serverEphemeral,
          List<int> negotiatedCapabilities) =>
      Primitives.sha256(<int>[
        ...'rl1 resume'.codeUnits,
        ...ticket,
        ...nonce,
        ...clientEphemeral,
        ...serverEphemeral,
        ...negotiatedCapabilities,
      ]);

  static Future<Uint8List> serverProof(
          List<int> secret, List<int> transcript) =>
      Primitives.mac(
          key: secret, data: <int>[...transcript, ...'server'.codeUnits]);

  static Future<SessionKeys> derive(
      {required List<int> secret,
      required Uint8List shared,
      required List<int> transcript,
      required bool client}) async {
    final ikm = <int>[...secret, ...shared];
    final c2s = await Primitives.hkdf(
        secret: ikm, salt: transcript, info: 'rl1 resume c2s');
    final s2c = await Primitives.hkdf(
        secret: ikm, salt: transcript, info: 'rl1 resume s2c');
    return SessionKeys(
      send: DirectionalCipher(
          key: client ? c2s : s2c, label: client ? 'c2s' : 's2c'),
      receive: DirectionalCipher(
          key: client ? s2c : c2s, label: client ? 's2c' : 'c2s'),
      resumptionSecret: await Primitives.hkdf(
          secret: ikm, salt: transcript, info: 'rl1 resume next'),
      exporterSecret: await Primitives.hkdf(
          secret: ikm, salt: transcript, info: 'rl1 resume exporter'),
    );
  }
}

Uint8List _random(int length) {
  final source = Random.secure();
  return Uint8List.fromList(
      List<int>.generate(length, (_) => source.nextInt(256)));
}
