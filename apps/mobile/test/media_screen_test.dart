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
}
