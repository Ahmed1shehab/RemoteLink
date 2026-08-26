import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/input/pointer_controller.dart';
import 'package:remotelink_mobile/src/features/watch/watch_bridge.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

/// Stands in for `WatchBridge.swift`: lets a test push what the wrist did onto
/// the channel the real iOS host publishes.
final class _FakeWatchChannel {
  _FakeWatchChannel(this.binding);

  final TestWidgetsFlutterBinding binding;

  /// Every `setLinkState` the app sent back to the watch.
  final List<Map<Object?, Object?>> published = <Map<Object?, Object?>>[];

  MockStreamHandlerEventSink? _sink;

  void install() {
    binding.defaultBinaryMessenger.setMockStreamHandler(
      kWatchCommandChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) => _sink = events,
        onCancel: (arguments) => _sink = null,
      ),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      kWatchChannel,
      (call) async {
        if (call.method == 'setLinkState') {
          published.add(call.arguments as Map<Object?, Object?>);
        }
        return null;
      },
    );
  }

  void remove() {
    binding.defaultBinaryMessenger
        .setMockStreamHandler(kWatchCommandChannel, null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(kWatchChannel, null);
  }

  /// Delivers one intent, as the watch would.
  void send(Map<String, Object?> command) => _sink?.success(command);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('the translator', () {
    test('carries the sub-pixel remainder rather than rounding it away', () {
      final translator = WatchCommandTranslator(
        settings: const PointerSettings(sensitivity: 1),
      );

      // Four tenths of a pixel, four times over. Rounded independently every
      // one of these is zero and the cursor never moves, which is exactly what
      // a slow, careful drag on a watch produces.
      expect(translator.translate(<Object?, Object?>{'t': 'move', 'dx': 0.4, 'dy': 0}), isEmpty);
      expect(translator.translate(<Object?, Object?>{'t': 'move', 'dx': 0.4, 'dy': 0}), isEmpty);
      final third =
          translator.translate(<Object?, Object?>{'t': 'move', 'dx': 0.4, 'dy': 0});
      expect(third, hasLength(1));
      expect((third.single as MouseMove).deltaX, 1);
    });

    test('applies the linear sensitivity the user set', () {
      final translator = WatchCommandTranslator(
        settings: const PointerSettings(sensitivity: 2),
      );
      final messages =
          translator.translate(<Object?, Object?>{'t': 'move', 'dx': 5, 'dy': -3});
      final move = messages.single as MouseMove;
      expect(move.deltaX, 10);
      expect(move.deltaY, -6);
    });

    test('a click is a press and a release, in that order', () {
      final translator =
          WatchCommandTranslator(settings: const PointerSettings());
      final messages =
          translator.translate(<Object?, Object?>{'t': 'click', 'b': 'right'});
      expect(messages, hasLength(2));
      expect((messages[0] as MouseButtonEvent).button, MouseButton.right);
      expect((messages[0] as MouseButtonEvent).pressed, isTrue);
      expect((messages[1] as MouseButtonEvent).pressed, isFalse);
    });

    test('the drag toggle holds the button down without releasing it', () {
      final translator =
          WatchCommandTranslator(settings: const PointerSettings());
      final down = translator
          .translate(<Object?, Object?>{'t': 'button', 'b': 'left', 'down': true});
      expect(down, hasLength(1));
      expect((down.single as MouseButtonEvent).pressed, isTrue);
    });

    test('the crown follows the natural-scrolling setting', () {
      final natural = WatchCommandTranslator(
        settings: const PointerSettings(naturalScrolling: true),
      );
      final classic = WatchCommandTranslator(
        settings: const PointerSettings(naturalScrolling: false),
      );
      final up = natural
          .translate(<Object?, Object?>{'t': 'scroll', 'dy': 3})
          .single as MouseScroll;
      final down = classic
          .translate(<Object?, Object?>{'t': 'scroll', 'dy': 3})
          .single as MouseScroll;
      expect(up.linesY, 3);
      expect(down.linesY, -3);
    });

    test('a click batched with movement lands after the movement', () {
      // The watch sends both in one message to save a round trip. The order is
      // what makes that safe: a click emitted before the movement that aimed it
      // presses the button where the cursor used to be.
      final translator = WatchCommandTranslator(
        settings: const PointerSettings(sensitivity: 1),
      );
      final messages = translator.translate(
        <Object?, Object?>{'t': 'move', 'dx': 9, 'dy': 4, 'clicks': 1},
      );
      expect(messages, hasLength(3));
      expect(messages[0], isA<MouseMove>());
      expect((messages[1] as MouseButtonEvent).pressed, isTrue);
      expect((messages[2] as MouseButtonEvent).pressed, isFalse);
    });

    test('a click batched with movement too small to register still fires', () {
      // A tap is a gesture that went nowhere, so the movement riding with it
      // rounds to nothing. Dropping the message on that basis would mean taps
      // silently did not click.
      final translator =
          WatchCommandTranslator(settings: const PointerSettings());
      final messages = translator.translate(
        <Object?, Object?>{'t': 'move', 'dx': 0.0, 'dy': 0.0, 'clicks': 1},
      );
      expect(messages, hasLength(2));
      expect(messages.every((m) => m is MouseButtonEvent), isTrue);
    });

    test('a double click is one gesture, not two clicks', () {
      // The distinction the computer cares about. macOS opens a file on a
      // `clickCount` of two and does nothing at all for two separate clicks of
      // one, however close together they land — so a watch double tap that
      // arrived as two singles did nothing, which is what it did.
      final translator =
          WatchCommandTranslator(settings: const PointerSettings());
      final messages = translator.translate(<Object?, Object?>{
        't': 'move',
        'dx': 0.0,
        'dy': 0.0,
        'clicks': 1,
        'clickCount': 2,
      });
      expect(messages, hasLength(2));
      expect((messages[0] as MouseButtonEvent).clickCount, 2);
      expect((messages[1] as MouseButtonEvent).clickCount, 2);
    });

    test('press and release are separate edges, and keep their order', () {
      // Holding to select text is a button that goes down and stays down. The
      // failure to avoid is a press with no release: the computer is left
      // holding a button nobody let go of, and every later move drags.
      final translator =
          WatchCommandTranslator(settings: const PointerSettings());
      final down = translator.translate(
        <Object?, Object?>{'t': 'move', 'dx': 0.0, 'dy': 0.0, 'button': 1},
      );
      expect(down, hasLength(1));
      expect((down.single as MouseButtonEvent).pressed, isTrue);

      final up = translator.translate(
        <Object?, Object?>{'t': 'move', 'dx': 0.0, 'dy': 0.0, 'button': 2},
      );
      expect(up, hasLength(1));
      expect((up.single as MouseButtonEvent).pressed, isFalse);
    });

    test('the button edge precedes movement clicks in the same message', () {
      final translator =
          WatchCommandTranslator(settings: const PointerSettings(sensitivity: 1));
      final messages = translator.translate(<Object?, Object?>{
        't': 'move',
        'dx': 10,
        'dy': 0,
        'button': 1,
        'clicks': 1,
      });
      // Movement, then the hold, then the click inside it.
      expect(messages[0], isA<MouseMove>());
      expect((messages[1] as MouseButtonEvent).pressed, isTrue);
      expect(messages, hasLength(4));
    });
  });

  group('the motion smoother', () {
    test('pays a batch out in slices rather than one jump', () {
      final smoother = WatchMotionSmoother();
      final start = DateTime(2026);
      // Two batches, 32 ms apart, so the measured interval is realistic.
      smoother.addBatch(0, 0, start);
      smoother.addBatch(64, 0, start.add(const Duration(milliseconds: 32)));

      final first = smoother.slice();
      expect(first, isNotNull);
      // An eighth-of-the-interval slice, not the whole 64 pixels.
      expect(first!.deltaX, lessThan(32));
      expect(first.deltaX, greaterThan(0));
      expect(smoother.isIdle, isFalse);
    });

    test('delivers the whole batch and then stops', () {
      final smoother = WatchMotionSmoother();
      final start = DateTime(2026);
      smoother.addBatch(0, 0, start);
      smoother.addBatch(40, -20, start.add(const Duration(milliseconds: 32)));

      var totalX = 0;
      var totalY = 0;
      // Generous bound: the point is that it terminates, not how fast.
      for (var i = 0; i < 200 && !smoother.isIdle; i++) {
        final step = smoother.slice();
        totalX += step?.deltaX ?? 0;
        totalY += step?.deltaY ?? 0;
      }
      expect(smoother.isIdle, isTrue,
          reason: 'the smoother never finished paying the batch out');
      // Every pixel arrives. Losing some would be a cursor that drifts short of
      // where the wrist put it, a little more on every gesture.
      expect(totalX, 40);
      expect(totalY, -20);
    });

    test('flush hands over everything at once, for a click', () {
      final smoother = WatchMotionSmoother();
      smoother.addBatch(30, 12, DateTime(2026));
      final flushed = smoother.flush();
      expect(flushed!.deltaX, 30);
      expect(flushed.deltaY, 12);
      expect(smoother.isIdle, isTrue);
    });

    test('a slice smaller than a pixel is carried, not lost', () {
      final smoother = WatchMotionSmoother();
      final start = DateTime(2026);
      smoother.addBatch(0, 0, start);
      smoother.addBatch(1, 0, start.add(const Duration(milliseconds: 100)));

      var total = 0;
      for (var i = 0; i < 200 && !smoother.isIdle; i++) {
        total += smoother.slice()?.deltaX ?? 0;
      }
      expect(total, 1);
    });
    test('a verb it has never heard of is ignored, not thrown on', () {
      // A watch updated ahead of the phone will send exactly this. Silence is
      // the right answer; an exception on the user's wrist is not.
      final translator =
          WatchCommandTranslator(settings: const PointerSettings());
      expect(
        translator.translate(<Object?, Object?>{'t': 'teleport', 'x': 1}),
        isEmpty,
      );
    });
  });

  group('the relay', () {
    late RemoteLinkServer server;
    late RemoteLinkClient client;
    late Session desktopSession;
    late ProviderContainer container;
    late _FakeWatchChannel channel;
    late InMemoryTrustStore trust;
    late DeviceIdentity desktopIdentity;

    setUp(() async {
      desktopIdentity = await DeviceIdentity.fromPrivateKey(
        Uint8List.fromList(List<int>.filled(32, 3)),
      );
      final phoneIdentity = await DeviceIdentity.fromPrivateKey(
        Uint8List.fromList(List<int>.filled(32, 5)),
      );

      trust = InMemoryTrustStore();
      await trust.upsert(
        TrustedPeer(
          id: phoneIdentity.id,
          publicKey: phoneIdentity.publicKey,
          name: 'Test Phone',
          platform: PlatformKind.ios,
          pairedAt: DateTime.now(),
          permissionTier: PermissionTier.extended.wireValue,
        ),
      );

      server = RemoteLinkServer(
        identity: desktopIdentity,
        capabilities: const Capabilities(Capabilities.mouse),
        trustStore: trust,
        clock: SystemClock(),
        port: 0,
      );
      await server.start();

      client = RemoteLinkClient(
        identity: phoneIdentity,
        capabilities: const Capabilities(Capabilities.mouse),
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
          displayName: 'Studio Mac',
        ),
      );
      await connected.timeout(const Duration(seconds: 10));
      desktopSession =
          (await accepted.timeout(const Duration(seconds: 10))).session;

      channel = _FakeWatchChannel(binding)..install();

      container = ProviderContainer(
        overrides: <Override>[
          identityStoreProvider
              .overrideWith((ref) async => InMemoryIdentityStore()),
          identityProvider.overrideWith(
            (ref) => Future<DeviceIdentity>.value(phoneIdentity),
          ),
          clientProvider.overrideWith((ref) async => client),
          // There is no iOS under a `flutter test`, and the relay is switched
          // off everywhere else — so without this the provider returns before
          // it subscribes to anything and the test would pass by doing nothing.
          watchSupportedProvider.overrideWithValue(true),
        ],
      );
      container.read(watchBridgeProvider);
      await container.read(clientProvider.future);
      await pumpEventQueue();
    });

    tearDown(() async {
      container.dispose();
      channel.remove();
      await client.disconnect();
      await server.stop();
      await trust.dispose();
    });

    test('what the wrist did reaches the computer', () async {
      final received = <Message>[];
      final subscription = desktopSession.messages.listen(received.add);
      addTearDown(subscription.cancel);

      channel.send(<String, Object?>{'t': 'move', 'dx': 12.0, 'dy': -6.0});
      channel.send(<String, Object?>{'t': 'click', 'b': 'left'});
      channel.send(<String, Object?>{'t': 'scroll', 'dy': 2.0});
      await pumpEventQueue(times: 40);

      final moves = received.whereType<MouseMove>().toList();
      expect(moves, isNotEmpty, reason: 'no pointer movement arrived');
      // The default sensitivity is 1.6, applied linearly.
      expect(moves.first.deltaX, 19);
      expect(moves.first.deltaY, -9);

      final buttons = received.whereType<MouseButtonEvent>().toList();
      expect(buttons, hasLength(2));
      expect(buttons.first.button, MouseButton.left);

      expect(received.whereType<MouseScroll>(), hasLength(1));
    });

    test('the watch is told which computer it is driving', () async {
      await pumpEventQueue(times: 20);
      expect(
        channel.published,
        isNotEmpty,
        reason: 'the watch was never told anything about the link',
      );
      final latest = channel.published.last;
      expect(latest['connected'], isTrue);
      expect(latest['peer'], 'Studio Mac');
    });
  });
}
