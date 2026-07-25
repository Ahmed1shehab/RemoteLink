import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';

/// How long to wait for an automatic connection before giving up and showing
/// the device list.
///
/// Deliberately short. If the computer is asleep or on another network, the
/// user needs the list quickly; a long spinner is worse than no attempt at all,
/// because it blocks the manual path they could have taken immediately.
const Duration kAutoConnectTimeout = Duration(seconds: 6);

/// Which paired computer to reconnect to on launch, if any.
///
/// Picks the most recently used, which is almost always the right guess: people
/// have one computer they control, and those with several return to the one
/// they were just using. Ties break on pairing time.
///
/// Returns `null` when nothing is paired, or when the best candidate has no
/// address to dial and discovery has not found it — attempting a connection we
/// know cannot succeed just delays the list.
final autoConnectTargetProvider =
    FutureProvider<ConnectionTarget?>((ref) async {
  final peers = await ref.watch(trustedPeersProvider.future);
  if (peers.isEmpty) return null;

  final discovered = ref.watch(discoveredDevicesProvider).valueOrNull ??
      const <DiscoveredDevice>[];
  final live = <String, DiscoveredDevice>{
    for (final device in discovered) device.id.value: device,
  };

  final ranked = <TrustedPeer>[...peers]..sort((a, b) {
      // A computer currently announcing itself beats one we only have a
      // remembered address for, however recent that memory is.
      final aLive = live.containsKey(a.id.value);
      final bLive = live.containsKey(b.id.value);
      if (aLive != bLive) return aLive ? -1 : 1;
      return (b.lastSeenAt ?? b.pairedAt).compareTo(a.lastSeenAt ?? a.pairedAt);
    });

  for (final peer in ranked) {
    final device = live[peer.id.value];
    final host = device?.address ?? peer.lastAddress;
    if (host == null) continue;

    return ConnectionTarget(
      host: host,
      port: device?.port ?? kDefaultServicePort,
      deviceId: peer.id,
      // Always present here: this peer is in the trust store, so the handshake
      // verifies against the stored key rather than trusting on first use.
      serverPublicKey: peer.publicKey,
      displayName: peer.name,
    );
  }
  return null;
});

/// Where an automatic connection attempt has got to.
enum AutoConnectStage {
  /// Still working out whether there is anything to connect to.
  deciding,

  /// Nothing paired, or no reachable address. Show the list.
  nothingToDo,

  /// Dialling.
  connecting,

  /// Connected; the caller should show the touchpad.
  connected,

  /// The attempt failed. Show the list so the user can choose.
  failed,
}

/// Runs one automatic connection attempt per app launch.
///
/// Deliberately *one*. Retrying in a loop here would fight the reconnect
/// supervisor inside [RemoteLinkClient], which already handles a connection
/// that drops after being established. This exists only to answer "should we
/// skip the device list entirely?", and once it has an answer its job is done.
final class AutoConnectController extends StateNotifier<AutoConnectStage> {
  AutoConnectController(this._ref) : super(AutoConnectStage.deciding);

  final Ref _ref;
  bool _attempted = false;

  final Log _log = Log.scoped('mobile.autoconnect');

  /// Attempts the connection. Safe to call repeatedly; only the first runs.
  Future<void> attempt() async {
    if (_attempted) return;
    _attempted = true;

    final target = await _ref.read(autoConnectTargetProvider.future);
    if (target == null) {
      state = AutoConnectStage.nothingToDo;
      return;
    }

    state = AutoConnectStage.connecting;
    _log.info(
      'reconnecting to the last used computer',
      fields: <String, Object?>{'target': target.toString()},
    );

    final client = await _ref.read(clientProvider.future);
    try {
      await client.connect(target);
      await client.waitUntilConnected(timeout: kAutoConnectTimeout);
      state = AutoConnectStage.connected;
      await _touch(target);
    } on Object catch (e) {
      // Not an error worth showing. The computer being off is the ordinary
      // case, and the device list is a perfectly good place to land.
      _log.info(
        'automatic connection did not succeed; showing the device list',
        fields: <String, Object?>{'reason': e.toString()},
      );
      await client.disconnect();
      state = AutoConnectStage.failed;
    }
  }

  /// Records that this computer was reached, so the next launch prefers it.
  Future<void> _touch(ConnectionTarget target) async {
    final id = target.deviceId;
    if (id == null) return;

    final store = await _ref.read(trustStoreProvider.future);
    final peer = await store.findById(id);
    if (peer == null) return;

    await store.upsert(
      peer.copyWith(lastSeenAt: DateTime.now(), lastAddress: target.host),
    );
    await persistTrustStore(
      store,
      await _ref.read(identityStoreProvider.future),
    );
  }

  /// Called when the user deliberately leaves the touchpad, so returning to the
  /// device list does not immediately bounce them back into a session.
  void cancel() {
    _attempted = true;
    state = AutoConnectStage.nothingToDo;
  }
}

final autoConnectProvider =
    StateNotifierProvider<AutoConnectController, AutoConnectStage>(
  AutoConnectController.new,
);
