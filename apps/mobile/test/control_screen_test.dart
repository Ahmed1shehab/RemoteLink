import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/clipboard/clipboard_history_controller.dart';
import 'package:remotelink_mobile/src/features/control/control_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

/// Opens the clipboard tab of a [ControlScreen] backed by [history].
///
/// The real ring buffer is injected rather than a stub list: the tab's
/// behaviour is the ring's behaviour, and a stub would let the widget pass
/// against a model that cannot evict or refuse a pin.
Future<void> _pumpClipboardTab(
  WidgetTester tester,
  ClipboardHistory history,
) async {
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
        clipboardHistoryProvider.overrideWithValue(history),
      ],
      child: const MaterialApp(home: ControlScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();

  await tester.tap(find.byIcon(Icons.content_paste_outlined));
  await tester.pumpAndSettle();
}

Uint8List _hash(String seed) {
  final bytes = Uint8List(16);
  final source = utf8.encode(seed);
  for (var i = 0; i < source.length; i++) {
    bytes[i % bytes.length] = (bytes[i % bytes.length] * 31 + source[i]) & 0xff;
  }
  return bytes;
}

void _record(ClipboardHistory history, String value) => history.record(
      kind: ClipboardHistoryKind.text,
      data: Uint8List.fromList(utf8.encode(value)),
      contentHash: _hash(value),
      isConcealed: false,
    );

/// Scrolls the clipboard tab until [target] is on screen.
///
/// Scoped to the clipboard tab's own scrollable: [ControlScreen] keeps every
/// tab alive in an [IndexedStack], so an unscoped finder would happily scroll
/// the touchpad instead and then report the row missing.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find
        .descendant(
          of: find.byType(ClipboardView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

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

  testWidgets('the clipboard tab says the history is memory-only by default',
      (tester) async {
    final history = ClipboardHistory(clock: FakeClock());
    await _pumpClipboardTab(tester, history);

    await _scrollTo(tester, find.text('History'));

    expect(find.text('Keep history on this phone'), findsOneWidget);
    expect(
      find.textContaining('disappears when you close RemoteLink'),
      findsOneWidget,
      reason: 'the user must be able to tell where this list lives',
    );
    expect(find.textContaining('marks confidential is never recorded'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await history.dispose();
  });

  testWidgets('tapping a history entry re-copies it to the phone clipboard',
      (tester) async {
    final clock = FakeClock();
    final history = ClipboardHistory(clock: clock);
    _record(history, 'the older note');
    clock.advance(const Duration(minutes: 5));
    _record(history, 'the newer note');

    // Intercept the platform clipboard so the re-copy is observed, not assumed.
    final written = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<Object?, Object?>;
          written.add(args['text']! as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await _pumpClipboardTab(tester, history);
    await _scrollTo(tester, find.text('the older note'));

    await tester.tap(find.text('the older note'));
    await tester.pumpAndSettle();

    expect(written, equals(<String>['the older note']));

    // And it floats back to the top, exactly as copying it by hand would.
    expect(history.entries, hasLength(2));
    expect(history.entries.first.text, equals('the older note'));
    expect(tester.takeException(), isNull);

    await history.dispose();
  });

  testWidgets('pin, remove, and clear all work from the clipboard tab',
      (tester) async {
    final clock = FakeClock();
    final history = ClipboardHistory(clock: clock);
    _record(history, 'worth keeping');
    clock.advance(const Duration(minutes: 1));
    _record(history, 'disposable');

    await _pumpClipboardTab(tester, history);
    await _scrollTo(tester, find.text('worth keeping'));

    // The older row is the second one; pin it.
    await tester.tap(find.byIcon(Icons.push_pin_outlined).last);
    await tester.pumpAndSettle();

    expect(history.pinnedCount, equals(1));
    expect(
      history.entries
          .singleWhere((entry) => entry.text == 'worth keeping')
          .pinned,
      isTrue,
    );

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(history.entries, hasLength(1));
    expect(history.entries.single.text, equals('worth keeping'));

    await _scrollTo(tester, find.text('Clear all'));
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    expect(history.entries, isEmpty);
    expect(tester.takeException(), isNull);

    await history.dispose();
  });
}
