import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/devices/device_list_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';

import 'support/fakes.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required TrustStore trustStore,
    bool discoveryOperational = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: mobileDeviceListOverrides(
          discoveryOperational: discoveryOperational,
          trustStore: trustStore,
          identityStore: InMemoryIdentityStore(),
        ),
        child: const MaterialApp(home: DeviceListScreen()),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  /// A computer this phone has paired with but has no address for.
  ///
  /// Reachable in practice: `lastAddress` is only written at pairing and after
  /// an automatic reconnect, so a trust store restored from backup, or a
  /// pairing made over a link whose address was never recorded, lands here.
  Future<TrustStore> pairedWithoutAddress() async {
    final identity = await DeviceIdentity.generate();
    final trust = InMemoryTrustStore();
    await trust.upsert(
      TrustedPeer(
        id: identity.id,
        publicKey: identity.publicKey,
        name: 'Office Mac',
        platform: PlatformKind.macos,
        pairedAt: DateTime.now(),
        permissionTier: 2,
      ),
    );
    return trust;
  }

  group('a paired computer with no remembered address', () {
    testWidgets('is still listed', (tester) async {
      // It used to be dropped from the list entirely. On a network where
      // discovery finds nothing, that left the screen permanently empty — the
      // one computer the user was certain they had set up was the one the
      // screen refused to show.
      await pump(tester, trustStore: await pairedWithoutAddress());

      expect(find.text('Office Mac'), findsOneWidget);
      expect(
        find.text('Looking for computers'),
        findsNothing,
        reason: 'searched for computers while holding one it could have shown',
      );
    });

    testWidgets('says what it needs instead of showing a blank address',
        (tester) async {
      await pump(tester, trustStore: await pairedWithoutAddress());
      expect(find.text('Paired · tap to enter its address'), findsOneWidget);
    });

    testWidgets('asks for the address when tapped', (tester) async {
      await pump(tester, trustStore: await pairedWithoutAddress());

      await tester.tap(find.text('Office Mac'));
      await tester.pumpAndSettle();

      // Named, not generic: the user is answering a question about a machine
      // they own rather than being asked to configure something.
      expect(find.text('Where is Office Mac?'), findsOneWidget);
    });
  });

  group('when nothing is found', () {
    testWidgets('spins while there is still reason to wait', (tester) async {
      await pump(tester, trustStore: InMemoryTrustStore());

      expect(find.text('Looking for computers'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('stops spinning and says so', (tester) async {
      // The bug this exists for: discovery that succeeds and finds nothing is
      // indistinguishable from discovery that has not finished, so the screen
      // reported "operational" and span forever. A spinner with no end tells
      // the user their setup is fine and they should keep waiting.
      await pump(tester, trustStore: InMemoryTrustStore());
      await tester.pump(kDiscoveryPatience);

      expect(find.text('No computers found'), findsOneWidget);
      expect(find.text('Looking for computers'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('offers a way to try again', (tester) async {
      await pump(tester, trustStore: InMemoryTrustStore());
      await tester.pump(kDiscoveryPatience);

      expect(find.text('Search again'), findsOneWidget);
      expect(
        find.text('Connect by address'),
        findsOneWidget,
        reason: 'the route that works on these networks must stay visible',
      );
    });

    testWidgets('searching again puts the spinner back', (tester) async {
      await pump(tester, trustStore: InMemoryTrustStore());
      await tester.pump(kDiscoveryPatience);

      await tester.tap(find.text('Search again'));
      await tester.pump();

      expect(find.text('Looking for computers'), findsOneWidget);
    });

    testWidgets('a platform that refused discovery says so immediately',
        (tester) async {
      // Distinct from the timeout above, and it must not wait for it: when the
      // platform has actually refused, the answer is known at once.
      await pump(
        tester,
        trustStore: InMemoryTrustStore(),
        discoveryOperational: false,
      );

      expect(
        find.text('This device can’t search automatically'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
