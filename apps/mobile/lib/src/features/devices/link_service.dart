import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';

/// Keeps this phone's link alive while the app is off screen.
///
/// Android freezes a backgrounded app and takes its sockets with it: the
/// session dies within seconds of the app leaving the screen, and every
/// reconnect then fails at the TCP layer until the app is opened again. A file
/// transfer therefore cannot survive the user switching to another app, which
/// on a phone is most of the time.
///
/// A foreground service is the platform's sanctioned answer, and this is the
/// seam to it. It is deliberately thin — starting and stopping a service that
/// hosts nothing — because the connection stays in this isolate. See
/// `LinkService.kt` for why a second, headless engine was not the answer.
///
/// The strings are passed in rather than composed on the far side, so all of
/// the app's copy stays in one language and within reach of any later
/// localisation.
abstract interface class LinkService {
  /// Whether this platform has a background service at all.
  ///
  /// Asked of the service rather than of `Platform`, so that the settings UI
  /// and a test are looking at the same answer. A switch offered where nothing
  /// can honour it is worse than no switch.
  bool get isSupported;

  /// Shows the notification and holds the process open.
  Future<void> start({
    required String title,
    required String body,
    required String disconnectLabel,
  });

  /// Takes both away.
  Future<void> stop();

  /// Opens the platform's battery-optimisation screen, returning false when
  /// there is none to open.
  Future<bool> openBatterySettings();

  /// Fires when the user presses Disconnect on the notification.
  ///
  /// The service cannot honour that itself — this isolate owns the connection —
  /// so it asks, and the answer comes back through here.
  Stream<void> get disconnectRequests;
}

/// The real one, backed by the service in the Android runner.
final class PlatformLinkService implements LinkService {
  PlatformLinkService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'disconnectRequested') _disconnects.add(null);
    });
  }

  static const MethodChannel _channel =
      MethodChannel('com.remotelink.app/link_service');

  static final Log _log = Log.scoped('mobile.link.service');

  final StreamController<void> _disconnects =
      StreamController<void>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Stream<void> get disconnectRequests => _disconnects.stream;

  @override
  Future<void> start({
    required String title,
    required String body,
    required String disconnectLabel,
  }) =>
      _invoke('start', <String, Object?>{
        'title': title,
        'body': body,
        'disconnectLabel': disconnectLabel,
      });

  @override
  Future<void> stop() => _invoke('stop');

  @override
  Future<bool> openBatterySettings() async {
    try {
      return await _channel.invokeMethod<bool>('openBatterySettings') ?? false;
    } on PlatformException catch (e) {
      _log.debug(() => 'could not open the battery settings: ${e.message}');
      return false;
    }
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (e) {
      // The link is what matters and it is not held up by this. A service that
      // would not start costs the user a session that dies in the background —
      // the behaviour they had before this existed — not a session that fails
      // now, so it is logged and stepped over.
      _log.warn('the background link service refused $method', error: e);
    } on MissingPluginException {
      _log.debug(() => 'no background link service on this platform');
    }
  }
}

/// A service that does nothing, for every platform that has no equivalent.
///
/// iOS is the one that matters: it grants no persistent background networking
/// to an app of this kind, and there is no entitlement, service type or
/// background mode that changes it for a local-network remote control. The
/// phone app therefore behaves differently on the two platforms, and the honest
/// way to ship that is to say so in the documentation rather than to build
/// something that looks like a solution.
final class InertLinkService implements LinkService {
  const InertLinkService();

  @override
  bool get isSupported => false;

  @override
  Future<void> start({
    required String title,
    required String body,
    required String disconnectLabel,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<bool> openBatterySettings() async => false;

  @override
  Stream<void> get disconnectRequests => const Stream<void>.empty();
}

/// The service for this platform.
final linkServiceProvider = Provider<LinkService>((ref) {
  if (!Platform.isAndroid) return const InertLinkService();
  return PlatformLinkService();
});

/// Whether the user wants the link held open in the background.
///
/// A preference, not a fact of the app. An ongoing notification is a cost paid
/// by everyone who installs this, including the people who only ever use it
/// with the app open, and a remote control that plants something permanent in
/// the notification shade without asking is one people uninstall.
final backgroundLinkEnabledProvider =
    StateNotifierProvider<BackgroundLinkNotifier, bool>(
  BackgroundLinkNotifier.new,
);

/// Reads and writes [backgroundLinkEnabledProvider]'s stored value.
final class BackgroundLinkNotifier extends StateNotifier<bool> {
  BackgroundLinkNotifier(this._ref) : super(true) {
    unawaited(_load());
  }

  static const String _key = 'background_link_enabled';

  final Ref _ref;

  Future<void> _load() async {
    final storage = await _ref.read(identityStoreProvider.future);
    final stored = await storage.read(_key);
    if (stored != null) state = stored == 'true';
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final storage = await _ref.read(identityStoreProvider.future);
    await storage.write(_key, '$enabled');
    // Applied at once rather than at the next connection. Switching this off
    // is usually someone reacting to the notification in front of them.
    if (!enabled) await _ref.read(linkServiceProvider).stop();
  }
}

/// What to call the computer in the notification.
///
/// The connection target first, not the computer's own reported name: the
/// target survives a session dropping, and a reconnect is precisely when the
/// notification has something to say. `DeviceInfo` only arrives once a session
/// is up, so relying on it would leave the shade saying "Reconnecting to your
/// computer" about a machine the user named themselves.
String _peerName(Ref ref) {
  final target = ref.read(clientProvider).valueOrNull?.target;
  final named = target?.displayName;
  if (named != null && named.isNotEmpty) return named;

  final reported = ref.read(connectedPeerProvider).valueOrNull?.name;
  if (reported != null && reported.isNotEmpty) return reported;

  return target?.host ?? 'your computer';
}

/// Runs the background service for exactly as long as there is a link worth
/// keeping.
///
/// Watched at the app root, because a provider nobody watches is never created
/// and this one has to outlive every screen.
final backgroundLinkProvider = Provider<void>((ref) {
  final service = ref.watch(linkServiceProvider);
  final log = Log.scoped('mobile.link.service');

  // The notification says what the connection is actually doing, never merely
  // that the service is running. A service outliving its session and still
  // claiming "Connected" is the worst outcome this feature can produce.
  void apply(ClientState? state) {
    if (!ref.read(backgroundLinkEnabledProvider)) return;

    final name = _peerName(ref);
    switch (state) {
      case ClientState.connected:
      case ClientState.pairing:
        unawaited(
          service.start(
            title: 'Connected to $name',
            body: 'Remote Link is holding the connection open.',
            disconnectLabel: 'Disconnect',
          ),
        );
      case ClientState.connecting:
      case ClientState.reconnecting:
        // Kept running through a reconnect, which is the entire point: the
        // service is what gives the retry a network to retry on. The wording
        // changes so the shade does not claim a link that is currently down.
        unawaited(
          service.start(
            title: 'Reconnecting to $name',
            body: 'Remote Link lost the connection and is trying again.',
            disconnectLabel: 'Stop',
          ),
        );
      case ClientState.idle:
      case ClientState.failed:
      case null:
        unawaited(service.stop());
    }
  }

  ref.listen<AsyncValue<ClientState>>(
    clientStateProvider,
    (previous, next) => apply(next.valueOrNull),
    fireImmediately: true,
  );

  // Switching the preference back on mid-session should not wait for the next
  // reconnect to take effect.
  ref.listen<bool>(backgroundLinkEnabledProvider, (previous, next) {
    if (next) apply(ref.read(clientStateProvider).valueOrNull);
  });

  final disconnects = service.disconnectRequests.listen((_) async {
    log.info('disconnecting at the notification\'s request');
    final client = ref.read(clientProvider).valueOrNull;
    await client?.disconnect();
    await service.stop();
  });
  ref.onDispose(disconnects.cancel);
});
