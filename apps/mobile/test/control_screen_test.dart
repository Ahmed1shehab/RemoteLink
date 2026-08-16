import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/control/control_screen.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

void main() {
  testWidgets(
      'renders complete system status strip with battery, CPU, RAM, and uptime',
      (tester) async {
    const status = SystemStatus(
      volume: 0.8,
      isMuted: false,
      uptimeSeconds: 7320, // 2h 2m
      batteryPercent: 88,
      isCharging: true,
      cpuPercent: 12.4,
      memoryPercent: 64.0,
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
          systemStatusProvider.overrideWith(
            (ref) => Stream<SystemStatus?>.value(status),
          ),
          connectionQualityProvider.overrideWith(
            (ref) => const Stream<ConnectionQuality>.empty(),
          ),
        ],
        child: const MaterialApp(home: ControlScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('88%'), findsOneWidget);
    expect(find.byIcon(Icons.battery_charging_full), findsOneWidget);
    expect(find.text('CPU 12%'), findsOneWidget);
    expect(find.text('RAM 64%'), findsOneWidget);
    expect(find.text('2h 2m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('omits battery when not present but shows other metrics',
      (tester) async {
    const status = SystemStatus(
      volume: 0.5,
      isMuted: false,
      uptimeSeconds: 3600,
      batteryPercent: null,
      isCharging: null,
      cpuPercent: 25.0,
      memoryPercent: 40.0,
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
          systemStatusProvider.overrideWith(
            (ref) => Stream<SystemStatus?>.value(status),
          ),
          connectionQualityProvider.overrideWith(
            (ref) => const Stream<ConnectionQuality>.empty(),
          ),
        ],
        child: const MaterialApp(home: ControlScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.battery_full), findsNothing);
    expect(find.byIcon(Icons.battery_charging_full), findsNothing);
    expect(find.text('CPU 25%'), findsOneWidget);
    expect(find.text('RAM 40%'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'degrades gracefully and hides strip when platform reports nothing',
      (tester) async {
    const status = SystemStatus(
      volume: 0.5,
      isMuted: false,
      uptimeSeconds: 0,
      batteryPercent: null,
      isCharging: null,
      cpuPercent: null,
      memoryPercent: null,
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
          systemStatusProvider.overrideWith(
            (ref) => Stream<SystemStatus?>.value(status),
          ),
          connectionQualityProvider.overrideWith(
            (ref) => const Stream<ConnectionQuality>.empty(),
          ),
        ],
        child: const MaterialApp(home: ControlScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    // No chips, no zeros, no dashes.
    expect(find.text('CPU'), findsNothing);
    expect(find.text('RAM'), findsNothing);
    expect(find.byIcon(Icons.schedule), findsNothing);
    expect(find.byIcon(Icons.battery_full), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides strip when disconnected', (tester) async {
    const status = SystemStatus(
      volume: 0.8,
      isMuted: false,
      uptimeSeconds: 3600,
      batteryPercent: 88,
      isCharging: true,
      cpuPercent: 12.4,
      memoryPercent: 64.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.idle),
          ),
          systemStatusProvider.overrideWith(
            (ref) => Stream<SystemStatus?>.value(status),
          ),
          connectionQualityProvider.overrideWith(
            (ref) => const Stream<ConnectionQuality>.empty(),
          ),
        ],
        child: const MaterialApp(home: ControlScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('88%'), findsNothing);
    expect(find.text('CPU 12%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders TouchpadSurfaceView and handles gestures cleanly',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          systemStatusProvider.overrideWith(
            (ref) => const Stream<SystemStatus?>.empty(),
          ),
          connectionQualityProvider.overrideWith(
            (ref) => const Stream<ConnectionQuality>.empty(),
          ),
        ],
        child: const MaterialApp(home: ControlScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    // Verify touchpad tab is active and shows instructions
    expect(find.textContaining('Drag to move'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Mid'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);

    // Tap Left button
    await tester.tap(find.text('Left'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
