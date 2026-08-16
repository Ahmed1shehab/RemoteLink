import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/devices/auto_connect.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

/// Provider state shared by device-list widget tests.
List<Override> mobileDeviceListOverrides({
  required bool discoveryOperational,
}) {
  final discovery = FakeDiscoveryBackend(
    isOperational: discoveryOperational,
  );
  final trustStore = InMemoryTrustStore();

  return <Override>[
    discoveryProvider.overrideWith((ref) async => discovery),
    trustStoreProvider.overrideWith((ref) async => trustStore),
    identityProvider.overrideWith(
      (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
    ),
    autoConnectProvider.overrideWith((ref) {
      final controller = AutoConnectController(ref)..cancel();
      return controller;
    }),
  ];
}

/// Inert discovery implementation: no sockets, Bonjour, or plugin channels.
final class FakeDiscoveryBackend implements DiscoveryBackend {
  FakeDiscoveryBackend({required this.isOperational});

  @override
  final bool isOperational;

  @override
  List<DiscoveredDevice> get current => const <DiscoveredDevice>[];

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
