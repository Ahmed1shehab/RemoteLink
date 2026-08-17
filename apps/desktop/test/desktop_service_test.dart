import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// Counts how many times the host was actually asked for metrics.
final class SpySystemInfoBackend implements SystemInfoBackend {
  int metricsCallCount = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<SystemMetrics> metrics() async {
    metricsCallCount++;
    return const SystemMetrics(
      batteryPercent: 90,
      isCharging: true,
      cpuPercent: 10,
      memoryPercent: 50,
      uptimeSeconds: 120,
    );
  }

  @override
  void dispose() {}
}

/// Reports a fixed interface table, so adapter selection can be asserted
/// without depending on the network the test machine is plugged into.
final class FakeNetworkAdapterBackend implements NetworkAdapterBackend {
  FakeNetworkAdapterBackend(this._adapters);

  final List<NetworkAdapter> _adapters;
  int adapterCallCount = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<List<NetworkAdapter>> adapters() async {
    adapterCallCount++;
    return _adapters;
  }

  @override
  void dispose() {}
}

/// Stands in for an FFI call that fails — a stripped system library, a
/// sandbox denial, a platform that answers with nonsense.
final class ThrowingNetworkAdapterBackend implements NetworkAdapterBackend {
  @override
  bool get isAvailable => true;

  @override
  Future<List<NetworkAdapter>> adapters() async =>
      throw StateError('enumeration failed');

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Builds a service with every native backend stubbed out.
  ///
  /// Note this never calls `start()`. Starting binds a TCP listener, a UDP
  /// multicast beacon on a fixed port, and a Bonjour advertiser — which
  /// collide as soon as two test runs overlap, and which have nothing to do
  /// with the property under test.
  Future<(DesktopService, SpySystemInfoBackend)> buildService({
    NetworkAdapterBackend? networkAdapters,
  }) async {
    final spy = SpySystemInfoBackend();
    final service = DesktopService(
      identity: await DeviceIdentity.generate(),
      trustStore: InMemoryTrustStore(),
      deviceName: 'Test Computer',
      appVersion: '0.1.0',
      clock: SystemClock(),
      input: const UnsupportedInputBackend('test'),
      clipboardBackend: const UnsupportedClipboardBackend(),
      media: const UnsupportedMediaBackend(),
      brightness: const UnsupportedBrightnessBackend('test'),
      systemInfo: spy,
      networkAdapters:
          networkAdapters ?? const UnsupportedNetworkAdapterBackend('test'),
    );
    return (service, spy);
  }

  test('the telemetry watcher does no work when no device is connected',
      () async {
    final (service, spy) = await buildService();

    expect(service.devices, isEmpty);

    // Drive the watcher's own tick directly, several times over. The timer
    // calls exactly this method, so the guarantee is being asserted against the
    // real code path rather than a reimplementation of it.
    for (var i = 0; i < 5; i++) {
      await service.telemetryTick();
    }

    expect(
      spy.metricsCallCount,
      0,
      reason: 'the host must not be polled while nobody is watching — that is '
          'battery cost for nobody\'s benefit',
    );
  });

  group('the hardware address advertised for wake-on-lan', () {
    /// A machine with more MACs than a test author would guess: a virtual
    /// bridge that sorts first, a switched-off Wi-Fi adapter, the Ethernet the
    /// phone is actually on, and an interface with no hardware address at all.
    List<NetworkAdapter> mixedAdapters() => <NetworkAdapter>[
          NetworkAdapter(
            name: 'bridge100',
            ipv4Addresses: const <String>['172.17.0.1'],
            macAddress: MacAddress.tryParse('02:42:AC:11:00:01'),
          ),
          NetworkAdapter(
            name: 'en1',
            ipv4Addresses: const <String>[],
            macAddress: MacAddress.tryParse('AA:BB:CC:DD:EE:01'),
          ),
          NetworkAdapter(
            name: 'en0',
            ipv4Addresses: const <String>['192.168.1.42'],
            macAddress: MacAddress.tryParse('AA:BB:CC:DD:EE:02'),
          ),
          const NetworkAdapter(
            name: 'utun3',
            ipv4Addresses: <String>['10.8.0.6'],
          ),
        ];

    test('is the one on the address the phone can actually reach', () async {
      final adapters = FakeNetworkAdapterBackend(mixedAdapters());
      final (service, _) = await buildService(networkAdapters: adapters);

      // The address list arrives sorted with the reachable LAN address first,
      // exactly as `_refreshLocalAddresses` produces it.
      await service.selectLocalMacAddress(
        const <String>['192.168.1.42', '172.17.0.1', '10.8.0.6'],
      );

      expect(
        service.localMacAddress,
        MacAddress.tryParse('AA:BB:CC:DD:EE:02'),
        reason: 'the Docker bridge sorts first in the adapter list and would '
            'be picked by any rule that does not match on address',
      );
      expect(service.describeSelf().macAddress?.canonical, 'AA:BB:CC:DD:EE:02');
    });

    test('is absent when no adapter carries a reachable address', () async {
      final adapters = FakeNetworkAdapterBackend(mixedAdapters());
      final (service, _) = await buildService(networkAdapters: adapters);

      await service.selectLocalMacAddress(const <String>['10.8.0.6']);

      // The VPN tunnel has an address and no hardware behind it. Advertising
      // anything here would put a Wake button on the phone that cannot work.
      expect(service.localMacAddress, isNull);
      expect(service.describeSelf().macAddress, isNull);
    });

    test('is never an address that identifies no machine', () async {
      final adapters = FakeNetworkAdapterBackend(<NetworkAdapter>[
        NetworkAdapter(
          name: 'en0',
          ipv4Addresses: const <String>['192.168.1.42'],
          macAddress: MacAddress.tryParse('00:00:00:00:00:00'),
        ),
      ]);
      final (service, _) = await buildService(networkAdapters: adapters);

      await service.selectLocalMacAddress(const <String>['192.168.1.42']);

      expect(service.localMacAddress, isNull);
    });

    test('is not asked for on a platform that cannot report it', () async {
      final (service, _) = await buildService();

      await service.selectLocalMacAddress(const <String>['192.168.1.42']);

      expect(service.describeSelf().macAddress, isNull);
    });

    test('survives a backend that throws', () async {
      final (service, _) = await buildService(
        networkAdapters: ThrowingNetworkAdapterBackend(),
      );

      // Enumeration goes through FFI. A failure there must not propagate into
      // service startup, whose real job does not depend on it.
      await service.selectLocalMacAddress(const <String>['192.168.1.42']);

      expect(service.localMacAddress, isNull);
    });
  });

  group('buildCapabilities gesture advertising', () {
    test('advertises Capabilities.gestures only when gesturesAvailable is true',
        () {
      final capsWithoutGestures = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        gesturesAvailable: false,
      );
      expect(capsWithoutGestures.has(Capabilities.gestures), isFalse);

      final capsWithGestures = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        gesturesAvailable: true,
      );
      expect(capsWithGestures.has(Capabilities.gestures), isTrue);
    });

    test(
        'currentCapabilities does not advertise gestures for unsupported backend',
        () async {
      final (service, _) = await buildService();
      expect(service.currentCapabilities.has(Capabilities.gestures), isFalse);
    });
  });

  group('buildCapabilities brightness advertising', () {
    test(
        'advertises Capabilities.brightness only when brightnessAvailable is true',
        () {
      final capsWithoutBrightness = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        brightnessAvailable: false,
      );
      expect(capsWithoutBrightness.has(Capabilities.brightness), isFalse);

      final capsWithBrightness = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        brightnessAvailable: true,
      );
      expect(capsWithBrightness.has(Capabilities.brightness), isTrue);
    });

    test(
        'currentCapabilities does not advertise brightness for unsupported backend',
        () async {
      final (service, _) = await buildService();
      expect(service.currentCapabilities.has(Capabilities.brightness), isFalse);
    });
  });
}
