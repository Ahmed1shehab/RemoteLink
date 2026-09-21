import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import 'phone_host_service.dart';

/// Storage key for whether this phone makes itself findable.
const String _receivingKey = 'remotelink.host.receiving';

/// Whether this phone offers itself to nearby devices, persisted.
///
/// On by default. The feature is worth nothing if it has to be switched on
/// before it can be used — the person who wants to receive a photo is
/// mid-conversation with the person sending it, and "open Settings first" is
/// where that conversation stops. Nothing arrives unasked regardless: an
/// unknown device still has to be confirmed by six digits, and a known one
/// still has to have its transfer accepted.
///
/// The switch exists for the case the default cannot cover — a phone on a
/// network its owner does not trust, where being listed at all is the thing
/// they object to.
final class ReceivingNotifier extends StateNotifier<bool> {
  ReceivingNotifier(this._ref) : super(true) {
    unawaited(_load());
  }

  final Ref _ref;

  Future<void> _load() async {
    final storage = await _ref.read(identityStoreProvider.future);
    final stored = await storage.read(_receivingKey);
    if (stored == null) return;
    state = stored == 'true';
  }

  Future<void> setReceiving(bool enabled) async {
    if (state == enabled) return;
    state = enabled;
    final storage = await _ref.read(identityStoreProvider.future);
    await storage.write(_receivingKey, '$enabled');
  }
}

final receivingProvider = StateNotifierProvider<ReceivingNotifier, bool>(
  ReceivingNotifier.new,
);

/// The listening half of this phone.
///
/// Created once and kept for the life of the app. Whether it is actually
/// listening is [receivingProvider]'s business — see [phoneHostRunnerProvider]
/// — because tearing the object down and rebuilding it on a toggle would drop
/// every connected device to change a preference.
final phoneHostServiceProvider = FutureProvider<PhoneHostService>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  final trustStore = await ref.watch(trustStoreProvider.future);

  final service = PhoneHostService(
    identity: identity,
    trustStore: trustStore,
    clock: ref.watch(clockProvider),
    // Read at call time rather than captured, so renaming this phone in
    // Settings changes what the next announcement says instead of what the
    // next launch says.
    describeName: () => ref.read(deviceNameProvider),
    onTrustChanged: () async {
      final store = await ref.read(trustStoreProvider.future);
      await persistTrustStore(
        store,
        await ref.read(identityStoreProvider.future),
      );
      ref.invalidate(trustedPeersProvider);
    },
  );

  ref.onDispose(service.dispose);
  return service;
});

/// Starts and stops the host as the preference and the platform allow.
///
/// Watched at the root of the app rather than owned by a screen, for the reason
/// every other root-level listener here is: a device sending a file does not
/// wait for the receiving phone to be looking at the right tab.
///
/// The lifecycle half is deliberately one-directional. Backgrounding does not
/// stop the host — a user who leaves the app to *pick* the file they are about
/// to send would otherwise disconnect the device they are sending to. iOS takes
/// the listening socket away regardless, which is the platform's decision and
/// not this app's, so the listener exists to put it back on resume rather than
/// to take it away on pause.
final phoneHostRunnerProvider = Provider<void>((ref) {
  final wanted = ref.watch(receivingProvider);

  Future<void> apply() async {
    final service = await ref.read(phoneHostServiceProvider.future);
    if (wanted) {
      await service.start();
    } else {
      await service.stop();
    }
  }

  unawaited(apply());

  final listener = AppLifecycleListener(
    onResume: () {
      if (ref.read(receivingProvider)) unawaited(apply());
    },
  );
  ref.onDispose(listener.dispose);
});

/// Devices currently connected to this phone.
final inboundLinksProvider = StreamProvider<List<InboundLink>>((ref) async* {
  final service = await ref.watch(phoneHostServiceProvider.future);
  // The snapshot first: a screen that opens after a device connected would
  // otherwise show nothing until that device did something.
  yield service.links;
  yield* service.linkChanges;
});

/// Storage key for whether a trusted device is asked about on each connection.
const String _askBeforeConnectingKey = 'remotelink.host.askBeforeConnecting';

/// Whether a device this phone already trusts is asked about each time it
/// connects, persisted.
///
/// On by default, unlike [receivingProvider]'s neighbours in Settings. Pairing
/// is a promise about a device, not a standing invitation to whoever is holding
/// it, and a phone is handed around far more than a computer is.
final class AskBeforeConnectingNotifier extends StateNotifier<bool> {
  AskBeforeConnectingNotifier(this._ref) : super(true) {
    unawaited(_load());
  }

  final Ref _ref;

  Future<void> _load() async {
    final storage = await _ref.read(identityStoreProvider.future);
    final stored = await storage.read(_askBeforeConnectingKey);
    if (stored == null) return;
    if (!mounted) return;
    state = stored == 'true';
    await _apply(state);
  }

  Future<void> set({required bool enabled}) async {
    if (state == enabled) return;
    state = enabled;
    final storage = await _ref.read(identityStoreProvider.future);
    await storage.write(_askBeforeConnectingKey, '$enabled');
    await _apply(enabled);
  }

  /// Pushes the answer at the running host, not only at the next launch.
  Future<void> _apply(bool enabled) async {
    final service = await _ref.read(phoneHostServiceProvider.future);
    service.asksBeforeConnecting = enabled;
  }
}

final askBeforeConnectingProvider =
    StateNotifierProvider<AskBeforeConnectingNotifier, bool>(
  AskBeforeConnectingNotifier.new,
);

/// Trusted devices waiting for someone to allow the connection.
final inboundConnectionsProvider =
    StreamProvider<List<PendingInboundConnection>>((ref) async* {
  final service = await ref.watch(phoneHostServiceProvider.future);
  yield service.pendingConnections;
  yield* service.pendingConnectionChanges;
});

/// Devices waiting at the door.
final inboundPairingsProvider =
    StreamProvider<List<PendingInboundPairing>>((ref) async* {
  final service = await ref.watch(phoneHostServiceProvider.future);
  yield service.pending;
  yield* service.pendingChanges;
});

/// Connected devices this phone could be told to stop asking about.
final inboundRememberProvider =
    StreamProvider<List<PendingInboundRemember>>((ref) async* {
  final service = await ref.watch(phoneHostServiceProvider.future);
  yield service.pendingRemembers;
  yield* service.rememberChanges;
});

/// Allowed messages arriving from devices connected to this phone.
final inboundMessagesProvider = StreamProvider<InboundMessage>((ref) async* {
  final service = await ref.watch(phoneHostServiceProvider.future);
  yield* service.messages;
});

/// Whether the host is actually listening, as opposed to merely wanted.
///
/// A separate answer from [receivingProvider] because the two genuinely differ:
/// the preference is on and the bind failed, or the preference was just flipped
/// and the socket is still coming up. A screen that reports the preference as
/// though it were the state tells the user they are findable when they are not.
/// Deliberately does not watch [phoneHostRunnerProvider]. Reading a state must
/// not create it: the runner is what binds the socket, and a screen that
/// merely *reports* whether this phone is findable would otherwise make it
/// findable by being opened. The root owns the lifecycle; this only looks.
final receivingLiveProvider = Provider<bool>((ref) {
  // Rebuilt whenever a link appears or goes, which is the cheapest live signal
  // available; the socket does not announce itself.
  ref.watch(inboundLinksProvider);
  return ref.watch(phoneHostServiceProvider).valueOrNull?.isRunning ?? false;
});

/// Where a link came from.
enum LinkOrigin {
  /// This phone dialled out. The peer is a computer, or a phone that was
  /// hosting when this one went looking.
  outbound,

  /// The peer dialled in. It found this phone and asked.
  inbound,
}

/// A peer this phone can send to right now.
///
/// The app used to have exactly one of these and did not need a name for it:
/// `client.session`, the computer being controlled. Once a phone can listen,
/// there can be several at once and they are not interchangeable — a transfer
/// has to go out over the session its peer is actually on, and sending it over
/// "the" session would deliver one phone's file to a different device under the
/// first one's name.
///
/// Deliberately without the session. This is what a screen is given, and a
/// screen has no business holding a transport object: it would be the only
/// reason `Session` appeared in the widget layer, and the only reason the send
/// UI could not be built in a test — a `Session` cannot be constructed without
/// a socket, so every widget test would have had to open one to render a list
/// of names. `MobileTransferController` resolves the session from the peer id
/// at the moment it sends, which is also the only moment the answer is still
/// true.
@immutable
final class PeerLink {
  const PeerLink({
    required this.id,
    required this.name,
    required this.platform,
    required this.origin,
  });

  final DeviceId id;
  final String name;
  final PlatformKind platform;
  final LinkOrigin origin;

  /// Whether the peer is a phone or tablet rather than a computer.
  ///
  /// Asked in the UI to choose an icon and a verb, never to decide what may be
  /// sent — the capability intersection already did that, and a platform field
  /// is something the peer told us.
  bool get isHandheld =>
      platform == PlatformKind.android || platform == PlatformKind.ios;
}

/// Every peer this phone can reach, whichever end opened the connection.
final peerLinksProvider = Provider<List<PeerLink>>((ref) {
  final links = <PeerLink>[];

  final outbound = ref.watch(_outboundLinkProvider);
  if (outbound != null) links.add(outbound);

  final inbound =
      ref.watch(inboundLinksProvider).valueOrNull ?? const <InboundLink>[];
  for (final link in inbound) {
    // A peer reached both ways is one peer. It happens when two phones each
    // discover the other and both dial: the sessions are distinct, the device
    // is not, and showing it twice would ask the user to choose between two
    // rows that do the same thing.
    if (links.any((existing) => existing.id == link.peerId)) continue;
    if (!link.session.isEstablished) continue;
    links.add(
      PeerLink(
        id: link.peerId,
        name: link.name,
        platform: link.platform,
        origin: LinkOrigin.inbound,
      ),
    );
  }

  return List<PeerLink>.unmodifiable(links);
});

/// The computer or phone this app dialled, if the session is usable.
///
/// The identity message is preferred and the trust store is the fallback, in
/// that order, because `DeviceInfoMessage` arrives a moment *after* the session
/// is established. Watching only the message left the send target empty for the
/// first second of every connection; watching only the trust store would show a
/// stale name after a rename.
final _outboundLinkProvider = Provider<PeerLink?>((ref) {
  // The state stream is watched first, and it is not decoration. `session` is a
  // plain field on the client, so nothing about reading it makes Riverpod
  // recompute — without this line the provider is evaluated once, on the build
  // where there is no session yet, and caches "no target" for the life of the
  // app.
  final state = ref.watch(clientStateProvider).valueOrNull;
  if (state != ClientState.connected) return null;

  final client = ref.watch(clientProvider).valueOrNull;
  final session = client?.session;
  if (session == null || !session.isEstablished) return null;

  final reported = ref.watch(connectedPeerProvider).valueOrNull;
  if (reported != null && reported.id == session.peerId) {
    return PeerLink(
      id: reported.id,
      name: reported.name,
      platform: reported.platform,
      origin: LinkOrigin.outbound,
    );
  }

  final peers = ref.watch(trustedPeersProvider).valueOrNull;
  final known = peers?.where((peer) => peer.id == session.peerId).firstOrNull;
  return PeerLink(
    id: session.peerId,
    name: known?.name ?? session.peerId.short,
    platform: known?.platform ?? PlatformKind.unknown,
    origin: LinkOrigin.outbound,
  );
});

/// All device IDs currently connected to this phone, whether outbound or inbound.
final connectedDeviceIdsProvider = Provider<Set<DeviceId>>((ref) {
  final ids = <DeviceId>{};
  final outboundId = ref.watch(connectedDeviceIdProvider);
  if (outboundId != null) ids.add(outboundId);

  final inbound =
      ref.watch(inboundLinksProvider).valueOrNull ?? const <InboundLink>[];
  for (final link in inbound) {
    if (link.session.isEstablished) {
      ids.add(link.peerId);
    }
  }
  return Set<DeviceId>.unmodifiable(ids);
});

/// The capabilities of the current session or the target being connected to.
///
/// Resolves capabilities ahead of the handshake completion so that phone-to-phone
/// connections do not briefly render desktop-only tabs (like the Touchpad)
/// during loading.
final activeCapabilitiesProvider = Provider<Capabilities?>((ref) {
  // 1. If an established outbound session already has capabilities, use them.
  final client = ref.watch(clientProvider).valueOrNull;
  final sessionCap = client?.session?.capabilities;
  if (sessionCap != null) return sessionCap;

  // 2. If connected via an inbound link, it is a phone host connection.
  final inbound =
      ref.watch(inboundLinksProvider).valueOrNull ?? const <InboundLink>[];
  if (inbound.any((link) => link.session.isEstablished)) {
    return kPhoneHostCapabilities;
  }

  // 3. Inspect target being connected to.
  final target = client?.target;
  if (target != null) {
    // 3a. Target port matches the phone host port.
    if (target.port == kPhoneHostPort) {
      return kPhoneHostCapabilities;
    }

    // 3b. Discovered beacon capabilities for target device.
    final discovered = ref.watch(discoveredDevicesProvider).valueOrNull;
    if (discovered != null) {
      for (final device in discovered) {
        if ((target.deviceId != null && device.id == target.deviceId) ||
            (device.address == target.host && device.port == target.port)) {
          return device.beacon.capabilities;
        }
      }
    }

    // 3c. Trusted peer platform is a phone.
    final peers = ref.watch(trustedPeersProvider).valueOrNull;
    if (peers != null && target.deviceId != null) {
      for (final peer in peers) {
        if (peer.id == target.deviceId) {
          if (peer.platform == PlatformKind.android ||
              peer.platform == PlatformKind.ios) {
            return kPhoneHostCapabilities;
          }
        }
      }
    }
  }

  // 4. Inbound peer link is handheld.
  final peerLinks = ref.watch(peerLinksProvider);
  if (peerLinks.any((p) => p.isHandheld)) {
    return kPhoneHostCapabilities;
  }

  return null;
});
