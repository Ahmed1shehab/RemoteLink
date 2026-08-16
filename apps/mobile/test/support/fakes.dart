import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/devices/auto_connect.dart';
import 'package:remotelink_mobile/src/features/input/pointer_controller.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

/// In-memory implementation of [IdentityStore] for tests.
final class InMemoryIdentityStore implements IdentityStore {
  InMemoryIdentityStore([Map<String, String>? initial])
      : _values = initial != null
            ? Map<String, String>.from(initial)
            : <String, String>{};

  final Map<String, String> _values;

  Map<String, String> get values => Map<String, String>.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

/// Provider state shared by device-list widget tests.
List<Override> mobileDeviceListOverrides({
  required bool discoveryOperational,
  TrustStore? trustStore,
  RemoteLinkClient? client,
  List<DiscoveredDevice> discovered = const <DiscoveredDevice>[],
  IdentityStore? identityStore,
}) {
  final discovery = FakeDiscoveryBackend(
    isOperational: discoveryOperational,
    current: discovered,
  );
  final peers = trustStore ?? InMemoryTrustStore();
  final storage = identityStore ?? InMemoryIdentityStore();

  return <Override>[
    identityStoreProvider.overrideWith((ref) async => storage),
    discoveryProvider.overrideWith((ref) async => discovery),
    trustStoreProvider.overrideWith((ref) async => peers),
    if (client != null) clientProvider.overrideWith((ref) async => client),
    identityProvider.overrideWith(
      (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
    ),
    autoConnectProvider.overrideWith((ref) {
      final controller = AutoConnectController(ref)..cancel();
      return controller;
    }),
  ];
}

/// Provider state shared by settings widget tests.
List<Override> mobileSettingsOverrides({
  IdentityStore? identityStore,
  TrustStore? trustStore,
  RemoteLinkClient? client,
  DeviceIdentity? identity,
  DiscoveryBackend? discovery,
  bool discoveryOperational = true,
  List<DiscoveredDevice> discovered = const <DiscoveredDevice>[],
  PointerSettings? pointerSettings,
  ClipboardSettings? clipboardSettings,
  String? deviceName,
  MemoryLogSink? memoryLogSink,
}) {
  final storage = identityStore ?? InMemoryIdentityStore();
  final peers = trustStore ?? InMemoryTrustStore();
  final disc = discovery ??
      FakeDiscoveryBackend(
        isOperational: discoveryOperational,
        current: discovered,
      );

  return <Override>[
    identityStoreProvider.overrideWith((ref) async => storage),
    trustStoreProvider.overrideWith((ref) async => peers),
    discoveryProvider.overrideWith((ref) async => disc),
    if (client != null) clientProvider.overrideWith((ref) async => client),
    if (identity != null)
      identityProvider.overrideWith((ref) => identity)
    else
      identityProvider.overrideWith(
        (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
      ),
    if (pointerSettings != null)
      pointerSettingsProvider.overrideWith((ref) {
        final notifier = PointerSettingsNotifier(ref);
        notifier.state = pointerSettings;
        return notifier;
      }),
    if (clipboardSettings != null)
      clipboardSettingsProvider.overrideWith((ref) {
        final notifier = ClipboardSettingsNotifier(ref);
        notifier.state = clipboardSettings;
        return notifier;
      }),
    if (deviceName != null)
      deviceNameProvider.overrideWith((ref) {
        final notifier = DeviceNameNotifier(ref);
        notifier.state = deviceName;
        return notifier;
      }),
    if (memoryLogSink != null)
      memoryLogSinkProvider.overrideWithValue(memoryLogSink),
    autoConnectProvider.overrideWith((ref) {
      final controller = AutoConnectController(ref)..cancel();
      return controller;
    }),
  ];
}

/// Inert discovery implementation: no sockets, Bonjour, or plugin channels.
final class FakeDiscoveryBackend implements DiscoveryBackend {
  FakeDiscoveryBackend({
    required this.isOperational,
    this.current = const <DiscoveredDevice>[],
  });

  @override
  final bool isOperational;

  @override
  final List<DiscoveredDevice> current;

  @override
  Stream<List<DiscoveredDevice>> get devices =>
      const Stream<List<DiscoveredDevice>>.empty();

  @override
  Stream<bool> get operational => const Stream<bool>.empty();

  @override
  Future<void> refresh() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
