import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/pairing/pairing_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

/// The bug this file exists for.
///
/// A session that required pairing starts in `SessionState.pairing`, and in
/// that state `Session` drops every message outside subsystems 0x00 and 0x01 —
/// the permission grant, media state, system status, clipboard, and every file
/// transfer message. `completePairing()` is what lifts that, and only the
/// desktop was calling it.
///
/// So the phone confirmed the six digits, wrote its trust record, opened the
/// controls, and sat there with a session that discarded everything the
/// computer sent it. The touchpad said "Not connected" against a live
/// connection, the Media tab said "Nothing playing" while a track was playing,
/// and a file offer was accepted by the desktop and the acceptance thrown away.
/// Three unrelated-looking bug reports, one missing call.
///
/// It never reproduced on a reconnect. The desktop only asks for pairing when
/// the peer is not already in its trust store, so the second connection to the
/// same computer was always fine — which is exactly why this survived: it broke
/// the first session with a computer and nothing after it.
void main() {
  testWidgets('confirming the digits unblocks the session', (tester) async {
    await tester.runAsync(() async {
      final phone = await DeviceIdentity.generate();
      final desktop = await DeviceIdentity.generate();

      // No trust record for the phone, which is what makes the desktop ask for
      // pairing and puts both sessions into the state under test.
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

      final accepted = server.accepted.first;
      final pairing = client.states.firstWhere(
        (state) => state == ClientState.pairing,
      );

      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktop.id,
        ),
      );

      final serverSession = await accepted.timeout(const Duration(seconds: 10));
      await pairing.timeout(const Duration(seconds: 10));

      final session = client.session!;
      expect(
        session.state,
        SessionState.pairing,
        reason: 'the precondition: an unpaired session starts blocked',
      );

      // Nothing the desktop sends can get through yet. Asserted rather than
      // assumed, because it is the consequence that made the app look broken.
      var delivered = 0;
      final subscription = session.messages.listen((_) => delivered++);
      addTearDown(subscription.cancel);

      serverSession.session.completePairing();
      await serverSession.session.send(
        const MediaState(
          isPlaying: true,
          title: 'Something',
          artist: '',
          album: '',
          positionSeconds: 0,
          durationSeconds: 0,
          volume: 0.5,
          isMuted: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(delivered, 0, reason: 'blocked until the user confirms');

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith((ref) => phone),
            identityStoreProvider.overrideWith(
              (ref) async => InMemoryIdentityStore(),
            ),
            clientProvider.overrideWith((ref) async => client),
          ],
          child: const MaterialApp(
            home: PairingScreen(
              deviceName: 'Test Desktop',
              address: '127.0.0.1',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('The numbers match'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        session.state,
        SessionState.established,
        reason: 'confirming the digits has to lift the pairing gate, or every '
            'feature behind it stays dead for the whole session',
      );

      await serverSession.session.send(
        const MediaState(
          isPlaying: true,
          title: 'Something',
          artist: '',
          album: '',
          positionSeconds: 0,
          durationSeconds: 0,
          volume: 0.5,
          isMuted: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(delivered, greaterThan(0), reason: 'messages flow after pairing');
    });
  });
}
