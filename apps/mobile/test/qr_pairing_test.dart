import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/pairing/pairing_code.dart';
import 'package:remotelink_mobile/src/features/pairing/pairing_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

/// What scanning a code is supposed to buy, and what it must never give back.
///
/// The whole reason QR pairing is stronger than six digits is that the phone
/// learns the computer's real static key over an optical channel *before* the
/// handshake, so a machine-in-the-middle has nothing to substitute. That
/// advantage survives only as long as a mismatch is fatal: the moment the app
/// offers "continue anyway", an attacker's plan becomes "cause a mismatch and
/// wait for the tap", which is a plan that works.
void main() {
  setUp(() {
    // Pairing successfully lands on the controls, which start the clipboard
    // watcher — a platform channel with no platform under a test. Unanswered
    // it throws `MissingPluginException` and fails the test for a reason that
    // has nothing to do with pairing.
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('com.remotelink.app/clipboard_changes'),
          MockStreamHandler.inline(onListen: (arguments, sink) {}),
        );
    addTearDown(
      () => TestWidgetsFlutterBinding.ensureInitialized()
          .defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel('com.remotelink.app/clipboard_changes'),
            null,
          ),
    );
  });

  testWidgets('a scanned key that does not match fails closed', (tester) async {
    await tester.runAsync(() async {
      final phone = await DeviceIdentity.generate();
      final desktop = await DeviceIdentity.generate();

      final server = RemoteLinkServer(
        identity: desktop,
        capabilities: const Capabilities(Capabilities.mediaControl),
        trustStore: InMemoryTrustStore(),
        clock: SystemClock(),
        port: 0,
      );
      await server.start();
      addTearDown(server.stop);

      final client = RemoteLinkClient(
        identity: phone,
        capabilities: kMobileCapabilities,
        clock: SystemClock(),
      );
      addTearDown(client.dispose);

      // Stands in for the attacker's key: the code said one thing, the machine
      // answering at that address proves another.
      final wrongKey = Uint8List.fromList(
        List<int>.generate(32, (i) => desktop.publicKey[i] ^ 0xFF),
      );

      final mobileTrust = InMemoryTrustStore();

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktop.id,
          serverPublicKey: wrongKey,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith((ref) => phone),
            identityStoreProvider.overrideWith(
              (ref) async => InMemoryIdentityStore(),
            ),
            trustStoreProvider.overrideWith((ref) async => mobileTrust),
            clientProvider.overrideWith((ref) async => client),
          ],
          child: const MaterialApp(
            home: PairingScreen(
              deviceName: 'Office Mac',
              address: '127.0.0.1',
              viaScannedCode: true,
            ),
          ),
        ),
      );
      // Real delays, not fake-clock pumps: the handshake is running on an
      // actual socket inside `runAsync`, and `pump(Duration)` advances only
      // the test binding's clock.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }

      expect(
        find.text('This is not the computer on the code'),
        findsOneWidget,
        reason: 'a substituted key is the event this flow exists to catch, and '
            'it must be named rather than reported as a stale pairing',
      );

      // The load-bearing half of the test. Cancel is the only button, so
      // there is no way onward — not the digits, not a retry that pairs
      // anyway. Asserted as "one button, and it is Cancel" rather than as a
      // list of forbidden words, because the next affordance someone adds
      // will be worded in a way this file did not think of.
      expect(find.widgetWithText(FilledButton, 'Cancel'), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
        findsOneWidget,
      );
      expect(find.byType(PairingCodeDisplay), findsNothing);

      expect(
        await mobileTrust.listPeers(),
        isEmpty,
        reason: 'nothing may be written to the trust store on a mismatch',
      );
    });
  });

  testWidgets('a scanned key that matches pairs without showing digits',
      (tester) async {
    await tester.runAsync(() async {
      final phone = await DeviceIdentity.generate();
      final desktop = await DeviceIdentity.generate();

      final server = RemoteLinkServer(
        identity: desktop,
        capabilities: const Capabilities(Capabilities.mediaControl),
        trustStore: InMemoryTrustStore(),
        clock: SystemClock(),
        port: 0,
      );
      await server.start();
      addTearDown(server.stop);

      final client = RemoteLinkClient(
        identity: phone,
        capabilities: kMobileCapabilities,
        clock: SystemClock(),
      );
      addTearDown(client.dispose);

      final mobileTrust = InMemoryTrustStore();

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktop.id,
          // Exactly what the camera would have read.
          serverPublicKey: desktop.publicKey,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith((ref) => phone),
            identityStoreProvider.overrideWith(
              (ref) async => InMemoryIdentityStore(),
            ),
            trustStoreProvider.overrideWith((ref) async => mobileTrust),
            clientProvider.overrideWith((ref) async => client),
          ],
          child: const MaterialApp(
            home: PairingScreen(
              deviceName: 'Office Mac',
              address: '127.0.0.1',
              viaScannedCode: true,
            ),
          ),
        ),
      );
      // Real delays, not fake-clock pumps: the handshake is running on an
      // actual socket inside `runAsync`, and `pump(Duration)` advances only
      // the test binding's clock.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }

      expect(
        find.byType(PairingCodeDisplay),
        findsNothing,
        reason: 'the camera already answered the question the digits ask',
      );
      expect(find.text('This is not the computer on the code'), findsNothing);

      final trusted = await mobileTrust.listPeers();
      expect(trusted, hasLength(1));
      expect(
        trusted.single.publicKey,
        desktop.publicKey,
        reason: 'the record must hold the key proven by the handshake',
      );
    });
  });
}
