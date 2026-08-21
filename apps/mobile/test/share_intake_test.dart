import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/share/share_intake.dart';
import 'package:remotelink_mobile/src/features/transfer/mobile_transfer_store.dart';
import 'package:remotelink_mobile/src/features/transfer/transfer_controller.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

/// A share intake a test can push into, standing in for the system's.
final class _FakeShareIntake implements ShareIntake {
  // Closed by `dispose`, which every tearDown here calls. The lint only
  // recognises a `close()` in the function that made the sink.
  // ignore: close_sinks
  final StreamController<SharedPayload> controller =
      StreamController<SharedPayload>.broadcast();

  SharedPayload? pending;

  Future<void> dispose() => controller.close();

  @override
  Stream<SharedPayload> get shares => controller.stream;

  @override
  Future<SharedPayload?> takePending() async {
    final held = pending;
    pending = null;
    return held;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sharing into Remote Link', () {
    late RemoteLinkServer server;
    late RemoteLinkClient client;
    late Session desktopSession;
    late ProviderContainer container;
    late _FakeShareIntake intake;
    late InMemoryTrustStore trust;
    late InMemoryTrustStore phoneTrust;
    late DeviceIdentity desktopIdentity;
    late Directory tempDir;
    final List<Message> received = <Message>[];
    StreamSubscription<Message>? tap;

    Future<void> connect() async {
      final accepted = server.accepted.first;
      final connected =
          client.states.firstWhere((s) => s == ClientState.connected);
      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
          displayName: 'Work Mac',
        ),
      );
      await connected.timeout(const Duration(seconds: 10));
      desktopSession =
          (await accepted.timeout(const Duration(seconds: 10))).session;
      // Recorded from the instant the session exists rather than awaited on
      // demand. A held share is flushed the moment a target appears, which can
      // be inside `connect` itself — earlier than any `await` a test could put
      // after it.
      tap = desktopSession.messages.listen(received.add);
      await pumpEventQueue(times: 20);
    }

    /// The first message of type [T] the desktop saw, or null if none arrives.
    Future<T?> awaitMessage<T extends Message>({
      Duration within = const Duration(seconds: 3),
    }) async {
      final deadline = DateTime.now().add(within);
      while (DateTime.now().isBefore(deadline)) {
        for (final message in received) {
          if (message is T) return message;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return null;
    }

    setUp(() async {
      received.clear();
      tempDir = Directory.systemTemp.createTempSync('share_test_');
      desktopIdentity = await DeviceIdentity.fromPrivateKey(
        Uint8List.fromList(List<int>.filled(32, 11)),
      );
      final phoneIdentity = await DeviceIdentity.fromPrivateKey(
        Uint8List.fromList(List<int>.filled(32, 13)),
      );

      trust = InMemoryTrustStore();
      await trust.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.android,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.extended.wireValue,
        ),
      );

      // The phone's own store, so the computer has the name the user gave it
      // rather than the short form of its device id.
      phoneTrust = InMemoryTrustStore();
      await phoneTrust.upsert(
        TrustedPeer(
          id: desktopIdentity.id,
          publicKey: desktopIdentity.publicKey,
          name: 'Work Mac',
          platform: PlatformKind.macos,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.extended.wireValue,
        ),
      );

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: const Capabilities(Capabilities.clipboardText),
        trustStore: trust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(Capabilities.clipboardText),
        clock: SystemClock(),
      );

      intake = _FakeShareIntake();
      container = ProviderContainer(
        overrides: <Override>[
          identityStoreProvider
              .overrideWith((ref) async => InMemoryIdentityStore()),
          identityProvider.overrideWith(
            (ref) => Future<DeviceIdentity>.value(phoneIdentity),
          ),
          clientProvider.overrideWith((ref) async => client),
          trustStoreProvider.overrideWith((ref) async => phoneTrust),
          shareIntakeProvider.overrideWithValue(intake),
          transferControllerProvider.overrideWith(
            (ref) => MobileTransferController(
              ref,
              customTransferStore: MobileTransferStore(tempDir),
            ),
          ),
        ],
      );
      await container.read(clientProvider.future);
      await pumpEventQueue();
    });

    tearDown(() async {
      await tap?.cancel();
      tap = null;
      container.dispose();
      await intake.dispose();
      await client.disconnect();
      await server.stop();
      await trust.dispose();
      await phoneTrust.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('shared text lands on the computer clipboard', () async {
      // The point of the feature: a link shared out of a browser should be
      // ready to paste on the computer, not arrive as a text file in Downloads.
      await connect();
      container.read(shareControllerProvider);
      await pumpEventQueue(times: 20);

      final seen = awaitMessage<ClipboardUpdate>();
      intake.controller.add(const SharedText('https://example.com/article'));

      final update = await seen;
      expect(update, isNotNull);
      expect(update!.plainText, 'https://example.com/article');
      expect(
        container.read(shareControllerProvider),
        isA<ShareSent>().having((s) => s.peerName, 'peerName', 'Work Mac'),
      );
    });

    test('shared files are offered like any other transfer', () async {
      // Offered, not written. A share is consent to send; accepting is still
      // the other machine's to give.
      await connect();
      container.read(shareControllerProvider);
      await pumpEventQueue(times: 20);

      final photo = File('${tempDir.path}/holiday.jpg')
        ..writeAsBytesSync(<int>[1, 2, 3, 4]);

      // A longer window than the text cases: a file offer goes through the
      // transfer controller and its store, and under a full-suite run that is
      // slow enough to outlast a three-second wait.
      final seen = awaitMessage<FileOffer>(within: const Duration(seconds: 10));
      intake.controller.add(
        SharedFiles(<({File file, String name})>[
          (file: photo, name: 'holiday.jpg'),
        ]),
      );

      final offer = await seen;
      expect(offer, isNotNull);
      expect(offer!.files.single.fileName, 'holiday.jpg');
      expect(offer.files.single.size, 4);
    });

    test('a share with nowhere to go waits for the connection', () async {
      // The ordinary case on a phone: the user shares into an app whose link
      // is still coming back up. Refusing it would lose what they shared.
      container.read(shareControllerProvider);
      await pumpEventQueue(times: 20);

      intake.controller.add(const SharedText('shared while offline'));
      await pumpEventQueue(times: 20);

      expect(container.read(shareControllerProvider), isA<ShareWaiting>());

      await connect();
      final update = await awaitMessage<ClipboardUpdate>();
      expect(update, isNotNull);
      expect(update!.plainText, 'shared while offline');
    });

    test('a share that arrived before the app was listening is collected',
        () async {
      // A cold start delivers the intent long before this isolate exists, so
      // the platform holds it and the controller asks for it on the way up.
      await connect();
      intake.pending = const SharedText('shared from a cold start');

      final seen = awaitMessage<ClipboardUpdate>();
      container.read(shareControllerProvider);

      final update = await seen;
      expect(update, isNotNull);
      expect(update!.plainText, 'shared from a cold start');
    });
  });
}
