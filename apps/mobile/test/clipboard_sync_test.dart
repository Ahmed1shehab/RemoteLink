import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/clipboard/clipboard_controller.dart';
import 'package:remotelink_mobile/src/features/clipboard/clipboard_watcher.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

/// A watcher a test can fire by hand, standing in for the platform's own.
final class _FakeClipboardWatcher implements ClipboardWatcher {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  void fire() => _controller.add(null);

  Future<void> close() => _controller.close();

  @override
  Stream<void> get changes => _controller.stream;
}

/// The phone's clipboard, in memory.
///
/// `Clipboard` is a platform channel, and there is no platform under a test —
/// without this every read returns null and the controller has nothing to send.
final class _FakeSystemClipboard {
  String? text;

  void install(TestWidgetsFlutterBinding binding) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.getData':
            return <String, Object?>{'text': text};
          case 'Clipboard.setData':
            text = (call.arguments as Map<Object?, Object?>)['text'] as String?;
            return null;
          default:
            return null;
        }
      },
    );
  }

  void remove(TestWidgetsFlutterBinding binding) =>
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('automatic clipboard sync', () {
    late RemoteLinkServer server;
    late RemoteLinkClient client;
    late Session desktopSession;
    late ProviderContainer container;
    late _FakeClipboardWatcher watcher;
    late _FakeSystemClipboard clipboard;
    late DeviceIdentity desktopIdentity;
    late InMemoryTrustStore trust;

    setUp(() async {
      desktopIdentity = await DeviceIdentity.fromPrivateKey(
        Uint8List.fromList(List<int>.filled(32, 7)),
      );
      final phoneIdentity = await DeviceIdentity.fromPrivateKey(
        Uint8List.fromList(List<int>.filled(32, 9)),
      );

      // Pre-trusted, so the session comes up already usable. An unpaired peer
      // lands in the pairing state, where nothing is carried.
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

      final accepted = server.accepted.first;
      final connected =
          client.states.firstWhere((s) => s == ClientState.connected);
      await client.connect(
        ConnectionTarget(
          host: '127.0.0.1',
          port: server.boundPort,
          deviceId: desktopIdentity.id,
          serverPublicKey: desktopIdentity.publicKey,
        ),
      );
      await connected.timeout(const Duration(seconds: 10));
      desktopSession =
          (await accepted.timeout(const Duration(seconds: 10))).session;

      watcher = _FakeClipboardWatcher();
      clipboard = _FakeSystemClipboard()..install(binding);

      container = ProviderContainer(
        overrides: <Override>[
          identityStoreProvider.overrideWith((ref) async =>
              InMemoryIdentityStore()),
          identityProvider.overrideWith((ref) => Future<DeviceIdentity>.value(
                phoneIdentity,
              )),
          clientProvider.overrideWith((ref) async => client),
          clipboardControllerProvider.overrideWith(
            (ref) => MobileClipboardController(ref, watcher: watcher),
          ),
        ],
      );
      // Reading the provider builds the controller, which subscribes to the
      // watcher and to the client's messages.
      container.read(clipboardControllerProvider.notifier);
      await container.read(clientProvider.future);
      await pumpEventQueue();
    });

    tearDown(() async {
      container.dispose();
      clipboard.remove(binding);
      await watcher.close();
      await client.disconnect();
      await server.stop();
      await trust.dispose();
    });

    /// The next clipboard update the desktop sees, or null if none arrives.
    Future<ClipboardUpdate?> nextUpdate({
      Duration within = const Duration(seconds: 2),
    }) =>
        desktopSession.messages
            .where((m) => m is ClipboardUpdate)
            .cast<ClipboardUpdate>()
            .first
            .timeout(within, onTimeout: () => throw TimeoutException('none'))
            .then<ClipboardUpdate?>((update) => update)
            .catchError((Object _) => null);

    test('a copy on the phone reaches the computer with no button pressed',
        () async {
      final seen = nextUpdate();
      clipboard.text = 'copied on the phone';
      watcher.fire();

      final update = await seen;
      expect(update, isNotNull);
      expect(update!.plainText, 'copied on the phone');
    });

    test('the phone does not read back what the computer just sent it',
        () async {
      await desktopSession.send(
        ClipboardUpdate(
          items: <ClipboardItem>[ClipboardItem.text('from the computer')],
          contentHash: Uint8List.fromList(List<int>.filled(16, 1)),
          originDeviceId: desktopIdentity.id.value,
          originSequence: 1,
        ),
      );
      await pumpEventQueue(times: 40);
      expect(clipboard.text, 'from the computer');

      // Writing the clipboard fires the same notification a user copy does. If
      // that provoked a read, every sync would cost the user an Android toast
      // or an iOS paste alert for content they did not copy.
      final echo = nextUpdate(within: const Duration(milliseconds: 900));
      watcher.fire();
      expect(await echo, isNull);
    });

    test('an update the phone does not apply still advances its clock',
        () async {
      // The regression, on the general form of it. The phone adopted the
      // computer's sequence at the bottom of the apply path, after every guard
      // that can return early — a repeat of content it already holds, an
      // update marked sensitive, sync switched off. Any of those left the
      // phone's clock behind the computer's, so the phone's next copy tied on
      // sequence, lost the device-id tie-break, and was discarded by the
      // computer with no sign of it on the phone at all.
      //
      // Driven here through the sensitive guard because that one returns
      // before writing the clipboard, which keeps the test off the wall clock:
      // a write would trip the echo suppression the previous test pins.
      await desktopSession.send(
        ClipboardUpdate(
          items: <ClipboardItem>[ClipboardItem.text('a password, probably')],
          contentHash: Uint8List.fromList(List<int>.filled(16, 2)),
          originDeviceId: desktopIdentity.id.value,
          originSequence: 9,
          isSensitive: true,
        ),
      );
      await pumpEventQueue(times: 40);
      expect(
        clipboard.text,
        isNull,
        reason: 'a sensitive update is still not mirrored',
      );

      final seen = nextUpdate();
      clipboard.text = 'something new from the phone';
      watcher.fire();

      final update = await seen;
      expect(update, isNotNull);
      expect(
        update!.originSequence,
        greaterThan(9),
        reason: 'a copy made after the computer spoke has to beat its clock',
      );
    });
  });
}
