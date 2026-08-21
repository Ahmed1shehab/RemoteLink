import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/providers.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';
import 'package:remotelink_desktop/src/ui/diagnostics_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

void main() {
  group('buildCapabilities', () {
    test('never claims phone control, however much else is available', () {
      // The guard on the whole feature. This computer has nowhere to draw a
      // phone's frames, and a capability bit is a promise to take part — so
      // claiming it would make a phone that *could* be captured offer itself
      // to a desktop that would drop every frame on the floor.
      //
      // Whoever builds the viewer changes this line, and this test with it.
      final everything = buildCapabilities(
        inputAvailable: true,
        clipboardAvailable: true,
        mediaAvailable: true,
        gesturesAvailable: true,
        brightnessAvailable: true,
        screenCaptureAvailable: true,
        // The forward direction switched on, so this test says something about
        // phone control rather than about the release switch.
        screenSharingShipped: true,
      );

      expect(everything.has(Capabilities.phoneControl), isFalse);
      expect(
        everything.has(Capabilities.screenCapture),
        isTrue,
        reason: 'the forward direction should be unaffected',
      );
    });
  });

  group('phoneControlBlockedReason', () {
    test('explains itself when the capability was never negotiated', () async {
      final pair = await _pair(desktop: _base, phone: _base);
      addTearDown(pair.dispose);

      final reason = phoneControlBlockedReason(
        ConnectedDevice(
          serverSession: pair.session,
          tier: PermissionTier.standard,
          name: 'Pixel 8 Pro',
        ),
      );

      expect(reason, isNotNull);
      // Not a bare "not supported". The user asked for this feature and the
      // honest answer names both halves of why it is missing.
      expect(reason, contains('iPhone'));
      expect(reason, contains('Android'));
      expect(reason, contains('viewer'));
    });

    test('drops to the tier reason once both ends could take part', () async {
      // The path that opens the day a viewer and a capture backend exist. It
      // is exercised now so that the *ordering* is right: a device with the
      // capability but not the permission must be told about the permission,
      // not told the feature does not exist.
      final pair = await _pair(desktop: _withControl, phone: _withControl);
      addTearDown(pair.dispose);

      expect(
        phoneControlBlockedReason(
          ConnectedDevice(
            serverSession: pair.session,
            tier: PermissionTier.readOnly,
            name: 'Pixel 8 Pro',
          ),
        ),
        contains('read-only'),
      );
    });

    test('is null when both ends take part and the tier allows it', () async {
      final pair = await _pair(desktop: _withControl, phone: _withControl);
      addTearDown(pair.dispose);

      expect(
        phoneControlBlockedReason(
          ConnectedDevice(
            serverSession: pair.session,
            tier: PermissionTier.standard,
            name: 'Pixel 8 Pro',
          ),
        ),
        isNull,
      );
    });

    test('one end alone is not enough', () async {
      // Capability negotiation is an intersection, and this is the case that
      // would slip through a check written against only the local side.
      final pair = await _pair(desktop: _withControl, phone: _base);
      addTearDown(pair.dispose);

      expect(
        phoneControlBlockedReason(
          ConnectedDevice(
            serverSession: pair.session,
            tier: PermissionTier.admin,
            name: 'Pixel 8 Pro',
          ),
        ),
        isNotNull,
      );
    });
  });

  group('the dispatcher', () {
    test('counts a phone frame as unsupported rather than swallowing it', () {
      // There is no handler, deliberately. An empty handler that drops the
      // frame would report the message as applied, and the diagnostics panel
      // would show a stream being handled while nothing was drawn.
      final dispatcher = createTestDispatcher();

      final handled = dispatcher.dispatch(
        PhoneControlFrame(
          sequence: 1,
          ptsMicros: 0,
          isKeyframe: true,
          width: 1,
          height: 1,
          data: Uint8List(0),
        ),
        PermissionTier.admin,
      );

      expect(handled, isFalse);
      expect(dispatcher.unsupportedCount, 1);
      expect(dispatcher.appliedCount, 0);
    });
  });

  group('the diagnostics projection', () {
    test('carries the reason from the live connection to the screen', () async {
      // The step the two widget tests below cannot see. They override the
      // provider, so they prove the screen draws what it is handed and say
      // nothing about whether anything hands it the right thing — which is
      // exactly where a field quietly stops being populated.
      final pair = await _pair(desktop: _base, phone: _base);
      addTearDown(pair.dispose);

      final device = ConnectedDevice(
        serverSession: pair.session,
        tier: PermissionTier.standard,
        name: 'Pixel 8 Pro',
      );
      final projected = deviceDiagnosticFor(device);

      expect(projected.phoneControlBlocked, isNotNull);
      expect(projected.phoneControlBlocked, phoneControlBlockedReason(device));
      // And the rest of the projection still arrives, so a mistake here is not
      // mistaken for the feature being absent.
      expect(projected.name, 'Pixel 8 Pro');
      expect(projected.tier, PermissionTier.standard);
    });

    test('leaves it null once the pair could take part', () async {
      final pair = await _pair(desktop: _withControl, phone: _withControl);
      addTearDown(pair.dispose);

      expect(
        deviceDiagnosticFor(
          ConnectedDevice(
            serverSession: pair.session,
            tier: PermissionTier.standard,
            name: 'Pixel 8 Pro',
          ),
        ).phoneControlBlocked,
        isNull,
      );
    });
  });

  group('the diagnostics screen', () {
    testWidgets('names the reason a phone cannot be controlled',
        (tester) async {
      // Not the home screen. This is a standing fact about the pair rather
      // than an action, and it is true of every device today — a line of it on
      // every tile of the main screen would be permanent clutter for a feature
      // that does not exist. Diagnostics is where someone goes to ask why.
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const reason = 'Controlling a phone from this computer is not available.';
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...desktopHomeOverrides,
            desktopDiagnosticsProvider.overrideWith(
              (ref) => Stream<DiagnosticsInfo>.value(
                _snapshotWith(
                  const DeviceDiagnostic(
                    id: 'phone-1',
                    name: 'Pixel 8 Pro',
                    address: '192.168.1.9',
                    tier: PermissionTier.standard,
                    roundTripMillis: 12,
                    qualityBars: 4,
                    phoneControlBlocked: reason,
                  ),
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: DiagnosticsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(reason), findsOneWidget);
    });

    testWidgets('says nothing when there is nothing to explain',
        (tester) async {
      // The day a phone can be controlled, the explanation has to disappear
      // rather than become a stale line claiming it cannot.
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...desktopHomeOverrides,
            desktopDiagnosticsProvider.overrideWith(
              (ref) => Stream<DiagnosticsInfo>.value(
                _snapshotWith(
                  const DeviceDiagnostic(
                    id: 'phone-1',
                    name: 'Pixel 8 Pro',
                    address: '192.168.1.9',
                    tier: PermissionTier.standard,
                    roundTripMillis: 12,
                    qualityBars: 4,
                  ),
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: DiagnosticsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.phonelink_off_outlined), findsNothing);
    });
  });
}

DiagnosticsInfo _snapshotWith(DeviceDiagnostic device) => DiagnosticsInfo(
      serviceStatus: const DesktopStatus(
        isRunning: true,
        deviceName: 'Test Mac',
        boundPort: 47811,
        localAddresses: <String>['192.168.1.2'],
        deviceId: 'desk-1',
      ),
      dispatcherCounters: const DispatcherCounters(
        applied: 0,
        denied: 0,
        unsupported: 0,
      ),
      backends: const BackendAvailability(
        input: BackendDiagnostic(name: 'Input', isAvailable: true),
        clipboard: BackendDiagnostic(name: 'Clipboard', isAvailable: true),
        media: BackendDiagnostic(name: 'Media control', isAvailable: true),
      ),
      devices: <DeviceDiagnostic>[device],
    );

const Capabilities _base = Capabilities(Capabilities.sessionResumption);
const Capabilities _withControl = Capabilities(
  Capabilities.sessionResumption | Capabilities.phoneControl,
);

final class _Pair {
  _Pair(this.server, this.client, this.session);

  final RemoteLinkServer server;
  final RemoteLinkClient client;
  final ServerSession session;

  Future<void> dispose() async {
    await client.dispose();
    await server.stop();
  }
}

/// A real handshake, so the negotiated set is the one the protocol produced.
///
/// Hand-building a capability set would test the assertion against itself: the
/// whole point of [phoneControlBlockedReason] is that it reads the
/// *intersection*, and only a real handshake computes one.
Future<_Pair> _pair({
  required Capabilities desktop,
  required Capabilities phone,
}) async {
  final phoneIdentity = await DeviceIdentity.generate();
  final desktopIdentity = await DeviceIdentity.generate();
  final trust = InMemoryTrustStore();
  await trust.upsert(
    TrustedPeer(
      id: phoneIdentity.id,
      publicKey: phoneIdentity.publicKey,
      name: 'Pixel 8 Pro',
      platform: PlatformKind.android,
      pairedAt: DateTime.now(),
      permissionTier: PermissionTier.standard.wireValue,
    ),
  );

  final server = RemoteLinkServer(
    identity: desktopIdentity,
    capabilities: desktop,
    trustStore: trust,
    clock: SystemClock(),
    port: 0,
  );
  await server.start();

  final client = RemoteLinkClient(
    identity: phoneIdentity,
    capabilities: phone,
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

  return _Pair(server, client, await server.accepted.first);
}
