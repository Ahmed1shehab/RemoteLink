import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/control/control_screen.dart';
import 'package:remotelink_mobile/src/features/screen/screen_viewer_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

void main() {
  // `flutter_test` defaults to an 800x600 surface, which is landscape — and
  // this screen deliberately behaves differently there, dropping the app bar
  // and the floating button to give the frame the whole display. Every test
  // below asserts the portrait chrome, so every test below needs a portrait
  // phone under it. The landscape behaviour has its own tests that set their
  // own size.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1170, 2532);
    view.devicePixelRatio = 3;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets(
      'renders unsupported state when Capabilities.screenCapture is absent',
      (tester) async {
    late DeviceIdentity desktopIdentity;
    late DeviceIdentity phoneIdentity;
    late InMemoryTrustStore desktopTrust;
    late RemoteLinkServer server;
    late RemoteLinkClient client;

    await tester.runAsync(() async {
      phoneIdentity = await DeviceIdentity.generate();
      desktopIdentity = await DeviceIdentity.generate();
      desktopTrust = InMemoryTrustStore();

      await desktopTrust.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: 2,
        ),
      );

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities:
            const Capabilities(Capabilities.mouse | Capabilities.keyboard),
        trustStore: desktopTrust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities:
            const Capabilities(Capabilities.mouse | Capabilities.keyboard),
        clock: SystemClock(),
      );

      final connectedFuture = client.states.firstWhere(
        (s) => s == ClientState.connected,
      );

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      await connectedFuture.timeout(const Duration(seconds: 10));
    });

    addTearDown(() => tester.runAsync(() async {
          await client.dispose();
          await server.stop();
          await desktopTrust.dispose();
        }));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          clientProvider.overrideWith((ref) async => client),
        ],
        child: const MaterialApp(home: ScreenViewerScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Screen sharing isn’t available'), findsOneWidget);
    expect(
      find.textContaining('This computer cannot share its screen'),
      findsOneWidget,
    );
  });

  testWidgets(
      'ControlScreen does not show screen stream button when capability is absent',
      (tester) async {
    late DeviceIdentity desktopIdentity;
    late DeviceIdentity phoneIdentity;
    late InMemoryTrustStore desktopTrust;
    late RemoteLinkServer server;
    late RemoteLinkClient client;

    await tester.runAsync(() async {
      phoneIdentity = await DeviceIdentity.generate();
      desktopIdentity = await DeviceIdentity.generate();
      desktopTrust = InMemoryTrustStore();

      await desktopTrust.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: 2,
        ),
      );

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: const Capabilities(Capabilities.mouse),
        trustStore: desktopTrust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(Capabilities.mouse),
        clock: SystemClock(),
      );

      final connectedFuture = client.states.firstWhere(
        (s) => s == ClientState.connected,
      );

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      await connectedFuture.timeout(const Duration(seconds: 10));
    });

    addTearDown(() => tester.runAsync(() async {
          await client.dispose();
          await server.stop();
          await desktopTrust.dispose();
        }));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          clientProvider.overrideWith((ref) async => client),
        ],
        child: const MaterialApp(home: ControlScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.screenshot_monitor_outlined), findsNothing);
  });

  testWidgets(
      'ControlScreen shows screen stream button when capability is present',
      (tester) async {
    late DeviceIdentity desktopIdentity;
    late DeviceIdentity phoneIdentity;
    late InMemoryTrustStore desktopTrust;
    late RemoteLinkServer server;
    late RemoteLinkClient client;

    await tester.runAsync(() async {
      phoneIdentity = await DeviceIdentity.generate();
      desktopIdentity = await DeviceIdentity.generate();
      desktopTrust = InMemoryTrustStore();

      await desktopTrust.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: 2,
        ),
      );

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: const Capabilities(
          Capabilities.mouse | Capabilities.screenCapture,
        ),
        trustStore: desktopTrust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(
          Capabilities.mouse | Capabilities.screenCapture,
        ),
        clock: SystemClock(),
      );

      final connectedFuture = client.states.firstWhere(
        (s) => s == ClientState.connected,
      );

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      await connectedFuture.timeout(const Duration(seconds: 10));
    });

    addTearDown(() => tester.runAsync(() async {
          await client.dispose();
          await server.stop();
          await desktopTrust.dispose();
        }));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          clientProvider.overrideWith((ref) async => client),
          // The button needs both the desk's capability bit and a tier that
          // may use it. The bit alone is not enough — see the readOnly test
          // immediately below.
          currentPermissionTierProvider.overrideWith(
            (ref) => Stream<PermissionTier?>.value(PermissionTier.standard),
          ),
        ],
        child: const MaterialApp(home: ControlScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.screenshot_monitor_outlined), findsOneWidget);
  });

  testWidgets(
      'ControlScreen hides the screen stream button at readOnly even when the '
      'desktop advertises the capability', (tester) async {
    // The capability bit is advertised per server, not per device, so a
    // readOnly phone sees it set on a desk that can capture. The desktop then
    // refuses the request in silence — deliberately, so a peer cannot
    // enumerate the tier system by probing. Which means the phone must decide
    // for itself, from the tier it was granted, or the button is one that
    // sends a message and never hears anything back.
    late DeviceIdentity desktopIdentity;
    late DeviceIdentity phoneIdentity;
    late InMemoryTrustStore desktopTrust;
    late RemoteLinkServer server;
    late RemoteLinkClient client;

    await tester.runAsync(() async {
      phoneIdentity = await DeviceIdentity.generate();
      desktopIdentity = await DeviceIdentity.generate();
      desktopTrust = InMemoryTrustStore();

      await desktopTrust.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.readOnly.wireValue,
        ),
      );

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: const Capabilities(
          Capabilities.mouse | Capabilities.screenCapture,
        ),
        trustStore: desktopTrust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(
          Capabilities.mouse | Capabilities.screenCapture,
        ),
        clock: SystemClock(),
      );

      final connectedFuture = client.states.firstWhere(
        (s) => s == ClientState.connected,
      );

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      await connectedFuture.timeout(const Duration(seconds: 10));
    });

    addTearDown(() => tester.runAsync(() async {
          await client.dispose();
          await server.stop();
          await desktopTrust.dispose();
        }));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          clientProvider.overrideWith((ref) async => client),
          currentPermissionTierProvider.overrideWith(
            (ref) => Stream<PermissionTier?>.value(PermissionTier.readOnly),
          ),
        ],
        child: const MaterialApp(home: ControlScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.screenshot_monitor_outlined), findsNothing);
  });

  testWidgets(
      'ScreenViewerScreen renders stream view and controls when capability is present',
      (tester) async {
    late DeviceIdentity desktopIdentity;
    late DeviceIdentity phoneIdentity;
    late InMemoryTrustStore desktopTrust;
    late RemoteLinkServer server;
    late RemoteLinkClient client;

    await tester.runAsync(() async {
      phoneIdentity = await DeviceIdentity.generate();
      desktopIdentity = await DeviceIdentity.generate();
      desktopTrust = InMemoryTrustStore();

      await desktopTrust.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: 2,
        ),
      );

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: const Capabilities(
          Capabilities.mouse | Capabilities.screenCapture,
        ),
        trustStore: desktopTrust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(
          Capabilities.mouse | Capabilities.screenCapture,
        ),
        clock: SystemClock(),
      );

      final connectedFuture = client.states.firstWhere(
        (s) => s == ClientState.connected,
      );

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      await connectedFuture.timeout(const Duration(seconds: 10));
    });

    addTearDown(() => tester.runAsync(() async {
          await client.dispose();
          await server.stop();
          await desktopTrust.dispose();
        }));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          clientProvider.overrideWith((ref) async => client),
        ],
        child: const MaterialApp(home: ScreenViewerScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Screen Stream'), findsOneWidget);
    expect(find.text('Waiting for screen frames...'), findsOneWidget);
    expect(find.text('Stop Sharing'), findsOneWidget);
  });

  testWidgets('ScreenViewerScreen renders incoming ScreenFrame image',
      (tester) async {
    late DeviceIdentity desktopIdentity;
    late DeviceIdentity phoneIdentity;
    late InMemoryTrustStore desktopTrust;
    late RemoteLinkServer server;
    late RemoteLinkClient client;

    await tester.runAsync(() async {
      phoneIdentity = await DeviceIdentity.generate();
      desktopIdentity = await DeviceIdentity.generate();
      desktopTrust = InMemoryTrustStore();

      await desktopTrust.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: 2,
        ),
      );

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: const Capabilities(
          Capabilities.mouse | Capabilities.screenCapture,
        ),
        trustStore: desktopTrust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(
          Capabilities.mouse | Capabilities.screenCapture,
        ),
        clock: SystemClock(),
      );

      final connectedFuture = client.states.firstWhere(
        (s) => s == ClientState.connected,
      );

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );

      await connectedFuture.timeout(const Duration(seconds: 10));
    });

    addTearDown(() => tester.runAsync(() async {
          await client.dispose();
          await server.stop();
          await desktopTrust.dispose();
        }));

    final frame = ScreenFrame(
      sequence: 0,
      ptsMicros: 1000000,
      isKeyframe: true,
      width: 1920,
      height: 1080,
      data: Uint8List.fromList(<int>[
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
        0x4A,
        0x46,
        0x49,
        0x46,
        0x00,
        0x01,
        0x01,
        0x00,
        0x00,
        0x01,
        0x00,
        0x01,
        0x00,
        0x00,
        0xFF,
        0xDB,
        0x00,
        0x43,
        0x00,
        0x08,
        0x06,
        0x06,
        0x07,
        0x06,
        0x05,
        0x08,
        0x07,
        0x07,
        0x07,
        0x09,
        0x09,
        0x08,
        0x0A,
        0x0C,
        0x14,
        0x0D,
        0x0C,
        0x0B,
        0x0B,
        0x0C,
        0x19,
        0x12,
        0x13,
        0x0F,
        0x14,
        0x1D,
        0x1A,
        0x1F,
        0x1E,
        0x1D,
        0x1A,
        0x1C,
        0x1C,
        0x20,
        0x24,
        0x2E,
        0x27,
        0x20,
        0x22,
        0x2C,
        0x23,
        0x1C,
        0x1C,
        0x28,
        0x37,
        0x29,
        0x2C,
        0x30,
        0x31,
        0x34,
        0x34,
        0x34,
        0x1F,
        0x27,
        0x39,
        0x3D,
        0x38,
        0x32,
        0x3C,
        0x2E,
        0x33,
        0x34,
        0x32,
        0xFF,
        0xC0,
        0x00,
        0x0B,
        0x08,
        0x00,
        0x01,
        0x00,
        0x01,
        0x01,
        0x01,
        0x11,
        0x00,
        0xFF,
        0xC4,
        0x00,
        0x1F,
        0x00,
        0x00,
        0x01,
        0x05,
        0x01,
        0x01,
        0x01,
        0x01,
        0x01,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x01,
        0x02,
        0x03,
        0x04,
        0x05,
        0x06,
        0x07,
        0x08,
        0x09,
        0x0A,
        0x0B,
        0xFF,
        0xDA,
        0x00,
        0x08,
        0x01,
        0x01,
        0x00,
        0x00,
        0x3F,
        0x00,
        0xBF,
        0x00,
        0xFF,
        0xD9,
      ]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          clientProvider.overrideWith((ref) async => client),
          screenFrameProvider.overrideWith(
            (ref) => Stream<ScreenFrame?>.value(frame),
          ),
        ],
        child: const MaterialApp(home: ScreenViewerScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('1920×1080'), findsOneWidget);
  });

  testWidgets('landscape drops the app bar and keeps the stop control',
      (tester) async {
    // A desk is a landscape rectangle; a portrait phone spends most of its
    // screen on letterbox bars. Turning it sideways has to give the frame the
    // whole display — but the stop control must survive that, because it is
    // the only way to end a stream from this side.
    final view = tester.view;
    view.physicalSize = const Size(2532, 1170);
    view.devicePixelRatio = 3;

    late RemoteLinkClient client;
    await tester.runAsync(() async {
      client = await _connectedClient(tester);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          clientProvider.overrideWith((ref) async => client),
          screenFrameProvider.overrideWith(
            (ref) => Stream<ScreenFrame?>.value(_tinyFrame()),
          ),
        ],
        child: const MaterialApp(home: ScreenViewerScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Stop Streaming'), findsOneWidget);
    expect(find.text('4\u00d72'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait keeps the app bar', (tester) async {
    // The counterpart, so the landscape branch cannot quietly become the only
    // branch. The file-level setUp already installs a portrait surface.
    late RemoteLinkClient client;
    await tester.runAsync(() async {
      client = await _connectedClient(tester);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          clientProvider.overrideWith((ref) async => client),
          screenFrameProvider.overrideWith(
            (ref) => Stream<ScreenFrame?>.value(_tinyFrame()),
          ),
        ],
        child: const MaterialApp(home: ScreenViewerScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picture is inert at a tier that cannot send input',
      (tester) async {
    // read-only may watch and may not touch. The desktop refuses out-of-tier
    // input in silence by design, so a phone that sent it anyway would give
    // the user a picture that swallows every tap without explanation.
    late RemoteLinkClient client;
    await tester.runAsync(() async {
      client = await _connectedClient(tester);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          clientProvider.overrideWith((ref) async => client),
          currentPermissionTierProvider.overrideWith(
            (ref) => Stream<PermissionTier?>.value(PermissionTier.readOnly),
          ),
          screenFrameProvider.overrideWith(
            (ref) => Stream<ScreenFrame?>.value(_tinyFrame()),
          ),
        ],
        child: const MaterialApp(home: ScreenViewerScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('screen-viewer-pointer-surface')),
      findsNothing,
      reason: 'a read-only viewer must not wire up pointer handling at all',
    );
  });
}

/// A valid 4x2 JPEG, small enough to inline and real enough for `Image.memory`.
ScreenFrame _tinyFrame() => ScreenFrame(
      sequence: 1,
      ptsMicros: 0,
      isKeyframe: true,
      width: 4,
      height: 2,
      data: Uint8List.fromList(_jpegBytes),
    );

/// A phone client connected to a throwaway desktop that can share its screen.
///
/// Factored out of the tests that were already doing this inline. The pair is
/// real because `ScreenViewerScreen` reads `client.session?.capabilities` to
/// decide whether the desk can share at all, and a session is the only thing
/// that carries a negotiated capability set.
Future<RemoteLinkClient> _connectedClient(WidgetTester tester) async {
  final phoneIdentity = await DeviceIdentity.generate();
  final desktopIdentity = await DeviceIdentity.generate();
  final desktopTrust = InMemoryTrustStore();

  await desktopTrust.upsert(
    TrustedPeer(
      id: phoneIdentity.id,
      publicKey: phoneIdentity.publicKey,
      name: 'Test Phone',
      platform: PlatformKind.android,
      pairedAt: DateTime.now(),
      permissionTier: PermissionTier.standard.wireValue,
    ),
  );

  const caps = Capabilities(
    Capabilities.mouse | Capabilities.keyboard | Capabilities.screenCapture,
  );

  final server = RemoteLinkServer(
    identity: desktopIdentity,
    capabilities: caps,
    trustStore: desktopTrust,
    clock: SystemClock(),
    port: 0,
  );
  await server.start();

  final client = RemoteLinkClient(
    identity: phoneIdentity,
    capabilities: caps,
    clock: SystemClock(),
  );

  final connected = client.states.firstWhere((s) => s == ClientState.connected);
  await client.connect(
    ConnectionTarget(
      host: '127.0.0.1',
      port: server.boundPort,
      deviceId: desktopIdentity.id,
      serverPublicKey: desktopIdentity.publicKey,
    ),
  );
  await connected.timeout(const Duration(seconds: 10));

  tester.binding.addPostFrameCallback((_) {});
  addTearDown(() => tester.runAsync(() async {
        await client.dispose();
        await server.stop();
        await desktopTrust.dispose();
      }));

  return client;
}

/// A valid 4x2 JPEG: small enough to inline, real enough for `Image.memory`.
const List<int> _jpegBytes = <int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
  0x01,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0xFF,
  0xDB,
  0x00,
  0x43,
  0x00,
  0x08,
  0x06,
  0x06,
  0x07,
  0x06,
  0x05,
  0x08,
  0x07,
  0x07,
  0x07,
  0x09,
  0x09,
  0x08,
  0x0A,
  0x0C,
  0x14,
  0x0D,
  0x0C,
  0x0B,
  0x0B,
  0x0C,
  0x19,
  0x12,
  0x13,
  0x0F,
  0x14,
  0x1D,
  0x1A,
  0x1F,
  0x1E,
  0x1D,
  0x1A,
  0x1C,
  0x1C,
  0x20,
  0x24,
  0x2E,
  0x27,
  0x20,
  0x22,
  0x2C,
  0x23,
  0x1C,
  0x1C,
  0x28,
  0x37,
  0x29,
  0x2C,
  0x30,
  0x31,
  0x34,
  0x34,
  0x34,
  0x1F,
  0x27,
  0x39,
  0x3D,
  0x38,
  0x32,
  0x3C,
  0x2E,
  0x33,
  0x34,
  0x32,
  0xFF,
  0xC0,
  0x00,
  0x0B,
  0x08,
  0x00,
  0x02,
  0x00,
  0x04,
  0x01,
  0x01,
  0x11,
  0x00,
  0xFF,
  0xC4,
  0x00,
  0x1F,
  0x00,
  0x00,
  0x01,
  0x05,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x02,
  0x03,
  0x04,
  0x05,
  0x06,
  0x07,
  0x08,
  0x09,
  0x0A,
  0x0B,
  0xFF,
  0xDA,
  0x00,
  0x08,
  0x01,
  0x01,
  0x00,
  0x00,
  0x3F,
  0x00,
  0xBF,
  0x00,
  0xFF,
  0xD9,
];
