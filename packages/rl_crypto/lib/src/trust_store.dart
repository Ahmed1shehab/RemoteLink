import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

import 'identity.dart';
import 'primitives.dart';

/// Persistent record of which devices are allowed to connect.
///
/// The store is the single authority on trust. Nothing else in the codebase may
/// decide that a peer is acceptable — the handshake asks the store, and the
/// store's answer is final.
abstract interface class TrustStore {
  /// Every peer, including revoked ones.
  Future<List<TrustedPeer>> listPeers();

  /// Looks up by device ID.
  Future<TrustedPeer?> findById(DeviceId id);

  /// Looks up by static public key.
  ///
  /// This is the lookup the handshake uses. Keying on the key rather than the
  /// ID matters: the ID is derived from the key, so an attacker who claims
  /// someone else's ID still fails here, and there is no window where a
  /// mismatched pair could be treated as a match.
  Future<TrustedPeer?> findByPublicKey(Uint8List staticPublicKey);

  /// Adds or replaces a peer.
  Future<void> upsert(TrustedPeer peer);

  /// Marks a peer revoked, keeping the record so future attempts get a
  /// definitive answer instead of being routed into pairing again.
  Future<void> revoke(DeviceId id);

  /// Permanently removes a peer.
  Future<void> forget(DeviceId id);

  /// Emits whenever the set of peers changes, so device-manager UI stays live.
  Stream<void> get changes;

  Future<void> dispose();
}

/// In-memory store. Used in tests and by the mobile app when the user has opted
/// out of persisting trust.
final class InMemoryTrustStore implements TrustStore {
  final Map<String, TrustedPeer> _peers = <String, TrustedPeer>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<TrustedPeer>> listPeers() async => _peers.values.toList();

  @override
  Future<TrustedPeer?> findById(DeviceId id) async => _peers[id.value];

  @override
  Future<TrustedPeer?> findByPublicKey(Uint8List staticPublicKey) async {
    for (final peer in _peers.values) {
      if (Primitives.constantTimeEquals(peer.publicKey, staticPublicKey)) {
        return peer;
      }
    }
    return null;
  }

  @override
  Future<void> upsert(TrustedPeer peer) async {
    _peers[peer.id.value] = peer;
    _notify();
  }

  @override
  Future<void> revoke(DeviceId id) async {
    final peer = _peers[id.value];
    if (peer == null) return;
    _peers[id.value] = peer.copyWith(revoked: true);
    _notify();
  }

  @override
  Future<void> forget(DeviceId id) async {
    if (_peers.remove(id.value) != null) _notify();
  }

  void _notify() {
    if (_changes.hasListener) _changes.add(null);
  }

  @override
  Future<void> dispose() => _changes.close();
}

/// JSON-file-backed trust store.
///
/// The file holds public keys and metadata only — never the local private key,
/// which lives in the OS keystore. That separation is deliberate: the trust
/// file is readable by anyone with access to the user's profile, and it should
/// be, because leaking a list of public keys costs nothing while leaking a
/// private key costs everything.
///
/// Writes go to a temporary file and are then renamed over the original.
/// `rename` is atomic on both NTFS and APFS, so a crash mid-write cannot leave
/// a truncated trust file — which would otherwise silently un-pair every device
/// the user owns.
final class FileTrustStore implements TrustStore {
  FileTrustStore(this.file);

  final File file;

  final Map<String, TrustedPeer> _peers = <String, TrustedPeer>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool _loaded = false;

  /// Bumped when the on-disk shape changes, so a future build can migrate.
  static const int _schemaVersion = 1;

  @override
  Stream<void> get changes => _changes.stream;

  /// Reads the file into memory. Safe to call repeatedly.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    if (!file.existsSync()) return;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;

      final version = decoded['version'];
      if (version is! int || version > _schemaVersion) {
        throw SecurityError(
          'trust_store_version',
          'trust store schema $version is newer than supported '
              '$_schemaVersion; refusing to read it',
        );
      }

      final peers = decoded['peers'];
      if (peers is! List) return;
      for (final entry in peers) {
        if (entry is! Map<String, dynamic>) continue;
        final peer = _decodePeer(entry);
        if (peer != null) _peers[peer.id.value] = peer;
      }
    } on FormatException {
      // A corrupt trust file must not brick the app, and it must not be
      // ignored either. Starting empty fails *closed* — nothing is trusted, so
      // the user re-pairs, which is annoying but safe. The damaged file is kept
      // aside rather than overwritten so it can be inspected or recovered.
      _peers.clear();
      final quarantine = File(
        '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
      );
      await file.rename(quarantine.path);
      Log.scoped('crypto.trust_store').error(
        'trust store was unreadable and has been quarantined; '
        'all devices must re-pair',
        fields: <String, Object?>{'quarantined': quarantine.path},
      );
    }
  }

  @override
  Future<List<TrustedPeer>> listPeers() async {
    await load();
    return _peers.values.toList();
  }

  @override
  Future<TrustedPeer?> findById(DeviceId id) async {
    await load();
    return _peers[id.value];
  }

  @override
  Future<TrustedPeer?> findByPublicKey(Uint8List staticPublicKey) async {
    await load();
    for (final peer in _peers.values) {
      if (Primitives.constantTimeEquals(peer.publicKey, staticPublicKey)) {
        return peer;
      }
    }
    return null;
  }

  @override
  Future<void> upsert(TrustedPeer peer) async {
    await load();
    _peers[peer.id.value] = peer;
    await _persist();
  }

  @override
  Future<void> revoke(DeviceId id) async {
    await load();
    final peer = _peers[id.value];
    if (peer == null) return;
    _peers[id.value] = peer.copyWith(revoked: true);
    await _persist();
  }

  @override
  Future<void> forget(DeviceId id) async {
    await load();
    if (_peers.remove(id.value) == null) return;
    await _persist();
  }

  Future<void> _persist() async {
    final payload = <String, Object?>{
      'version': _schemaVersion,
      'peers': _peers.values.map(_encodePeer).toList(),
    };

    final directory = file.parent;
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    await temporary.rename(file.path);

    if (_changes.hasListener) _changes.add(null);
  }

  static Map<String, Object?> _encodePeer(TrustedPeer peer) =>
      <String, Object?>{
        'id': peer.id.value,
        'publicKey': base64Encode(peer.publicKey),
        'name': peer.name,
        'platform': peer.platform.wireValue,
        'pairedAt': peer.pairedAt.toUtc().toIso8601String(),
        'permissionTier': peer.permissionTier,
        'lastSeenAt': peer.lastSeenAt?.toUtc().toIso8601String(),
        'lastAddress': peer.lastAddress,
        'revoked': peer.revoked,
      };

  static TrustedPeer? _decodePeer(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawKey = json['publicKey'];
    if (rawId is! String || rawKey is! String) return null;

    final id = DeviceId.tryParse(rawId);
    if (id == null) return null;

    final publicKey = Uint8List.fromList(base64Decode(rawKey));
    if (publicKey.length != Primitives.keyLength) return null;

    final rawPairedAt = json['pairedAt'];
    final rawLastSeen = json['lastSeenAt'];

    return TrustedPeer(
      id: id,
      publicKey: publicKey,
      name: json['name'] is String ? json['name'] as String : id.short,
      platform: PlatformKind.fromWire(
        json['platform'] is int ? json['platform'] as int : 0,
      ),
      pairedAt: rawPairedAt is String
          ? (DateTime.tryParse(rawPairedAt) ?? DateTime.now())
          : DateTime.now(),
      permissionTier:
          json['permissionTier'] is int ? json['permissionTier'] as int : 2,
      lastSeenAt: rawLastSeen is String ? DateTime.tryParse(rawLastSeen) : null,
      lastAddress:
          json['lastAddress'] is String ? json['lastAddress'] as String : null,
      revoked: json['revoked'] == true,
    );
  }

  @override
  Future<void> dispose() => _changes.close();
}

/// Convenience helpers shared by both implementations.
extension TrustStoreQueries on TrustStore {
  /// Peers that may currently connect.
  Future<List<TrustedPeer>> activePeers() async =>
      (await listPeers()).where((peer) => !peer.revoked).toList();

  /// Whether [staticPublicKey] belongs to a peer that may connect right now.
  @useResult
  Future<bool> isTrusted(Uint8List staticPublicKey) async {
    final peer = await findByPublicKey(staticPublicKey);
    return peer != null && !peer.revoked;
  }
}
