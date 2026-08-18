import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/control/control_screen.dart';
import 'package:remotelink_mobile/src/features/screen/remote_cursor.dart';
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

    // Decoding a frame is real work on the engine, so the tests that assert a
    // picture appeared have to run inside `runAsync` — and inside `runAsync`
    // the provider graph's real futures run too, including the one that asks
    // the platform where to store the identity. Unanswered, that throws a
    // MissingPluginException and fails the test for a reason unrelated to
    // anything it is testing.
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => Directory.systemTemp
              .createTempSync('remotelink-viewer-test')
              .path,
        );
    addTearDown(
      () => TestWidgetsFlutterBinding.ensureInitialized()
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
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

    await _decodeFrame(tester);

    _expectPictureOnScreen(tester);
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

    await _decodeFrame(tester);

    _expectPictureOnScreen(tester);
    expect(
      find.byKey(const ValueKey<String>('screen-viewer-pointer-surface')),
      findsNothing,
      reason: 'a read-only viewer must not wire up pointer handling at all',
    );
  });

  testWidgets('the pointer follows its own stream, not the frames',
      (tester) async {
    // The whole point of `ScreenCursor`. While the pointer arrived on the
    // frame it could only move as often as a couple of hundred kilobytes of
    // picture could cross the link — five to ten times a second — so the one
    // thing on screen the user is certainly watching was the jerkiest. Here
    // the frame never changes and the cursor still moves.
    late RemoteLinkClient client;
    await tester.runAsync(() async {
      client = await _connectedClient(tester);
    });

    final cursors = StreamController<Offset?>();
    addTearDown(cursors.close);

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
          screenCursorProvider.overrideWith((ref) => cursors.stream),
        ],
        child: const MaterialApp(home: ScreenViewerScreen()),
      ),
    );
    await _decodeFrame(tester);

    cursors.add(const Offset(0.2, 0.2));
    await tester.pump();
    final first = tester.widget<RemoteCursor>(find.byType(RemoteCursor));
    expect(first.normalised, const Offset(0.2, 0.2));

    cursors.add(const Offset(0.8, 0.6));
    await tester.pump();
    final second = tester.widget<RemoteCursor>(find.byType(RemoteCursor));
    expect(
      second.normalised,
      const Offset(0.8, 0.6),
      reason: 'the pointer did not move without a new frame behind it',
    );
  });

  testWidgets('the pointer disappears when it leaves the display',
      (tester) async {
    // Left at its last position the arrow sits frozen against an edge, which
    // reads as the stream having hung rather than as the pointer being on
    // another monitor.
    late RemoteLinkClient client;
    await tester.runAsync(() async {
      client = await _connectedClient(tester);
    });

    final cursors = StreamController<Offset?>();
    addTearDown(cursors.close);

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
          screenCursorProvider.overrideWith((ref) => cursors.stream),
        ],
        child: const MaterialApp(home: ScreenViewerScreen()),
      ),
    );
    await _decodeFrame(tester);

    cursors.add(const Offset(0.2, 0.2));
    await tester.pump();
    expect(
      tester.widget<RemoteCursor>(find.byType(RemoteCursor)).normalised,
      isNotNull,
    );

    cursors.add(null);
    await tester.pump();
    expect(
      tester.widget<RemoteCursor>(find.byType(RemoteCursor)).normalised,
      isNull,
    );
  });

  group('screenCursorUpdate', () {
    test('a cursor message moves the pointer', () {
      final update = screenCursorUpdate(
        const ScreenCursor(monitorId: 1, x: 0.25, y: 0.75),
      );
      expect(update, isNotNull);
      expect(update!.position, const Offset(0.25, 0.75));
    });

    test('a cursor message with no position takes the pointer away', () {
      // The distinction a plain `Offset?` cannot carry: this is an instruction
      // to stop drawing, not an absence of news. Confused for the latter the
      // arrow stays frozen against whichever edge it left by, which reads as
      // the stream having hung.
      final update = screenCursorUpdate(const ScreenCursor(monitorId: 1));
      expect(update, isNotNull);
      expect(update!.position, isNull);
    });

    test('a frame still carries the pointer, for an older desktop', () {
      // A desktop built before `ScreenCursor` reports the pointer only here.
      // Ignoring it would leave anyone on an older build with no cursor at all.
      final update = screenCursorUpdate(
        ScreenFrame(
          sequence: 1,
          ptsMicros: 0,
          isKeyframe: true,
          width: 4,
          height: 2,
          data: Uint8List(0),
          cursorX: 0.5,
          cursorY: 0.5,
        ),
      );
      expect(update, isNotNull);
      expect(update!.position, const Offset(0.5, 0.5));
    });

    test('a frame without a pointer says nothing rather than blanking it', () {
      // An older desktop omits these fields whenever it could not read the
      // pointer, so treating absence as departure would make the arrow flicker
      // on and off through every stream.
      expect(
        screenCursorUpdate(
          ScreenFrame(
            sequence: 1,
            ptsMicros: 0,
            isKeyframe: true,
            width: 4,
            height: 2,
            data: Uint8List(0),
          ),
        ),
        isNull,
      );
    });

    test('an unrelated message says nothing about the pointer', () {
      expect(screenCursorUpdate(const ClipboardRequest()), isNull);
    });
  });
}

/// Pumps until the frame has actually been decoded.
///
/// Decoding is real asynchronous work on the engine, which the test binding's
/// fake clock will never advance on its own — so it has to happen inside
/// [WidgetTester.runAsync]. Two plain pumps used to be enough only because
/// `Image.memory` puts *something* in the tree before it has an image.
Future<void> _decodeFrame(WidgetTester tester) async {
  // Alternating, and that is the whole reason this helper exists. Decoding
  // walks a chain of real engine calls — buffer, descriptor, codec, frame —
  // and the two halves of each step live in different worlds: the engine's
  // callback only fires while `runAsync` lets real time pass, and the `await`
  // that resumes afterwards is a microtask in the binding's fake zone, which
  // only `pump` drains. One of either is a deadlock; alternating walks the
  // chain one link per turn.
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    if (find.byType(RawImage).evaluate().isNotEmpty) return;
  }
}

/// Asserts a decoded picture is on screen, not merely a placeholder for one.
///
/// The old assertion — one `Image` widget exists — would have passed against a
/// frame that failed to decode, because the widget is in the tree either way.
void _expectPictureOnScreen(WidgetTester tester) {
  final raw = tester.widget<RawImage>(find.byType(RawImage));
  // A decoded image, not a placeholder standing in for one. The old assertion
  // — that an `Image` widget exists — would have passed against a frame the
  // engine rejected, because the widget goes into the tree either way.
  expect(raw.image, isNotNull, reason: 'the frame never finished decoding');
  // Never `fill`: a desk stretched to a phone's aspect ratio is unusable, and
  // it is the kind of thing that looks almost right in a screenshot.
  expect(raw.fit, BoxFit.contain);
}

/// A valid 4x2 JPEG, small enough to inline and real enough for the engine's own decoder.
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

/// A valid 4x2 JPEG: small enough to inline, real enough for the engine's own decoder.
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
