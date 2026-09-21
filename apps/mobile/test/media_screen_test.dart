import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/media/media_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

void main() {
  testWidgets('renders brightness slider when capability is advertised',
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
          Capabilities.mediaControl | Capabilities.brightness,
        ),
        trustStore: desktopTrust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(
          Capabilities.mediaControl | Capabilities.brightness,
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
          mediaStateProvider.overrideWith(
            (ref) => Stream<MediaState?>.value(
              const MediaState(
                isPlaying: true,
                title: 'Test Track',
                artist: 'Test Artist',
                album: 'Test Album',
                positionSeconds: 30,
                durationSeconds: 180,
                volume: 0.7,
                isMuted: false,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MediaScreen())),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Test Track'), findsOneWidget);
    expect(find.byIcon(Icons.brightness_low), findsOneWidget);
    expect(find.byIcon(Icons.brightness_high), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2)); // Volume + Brightness
  });

  testWidgets('hides brightness slider when capability is not advertised',
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
        capabilities: const Capabilities(Capabilities.mediaControl),
        trustStore: desktopTrust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(Capabilities.mediaControl),
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
          mediaStateProvider.overrideWith(
            (ref) => Stream<MediaState?>.value(
              const MediaState(
                isPlaying: false,
                title: '',
                artist: '',
                album: '',
                positionSeconds: 0,
                durationSeconds: 0,
                volume: 0.5,
                isMuted: false,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MediaScreen())),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.brightness_low), findsNothing);
    expect(find.byIcon(Icons.brightness_high), findsNothing);
    expect(find.byType(Slider), findsOneWidget); // Only Volume
  });

  group('the transport button', () {
    /// A screen wired to a media stream the test drives, and a client with no
    /// session — sending is a no-op, which is exactly the case that used to
    /// leave the button frozen.
    ///
    /// Returns the way to push a state from the computer, rather than the
    /// controller itself: the tear-down here owns closing it.
    Future<void Function(MediaState)> pumpScreen(
      WidgetTester tester, {
      required bool isPlaying,
    }) async {
      // Closed by the tear-down below; the lint cannot see through the
      // callback it is handed to.
      // ignore: close_sinks
      final states = StreamController<MediaState?>.broadcast();
      addTearDown(states.close);

      late final RemoteLinkClient client;
      await tester.runAsync(() async {
        client = RemoteLinkClient(
          identity: await DeviceIdentity.fromPrivateKey(Uint8List(32)),
          capabilities: const Capabilities(Capabilities.mediaControl),
          clock: SystemClock(),
        );
      });
      addTearDown(client.dispose);

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
            mediaStateProvider.overrideWith((ref) => states.stream),
          ],
          child: const MaterialApp(home: Scaffold(body: MediaScreen())),
        ),
      );
      await tester.pump();
      states.add(_playing(isPlaying: isPlaying));
      await tester.pump();
      await tester.pump();
      return states.add;
    }

    testWidgets('answers the press before the computer does', (tester) async {
      // It used to be drawn purely from the computer's last word, so pressing
      // it did nothing at all until a state push arrived — and when the link
      // was down, or the computer's guess about a browser tab was stale, it sat
      // on the pause glyph however often it was pressed.
      await pumpScreen(tester, isPlaying: true);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
    });

    testWidgets('hands the state back once the computer agrees',
        (tester) async {
      final push = await pumpScreen(tester, isPlaying: true);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      push(_playing(isPlaying: false));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // The computer's own news — a track starting on its own — must not be
      // held back by the request that has already been answered.
      push(_playing(isPlaying: true));
      await tester.pump();
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });

    testWidgets('gives up and shows what the computer says', (tester) async {
      // The computer has the last word. A control that keeps insisting on a
      // state the machine is not in is worse than one that admits it.
      await pumpScreen(tester, isPlaying: true);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });
  });
}

MediaState _playing({required bool isPlaying}) => MediaState(
      isPlaying: isPlaying,
      title: 'Test Track',
      artist: 'Test Artist',
      album: 'Test Album',
      positionSeconds: 30,
      durationSeconds: 180,
      volume: 0.7,
      isMuted: false,
    );
