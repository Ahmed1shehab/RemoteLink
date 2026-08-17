import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

/// Controllable screen capture backend for testing pacing and backpressure.
final class ControllableScreenCaptureBackend implements ScreenCaptureBackend {
  ControllableScreenCaptureBackend({
    this.isAvailable = true,
    this.unavailableReason,
  });

  @override
  bool isAvailable;

  @override
  String? unavailableReason;

  Completer<CapturedFrame?>? pendingFrame;
  int captureCallCount = 0;

  @override
  bool checkPermission() => isAvailable;

  @override
  bool requestPermission() => isAvailable;

  @override
  Future<CapturedFrame?> captureFrame({
    int monitorId = kWholeVirtualDesktopMonitorId,
    int maxWidth = 0,
    int maxHeight = 0,
  }) async {
    captureCallCount++;
    if (pendingFrame != null) {
      return pendingFrame!.future;
    }
    return CapturedFrame(
      width: 1920,
      height: 1080,
      data: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
    );
  }

  @override
  void dispose() {}
}

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
    ScreenCaptureBackend? screenCapture,
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
      screenCapture:
          screenCapture ?? const UnsupportedScreenCaptureBackend('test'),
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

  group('buildCapabilities screen capture advertising', () {
    test(
        'advertises Capabilities.screenCapture only when screenCaptureAvailable is true',
        () {
      final capsWithoutCapture = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        screenCaptureAvailable: false,
      );
      expect(capsWithoutCapture.has(Capabilities.screenCapture), isFalse);

      final capsWithCapture = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        screenCaptureAvailable: true,
      );
      expect(capsWithCapture.has(Capabilities.screenCapture), isTrue);
    });

    test(
        'currentCapabilities does not advertise screenCapture for unsupported backend',
        () async {
      final (service, _) = await buildService();
      expect(
          service.currentCapabilities.has(Capabilities.screenCapture), isFalse);
    });

    test(
        'currentCapabilities advertises screenCapture when backend is available',
        () async {
      final capture = ControllableScreenCaptureBackend(isAvailable: true);
      final (service, _) = await buildService(screenCapture: capture);
      expect(
          service.currentCapabilities.has(Capabilities.screenCapture), isTrue);
    });
  });

  group('screen capture loop, pacing, and backpressure', () {
    test('backpressure skips ticks when frame capture or send is in-flight',
        () async {
      final captureBackend =
          ControllableScreenCaptureBackend(isAvailable: true);
      final pair = await _createTestServerClientPair();
      final phoneIdentity = pair.clientIdentity;

      final trustStore = InMemoryTrustStore();
      await trustStore.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Pixel 8 Pro',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.standard.wireValue,
        ),
      );

      final clock = SystemClock();
      final service = DesktopService(
        identity: await DeviceIdentity.generate(),
        trustStore: trustStore,
        deviceName: 'Test Computer',
        appVersion: '0.1.0',
        clock: clock,
        input: const UnsupportedInputBackend('test'),
        clipboardBackend: const UnsupportedClipboardBackend(),
        media: const UnsupportedMediaBackend(),
        brightness: const UnsupportedBrightnessBackend('test'),
        systemInfo: const UnsupportedSystemInfoBackend('test'),
        networkAdapters: const UnsupportedNetworkAdapterBackend('test'),
        screenCapture: captureBackend,
      );

      await service.registerSessionForTesting(pair.session);

      // Inbound ScreenStreamStart message from phone
      await service.handleMessageForTesting(
        pair.session,
        const ScreenStreamStart(
          targetFps: 30,
          codec: ScreenCodec.jpeg,
          maxWidth: 1280,
          maxHeight: 720,
        ),
      );

      expect(service.isStreamingScreen(pair.session.peerId), isTrue);

      // Frame 1: simulate in-flight capture using pending completer
      final completer1 = Completer<CapturedFrame?>();
      captureBackend.pendingFrame = completer1;

      final tick1 = service.screenCaptureTick(pair.session.peerId);
      expect(captureBackend.captureCallCount, 1);

      // While tick 1 is in flight, tick 2 fires
      await service.screenCaptureTick(pair.session.peerId);

      // Assert tick 2 was SKIPPED due to backpressure: capture was not called again
      expect(captureBackend.captureCallCount, 1);
      expect(service.screenStreamSkippedCount(pair.session.peerId), 1);

      // Now complete tick 1
      completer1.complete(
        CapturedFrame(
          width: 1280,
          height: 720,
          data: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
        ),
      );
      await tick1;

      expect(service.screenStreamCapturedCount(pair.session.peerId), 1);

      // Tick 3: system is idle, frame is captured normally
      captureBackend.pendingFrame = null;
      await service.screenCaptureTick(pair.session.peerId);

      expect(captureBackend.captureCallCount, 2);
      expect(service.screenStreamCapturedCount(pair.session.peerId), 2);
      expect(service.screenStreamSkippedCount(pair.session.peerId), 1);

      // Phone stops streaming
      await service.handleMessageForTesting(
        pair.session,
        const ScreenStreamStop(reason: ScreenStopReason.userClosed),
      );

      expect(service.isStreamingScreen(pair.session.peerId), isFalse);

      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });
  });

  group('the desktop knows, and can say, that it is being watched', () {
    test('a stream names its viewer, and stopping it clears the name',
        () async {
      final captureBackend =
          ControllableScreenCaptureBackend(isAvailable: true);
      final pair = await _createTestServerClientPair();
      final phoneIdentity = pair.clientIdentity;

      final trustStore = InMemoryTrustStore();
      await trustStore.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Pixel 8 Pro',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.standard.wireValue,
        ),
      );

      final service = DesktopService(
        identity: await DeviceIdentity.generate(),
        trustStore: trustStore,
        deviceName: 'Test Computer',
        appVersion: '0.1.0',
        clock: SystemClock(),
        input: const UnsupportedInputBackend('test'),
        clipboardBackend: const UnsupportedClipboardBackend(),
        media: const UnsupportedMediaBackend(),
        brightness: const UnsupportedBrightnessBackend('test'),
        systemInfo: const UnsupportedSystemInfoBackend('test'),
        networkAdapters: const UnsupportedNetworkAdapterBackend('test'),
        screenCapture: captureBackend,
      );

      await service.registerSessionForTesting(pair.session);

      // Collected from the change stream rather than only read back from the
      // getter: the banner is driven by the stream, so a getter that updates
      // while the stream stays silent would leave the window showing nothing.
      final published = <List<String>>[];
      final subscription = service.screenViewerChanges.listen(published.add);

      expect(service.screenViewers, isEmpty);

      await service.handleMessageForTesting(
        pair.session,
        const ScreenStreamStart(targetFps: 30, codec: ScreenCodec.jpeg),
      );

      expect(service.screenViewers, <String>['Pixel 8 Pro']);
      await pumpEventQueue();
      expect(published.last, <String>['Pixel 8 Pro']);

      await service.stopScreenStreamFor(pair.session.peerId);

      expect(service.isStreamingScreen(pair.session.peerId), isFalse);
      expect(service.screenViewers, isEmpty);
      await pumpEventQueue();
      expect(published.last, isEmpty);

      await subscription.cancel();
      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });

    test('stopping a stream that is not running is not an error', () async {
      // The banner's button acts on every connected device, so most of the
      // calls it makes are for peers that were never streaming.
      final pair = await _createTestServerClientPair();
      final trustStore = InMemoryTrustStore();
      await trustStore.upsert(
        TrustedPeer(
          id: pair.clientIdentity.id,
          publicKey: pair.clientIdentity.publicKey,
          name: 'Pixel 8 Pro',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.standard.wireValue,
        ),
      );

      final service = DesktopService(
        identity: await DeviceIdentity.generate(),
        trustStore: trustStore,
        deviceName: 'Test Computer',
        appVersion: '0.1.0',
        clock: SystemClock(),
        input: const UnsupportedInputBackend('test'),
        clipboardBackend: const UnsupportedClipboardBackend(),
        media: const UnsupportedMediaBackend(),
        brightness: const UnsupportedBrightnessBackend('test'),
        systemInfo: const UnsupportedSystemInfoBackend('test'),
        networkAdapters: const UnsupportedNetworkAdapterBackend('test'),
        screenCapture: ControllableScreenCaptureBackend(isAvailable: true),
      );

      await service.registerSessionForTesting(pair.session);

      await expectLater(
        service.stopScreenStreamFor(pair.session.peerId),
        completes,
      );
      expect(service.screenViewers, isEmpty);

      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });
  });
}

Future<
    ({
      RemoteLinkServer server,
      RemoteLinkClient client,
      ServerSession session,
      DeviceIdentity clientIdentity,
    })> _createTestServerClientPair() async {
  final phoneIdentity = await DeviceIdentity.generate();
  final desktopIdentity = await DeviceIdentity.generate();
  final desktopTrust = InMemoryTrustStore();
  await desktopTrust.upsert(
    TrustedPeer(
      id: phoneIdentity.id,
      publicKey: phoneIdentity.publicKey,
      name: 'Pixel 8 Pro',
      platform: PlatformKind.android,
      pairedAt: DateTime.now(),
      permissionTier: PermissionTier.extended.wireValue,
    ),
  );

  final server = RemoteLinkServer(
    identity: desktopIdentity,
    capabilities: const Capabilities(Capabilities.sessionResumption),
    trustStore: desktopTrust,
    clock: SystemClock(),
    port: 0,
  );
  await server.start();

  final client = RemoteLinkClient(
    identity: phoneIdentity,
    capabilities: const Capabilities(Capabilities.sessionResumption),
    clock: SystemClock(),
  );

  unawaited(
    client.connect(
      ConnectionTarget(
        host: '127.0.0.1',
        port: server.boundPort,
        serverPublicKey: desktopIdentity.publicKey,
      ),
    ),
  );

  final session = await server.accepted.first;
  return (
    server: server,
    client: client,
    session: session,
    clientIdentity: phoneIdentity,
  );
}
