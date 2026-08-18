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

  /// Frames to hand out in order, for tests that care what changes between
  /// one capture and the next. The last entry repeats once exhausted.
  List<CapturedFrame>? script;

  /// What the service actually asked for on the most recent capture.
  ///
  /// Recorded rather than ignored because the stream's parameters reaching the
  /// backend is the only thing that makes them mean anything: a request for a
  /// 1280-wide frame that the service quietly captures at native resolution
  /// looks identical from every other angle.
  int? lastMaxWidth;
  int? lastMaxHeight;
  int? lastMonitorId;
  double? lastQuality;

  /// Where the fake pointer is. Moved by tests to drive the cursor poll.
  ({double x, double y})? cursor;
  int cursorReadCount = 0;
  int? lastCursorMonitorId;

  @override
  ({double x, double y})? cursorPosition({
    int monitorId = kWholeVirtualDesktopMonitorId,
  }) {
    cursorReadCount++;
    lastCursorMonitorId = monitorId;
    return cursor;
  }

  @override
  bool checkPermission() => isAvailable;

  @override
  bool requestPermission() => isAvailable;

  @override
  Future<CapturedFrame?> captureFrame({
    int monitorId = kWholeVirtualDesktopMonitorId,
    int maxWidth = 0,
    int maxHeight = 0,
    double quality = kDefaultScreenJpegQuality,
  }) async {
    captureCallCount++;
    lastMaxWidth = maxWidth;
    lastMaxHeight = maxHeight;
    lastMonitorId = monitorId;
    lastQuality = quality;
    if (pendingFrame != null) {
      return pendingFrame!.future;
    }
    final scripted = script;
    if (scripted != null && scripted.isNotEmpty) {
      final index = captureCallCount - 1;
      return scripted[index < scripted.length ? index : scripted.length - 1];
    }
    // Distinct bytes per capture by default, standing in for a desk where
    // something is happening. Identical frames are now withheld, so a fake
    // that returned a constant would silently turn every test that counts
    // sent frames into a test of the deduplicator.
    return CapturedFrame(
      width: 1920,
      height: 1080,
      data: Uint8List.fromList(
        <int>[0xFF, 0xD8, captureCallCount & 0xFF, 0xFF, 0xD9],
      ),
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

/// Lets an unawaited send cross a real loopback socket and come back.
///
/// The cursor path deliberately does not await its send — the whole point is
/// that a pointer update never queues behind anything — so a test has to give
/// the round trip somewhere to happen.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
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
          // Deliberately below the protocol default, so the quality the
          // backend receives cannot be the default arriving by coincidence.
          targetBitrateKbps: 1250,
        ),
      );

      expect(service.isStreamingScreen(pair.session.peerId), isTrue);
      service.pauseScreenCaptureLoop(pair.session.peerId);

      // Frame 1: simulate in-flight capture using pending completer
      final completer1 = Completer<CapturedFrame?>();
      captureBackend.pendingFrame = completer1;

      final tick1 = service.screenCaptureTick(pair.session.peerId);
      expect(captureBackend.captureCallCount, 1);

      // The phone asked for 1280x720. A service that captures at native
      // resolution regardless sends frames several times the size the phone
      // requested, which is invisible from the phone — the picture looks
      // correct, it just arrives late and keeps falling further behind.
      expect(captureBackend.lastMaxWidth, 1280);
      expect(captureBackend.lastMaxHeight, 720);
      expect(captureBackend.lastMonitorId, kWholeVirtualDesktopMonitorId);
      // Encoding at ImageIO's near-lossless default is what made a frame
      // 400 KB. Nothing else in the pipeline notices the difference, so the
      // only place it can be caught is here, at the call.
      //
      // 1250 kbps is two halvings below the 5000 kbps anchor, so the quality
      // must come out *below* the default. Asserting the exact value would
      // pass just as well against a service that ignored the bitrate and
      // handed over a constant.
      expect(captureBackend.lastQuality, lessThan(kDefaultScreenJpegQuality));
      expect(
        captureBackend.lastQuality,
        screenJpegQualityForBitrate(1250),
      );

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
  group('a desk that is not moving', () {
    /// Builds a service already streaming to a connected peer.
    Future<
        (
          DesktopService,
          ({
            RemoteLinkServer server,
            RemoteLinkClient client,
            ServerSession session,
            DeviceIdentity clientIdentity,
          }),
          ControllableScreenCaptureBackend,
        )> streamingService({required List<CapturedFrame> frames}) async {
      final captureBackend = ControllableScreenCaptureBackend(isAvailable: true)
        ..script = frames;
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
        screenCapture: captureBackend,
      );

      await service.registerSessionForTesting(pair.session);
      await service.handleMessageForTesting(
        pair.session,
        const ScreenStreamStart(
          targetFps: 30,
          codec: ScreenCodec.jpeg,
          maxWidth: 1280,
          maxHeight: 720,
        ),
      );
      // Silence the automatic loop: these tests count frames, and a loop
      // rescheduling itself in real time would contribute ticks of its own to
      // every count below.
      service.pauseScreenCaptureLoop(pair.session.peerId);

      return (service, pair, captureBackend);
    }

    CapturedFrame frame(List<int> bytes, {double? cursorX, double? cursorY}) =>
        CapturedFrame(
          width: 1280,
          height: 720,
          data: Uint8List.fromList(bytes),
          cursorX: cursorX,
          cursorY: cursorY,
        );

    test('is not sent over and over', () async {
      // A still desk used to cost exactly as much bandwidth as a moving one:
      // a fresh full JPEG, thirty times a second, saying nothing.
      final still = <int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9];
      final (service, pair, _) = await streamingService(
        frames: <CapturedFrame>[frame(still), frame(still), frame(still)],
      );
      final peerId = pair.session.peerId;

      for (var i = 0; i < 3; i++) {
        await service.screenCaptureTick(peerId);
      }

      expect(
        service.screenStreamCapturedCount(peerId),
        1,
        reason: 'the same picture was sent more than once',
      );
      expect(service.screenStreamUnchangedCount(peerId), 2);

      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });

    test('sends again the moment anything changes', () async {
      final (service, pair, _) = await streamingService(
        frames: <CapturedFrame>[
          frame(<int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9]),
          frame(<int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9]),
          frame(<int>[0xFF, 0xD8, 0x02, 0xFF, 0xD9]),
        ],
      );
      final peerId = pair.session.peerId;

      for (var i = 0; i < 3; i++) {
        await service.screenCaptureTick(peerId);
      }

      expect(service.screenStreamCapturedCount(peerId), 2);
      expect(service.screenStreamUnchangedCount(peerId), 1);

      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });

    test('sends nothing when only the cursor moved', () async {
      // This used to be the opposite assertion, and the reversal is the whole
      // fix. The cursor is not in the picture, so a pointer crossing a still
      // desktop produces byte-identical image data — and while the cursor rode
      // on the frame, keeping the drawn pointer alive meant re-sending 213,622
      // bytes to report that an arrow had moved a few pixels. No home network
      // carries that, so the pointer updated five to ten times a second.
      //
      // It has `ScreenCursor` to itself now, at 34 bytes, so these captures
      // are correctly recognised as showing nothing new.
      const identicalPixels = <int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9];
      final (service, pair, _) = await streamingService(
        frames: <CapturedFrame>[
          frame(identicalPixels, cursorX: 0.10, cursorY: 0.10),
          frame(identicalPixels, cursorX: 0.50, cursorY: 0.40),
          frame(identicalPixels, cursorX: 0.90, cursorY: 0.70),
        ],
      );
      final peerId = pair.session.peerId;

      for (var i = 0; i < 3; i++) {
        await service.screenCaptureTick(peerId);
      }

      expect(
        service.screenStreamCapturedCount(peerId),
        1,
        reason: 'a moving pointer must not drag whole frames along with it',
      );
      expect(service.screenStreamUnchangedCount(peerId), 2);

      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });

    test('reports the pointer without capturing anything', () async {
      // The other half. The frame loop is paused for the whole test, so every
      // cursor update below happens with no capture running at all — which is
      // the decoupling stated as an assertion.
      final (service, pair, backend) = await streamingService(
        frames: <CapturedFrame>[
          frame(<int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9])
        ],
      );
      final peerId = pair.session.peerId;
      final seen = <ScreenCursor>[];
      final subscription = pair.client.messages
          .where((m) => m is ScreenCursor)
          .cast<ScreenCursor>()
          .listen(seen.add);

      backend.cursor = (x: 0.25, y: 0.5);
      service.screenCursorTick(peerId);
      await _settle();
      backend.cursor = (x: 0.75, y: 0.5);
      service.screenCursorTick(peerId);
      await _settle();

      expect(seen, hasLength(2));
      expect(seen.first.x, closeTo(0.25, 1e-6));
      expect(seen.last.x, closeTo(0.75, 1e-6));
      expect(
        backend.captureCallCount,
        0,
        reason: 'moving the pointer must not cost a capture',
      );

      await subscription.cancel();
      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });

    test('a burst of movement arrives as the position it ended at', () async {
      // `screenCursor` is lossy, so several positions queued in one turn
      // collapse to the newest. Right for a pointer: replaying the path late
      // would drag the drawn arrow along a trail the real one has left, which
      // is worse than simply arriving where it is.
      final (service, pair, backend) = await streamingService(
        frames: <CapturedFrame>[
          frame(<int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9])
        ],
      );
      final peerId = pair.session.peerId;
      final seen = <ScreenCursor>[];
      final subscription = pair.client.messages
          .where((m) => m is ScreenCursor)
          .cast<ScreenCursor>()
          .listen(seen.add);

      for (var i = 1; i <= 5; i++) {
        backend.cursor = (x: i / 10, y: 0.5);
        service.screenCursorTick(peerId);
      }
      await _settle();

      expect(seen, hasLength(1));
      expect(seen.single.x, closeTo(0.5, 1e-6));

      await subscription.cancel();
      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });

    test('says nothing while the pointer is still', () async {
      // Polled at 60 Hz, and a hand rests far more than it moves. Sending an
      // unchanged position every tick would put the cursor straight back on the
      // same footing as the frames it was rescued from.
      final (service, pair, backend) = await streamingService(
        frames: <CapturedFrame>[
          frame(<int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9])
        ],
      );
      final peerId = pair.session.peerId;
      final seen = <ScreenCursor>[];
      final subscription = pair.client.messages
          .where((m) => m is ScreenCursor)
          .cast<ScreenCursor>()
          .listen(seen.add);

      backend.cursor = (x: 0.25, y: 0.5);
      for (var i = 0; i < 10; i++) {
        service.screenCursorTick(peerId);
      }

      await _settle();

      expect(seen, hasLength(1));
      expect(
        backend.cursorReadCount,
        10,
        reason: 'the read is cheap; it is the send that must be conditional',
      );
      // Counted at the source. The lossy queue collapses same-turn messages
      // into the newest, so from the receiving end a poll that sends every
      // tick looks exactly like one that sends only on movement — which is how
      // a missing guard would sail through the assertion above.
      expect(
        service.screenCursorUpdateCount(peerId),
        1,
        reason: 'the pointer had not moved; nine of those were noise',
      );

      await subscription.cancel();
      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });

    test('reports the pointer leaving the display, exactly once', () async {
      // A real state that has to be sent. Left at its last position the arrow
      // sits frozen against an edge, which reads as the stream having hung
      // rather than as the pointer being on another monitor.
      final (service, pair, backend) = await streamingService(
        frames: <CapturedFrame>[
          frame(<int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9])
        ],
      );
      final peerId = pair.session.peerId;
      final seen = <ScreenCursor>[];
      final subscription = pair.client.messages
          .where((m) => m is ScreenCursor)
          .cast<ScreenCursor>()
          .listen(seen.add);

      backend.cursor = (x: 0.25, y: 0.5);
      service.screenCursorTick(peerId);
      await _settle();
      backend.cursor = null;
      service.screenCursorTick(peerId);
      service.screenCursorTick(peerId);
      await _settle();

      expect(seen, hasLength(2));
      expect(seen.first.isOnScreen, isTrue);
      expect(seen.last.isOnScreen, isFalse);

      await subscription.cancel();
      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });

    test('asks about the display being watched', () async {
      // On a two-monitor desk a pointer normalised against the wrong screen
      // lands nowhere near where it is, and nothing else in the picture would
      // look wrong.
      final (service, pair, backend) = await streamingService(
        frames: <CapturedFrame>[
          frame(<int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9])
        ],
      );
      final peerId = pair.session.peerId;

      await service.handleMessageForTesting(
        pair.session,
        const ScreenConfigure(monitorId: 69733248),
      );
      service.pauseScreenCaptureLoop(peerId);
      service.screenCursorTick(peerId);

      expect(backend.lastCursorMonitorId, 69733248);

      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    });

    test('sends the first frame after the stream is reconfigured', () async {
      // After a reconfigure the phone expects a different size or a different
      // display. A frame withheld for matching the *old* one would leave it on
      // the previous monitor until something there happened to move.
      const same = <int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9];
      final (service, pair, _) = await streamingService(
        frames: <CapturedFrame>[frame(same), frame(same), frame(same)],
      );
      final peerId = pair.session.peerId;

      await service.screenCaptureTick(peerId);
      await service.screenCaptureTick(peerId);
      expect(service.screenStreamCapturedCount(peerId), 1);

      await service.handleMessageForTesting(
        pair.session,
        const ScreenConfigure(monitorId: 3),
      );
      await service.screenCaptureTick(peerId);

      expect(
        service.screenStreamCapturedCount(peerId),
        2,
        reason: 'the phone switched displays and was sent nothing',
      );

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
