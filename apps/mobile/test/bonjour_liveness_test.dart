import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/devices/bonjour_discovery.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

/// The bug this file exists for.
///
/// `BonjourDiscoveryBackend` took a `deviceTimeout` and read it nowhere. The
/// only thing that removed a row was a `discoveryServiceLost` event, and mDNS
/// only sends the goodbye packet that produces one when a service unregisters
/// politely. A desktop that was force-quit, crashed, or had its Wi-Fi pulled
/// never does — so the phone listed a computer that had been off for an hour,
/// and tapping it produced a connection attempt that hung.
void main() {
  DiscoveredDevice deviceAt(String id, String address, DateTime seen) {
    final beacon = Beacon(
      kind: BeaconKind.announce,
      deviceId: DeviceId(id),
      name: id,
      platform: PlatformKind.macos,
      servicePort: kDefaultServicePort,
      protocolVersion: kProtocolVersion,
      publicKeyFingerprint: Uint8List(8),
      capabilities: const Capabilities(0),
    );
    return DiscoveredDevice(
      beacon: beacon,
      address: address,
      firstSeen: seen,
      lastSeen: seen,
    );
  }

  /// A backend whose probes answer from [alive] instead of opening sockets.
  ({
    BonjourDiscoveryBackend backend,
    FakeClock clock,
    List<String> probed,
  }) harness(Set<String> alive) {
    final clock = FakeClock();
    final probed = <String>[];
    final backend = BonjourDiscoveryBackend(
      clock: clock,
      probe: (host, port, timeout) async {
        probed.add(host);
        return alive.contains(host);
      },
    );
    return (backend: backend, clock: clock, probed: probed);
  }

  test('a service that stopped answering is dropped', () async {
    final h = harness(<String>{'192.168.1.10'});
    h.backend
      ..seedForTesting(deviceAt('live', '192.168.1.10', h.clock.now()))
      ..seedForTesting(deviceAt('ghost', '192.168.1.99', h.clock.now()));

    // Past the probe interval, so both are due, but still inside the timeout —
    // one failed probe is not enough to remove a computer that may simply be
    // busy.
    h.clock.advance(kBonjourProbeInterval);
    await h.backend.refresh();
    expect(h.backend.current, hasLength(2));

    // Past the timeout with no successful probe in between.
    h.clock.advance(kBonjourDeviceTimeout);
    await h.backend.refresh();

    expect(
      h.backend.current.map((device) => device.id.value),
      <String>['live'],
      reason: 'the address that answered stays; the one that did not is gone',
    );
  });

  test('a service that keeps answering is never dropped', () async {
    final h = harness(<String>{'192.168.1.10'});
    h.backend.seedForTesting(
      deviceAt('live', '192.168.1.10', h.clock.now()),
    );

    // Far longer than the timeout. Nothing re-announces over DNS-SD, so if the
    // clock were the only input this row would expire on its own — which would
    // delete a perfectly healthy computer from the list.
    for (var i = 0; i < 10; i++) {
      h.clock.advance(kBonjourProbeInterval);
      await h.backend.refresh();
    }

    expect(h.backend.current, hasLength(1));
  });

  test('a service seen moments ago is not probed', () async {
    final h = harness(<String>{});
    h.backend.seedForTesting(deviceAt('fresh', '192.168.1.10', h.clock.now()));

    await h.backend.refresh();

    expect(
      h.probed,
      isEmpty,
      reason: 'a service that just resolved needs no confirming',
    );
    expect(h.backend.current, hasLength(1));
  });

  test('the list is republished when something is dropped', () async {
    final h = harness(<String>{});
    h.backend.seedForTesting(deviceAt('ghost', '192.168.1.99', h.clock.now()));

    final published = h.backend.devices.first;

    h.clock.advance(kBonjourDeviceTimeout + kBonjourProbeInterval);
    await h.backend.refresh();

    expect(await published, isEmpty);
  });
}
