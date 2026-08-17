import 'package:flutter_test/flutter_test.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'support/fakes.dart';

void main() {
  group('CommandDispatcher DeviceRename', () {
    test('applies valid DeviceRename and calls onDeviceRename callback', () {
      DeviceRename? receivedCommand;
      final dispatcher = createTestDispatcher(
        onDeviceRename: (command) {
          receivedCommand = command;
        },
      );

      final result = dispatcher.dispatch(
        const DeviceRename('My Pixel 9'),
        PermissionTier.standard,
      );

      expect(result, isTrue);
      expect(dispatcher.appliedCount, 1);
      expect(dispatcher.deniedCount, 0);
      expect(dispatcher.unsupportedCount, 0);
      expect(receivedCommand, isNotNull);
      expect(receivedCommand!.name, 'My Pixel 9');
    });

    test('normalises name in valid DeviceRename to Unicode NFC', () {
      DeviceRename? receivedCommand;
      final dispatcher = createTestDispatcher(
        onDeviceRename: (command) {
          receivedCommand = command;
        },
      );

      // Decomposed 'e' + combining acute
      final result = dispatcher.dispatch(
        const DeviceRename('e\u0301lise-phone'),
        PermissionTier.standard,
      );

      expect(result, isTrue);
      expect(receivedCommand!.name, 'élise-phone');
      expect(receivedCommand!.name.codeUnits.first, 0x00E9);
    });

    test('rejects invalid DeviceRename and leaves stored name untouched', () {
      String storedName = 'Original iPhone Name';
      var renameCalled = false;

      final dispatcher = createTestDispatcher(
        onDeviceRename: (command) {
          renameCalled = true;
          storedName = command.name;
        },
      );

      final invalidNames = <String>[
        '',
        '   ',
        '\t',
        '\n',
        'Phone\nName',
        'Phone\r\nName',
        'Phone\x00Name',
        'Phone\x1B[31mName\x1B[0m',
        'Phone\u200BName',
        '\uFEFFPhone',
        '\u2800',
        'A' * 65,
      ];

      for (final invalid in invalidNames) {
        renameCalled = false;
        final result = dispatcher.dispatch(
          DeviceRename(invalid),
          PermissionTier.standard,
        );

        expect(result, isFalse, reason: 'Expected "$invalid" to be rejected');
        expect(renameCalled, isFalse,
            reason: 'Handler must NOT be called for "$invalid"');
        expect(storedName, 'Original iPhone Name',
            reason: 'Stored name must remain untouched for "$invalid"');
      }

      expect(dispatcher.appliedCount, 0);
    });

    test('permits valid DeviceRename across all permission tiers', () {
      final tiers = <PermissionTier>[
        PermissionTier.readOnly,
        PermissionTier.standard,
        PermissionTier.extended,
        PermissionTier.admin,
      ];

      for (var i = 0; i < tiers.length; i++) {
        final tier = tiers[i];
        DeviceRename? received;
        final dispatcher = createTestDispatcher(
          onDeviceRename: (command) {
            received = command;
          },
        );

        final result = dispatcher.dispatch(
          DeviceRename('Tier Test $i'),
          tier,
        );

        expect(result, isTrue,
            reason: 'DeviceRename should be allowed at tier ${tier.name}');
        expect(received?.name, 'Tier Test $i');
        expect(dispatcher.appliedCount, 1);
        expect(dispatcher.deniedCount, 0);
      }
    });
  });

  group('CommandDispatcher file transfer', () {
    final offer = FileOffer(
      transferId: 'transfer-1',
      files: <OfferedFile>[
        OfferedFile(
          fileId: 'file-1',
          fileName: 'safe.txt',
          size: 4,
          fileType: 'text/plain',
        ),
      ],
    );

    test('refuses a standard-tier offer on the receiving boundary', () {
      var called = false;
      final dispatcher = createTestDispatcher(
        onFileTransferMessage: (_) => called = true,
      );

      expect(
        dispatcher.dispatch(offer, PermissionTier.standard),
        isFalse,
      );
      expect(called, isFalse);
      expect(dispatcher.deniedCount, 1);
    });

    test('routes an extended-tier offer', () {
      Message? routed;
      final dispatcher = createTestDispatcher(
        onFileTransferMessage: (message) => routed = message,
      );

      expect(
        dispatcher.dispatch(offer, PermissionTier.extended),
        isTrue,
      );
      expect(routed, same(offer));
    });
  });

  group('CommandDispatcher gesture matrix across PermissionTier', () {
    final gestureMessages = <Message>[
      const GestureZoom(
        magnificationDelta: 0.15,
        phase: GesturePhase.changed,
      ),
      const GestureRotate(
        degreesDelta: 45.0,
        phase: GesturePhase.changed,
      ),
      const GestureSwipe(
        fingerCount: 3,
        direction: SwipeDirection.up,
      ),
    ];

    for (final message in gestureMessages) {
      test('denies ${message.runtimeType} at readOnly tier', () {
        final backend = _RecordingInputBackend();
        final dispatcher = createTestDispatcher(input: backend);

        final result = dispatcher.dispatch(message, PermissionTier.readOnly);

        expect(result, isFalse);
        expect(dispatcher.deniedCount, 1);
        expect(dispatcher.appliedCount, 0);
        expect(backend.magnifyDelta, isNull);
        expect(backend.rotateDegrees, isNull);
        expect(backend.swipeDetails, isNull);
      });

      for (final tier in <PermissionTier>[
        PermissionTier.standard,
        PermissionTier.extended,
        PermissionTier.admin,
      ]) {
        test('applies ${message.runtimeType} at ${tier.name} tier', () {
          final backend = _RecordingInputBackend();
          final dispatcher = createTestDispatcher(input: backend);

          final result = dispatcher.dispatch(message, tier);

          expect(result, isTrue);
          expect(dispatcher.appliedCount, 1);
          expect(dispatcher.deniedCount, 0);

          switch (message) {
            case GestureZoom(:final magnificationDelta):
              expect(backend.magnifyDelta, magnificationDelta);
            case GestureRotate(:final degreesDelta):
              expect(backend.rotateDegrees, degreesDelta);
            case GestureSwipe(:final fingerCount, :final direction):
              expect(backend.swipeDetails?.fingerCount, fingerCount);
              expect(backend.swipeDetails?.direction, direction);
            default:
              fail('Unexpected gesture message type: $message');
          }
        });
      }
    }
  });

  group('CommandDispatcher brightness matrix across PermissionTier', () {
    const brightnessCommand = BrightnessCommand(relative: false, value: 0.75);

    for (final tier in PermissionTier.values) {
      test('applies BrightnessCommand at ${tier.name} tier', () {
        BrightnessCommand? received;
        final dispatcher = createTestDispatcher(
          onBrightnessCommand: (cmd) => received = cmd,
        );

        final result = dispatcher.dispatch(brightnessCommand, tier);

        expect(result, isTrue);
        expect(dispatcher.appliedCount, 1);
        expect(dispatcher.deniedCount, 0);
        expect(received?.relative, isFalse);
        expect(received?.value, 0.75);
      });
    }
  });

  group('CommandDispatcher ClipboardSyncToggle across PermissionTier', () {
    const toggleCommand = ClipboardSyncToggle(
      enabled: false,
      allowImages: false,
      allowFiles: false,
    );

    test('denies ClipboardSyncToggle at readOnly tier', () {
      var called = false;
      final dispatcher = createTestDispatcher(
        onClipboardSyncToggle: (_) => called = true,
      );

      final result =
          dispatcher.dispatch(toggleCommand, PermissionTier.readOnly);

      expect(result, isFalse);
      expect(called, isFalse);
      expect(dispatcher.deniedCount, 1);
      expect(dispatcher.appliedCount, 0);
    });

    for (final tier in <PermissionTier>[
      PermissionTier.standard,
      PermissionTier.extended,
      PermissionTier.admin,
    ]) {
      test('routes ClipboardSyncToggle at ${tier.name} tier', () {
        ClipboardSyncToggle? received;
        final dispatcher = createTestDispatcher(
          onClipboardSyncToggle: (toggle) => received = toggle,
        );

        final result = dispatcher.dispatch(toggleCommand, tier);

        expect(result, isTrue);
        expect(dispatcher.appliedCount, 1);
        expect(dispatcher.deniedCount, 0);
        expect(received, isNotNull);
        expect(received!.enabled, isFalse);
        expect(received!.allowImages, isFalse);
      });
    }
  });
}

class _RecordingInputBackend implements InputBackend {
  double? magnifyDelta;
  double? rotateDegrees;
  ({int fingerCount, SwipeDirection direction})? swipeDetails;

  @override
  bool get isAvailable => true;

  @override
  String? get unavailableReason => null;

  @override
  (int, int) get cursorPosition => (0, 0);

  @override
  ScreenBounds get virtualBounds => const ScreenBounds(
        x: 0,
        y: 0,
        width: 1920,
        height: 1080,
      );

  @override
  List<ScreenBounds> get displays => const <ScreenBounds>[];

  @override
  void moveCursorBy(int dx, int dy) {}

  @override
  void moveCursorTo(int x, int y) {}

  @override
  void mouseDown(MouseButton button, {int clickCount = 1}) {}

  @override
  void mouseUp(MouseButton button, {int clickCount = 1}) {}

  @override
  void scroll({
    int linesX = 0,
    int linesY = 0,
    int pixelsX = 0,
    int pixelsY = 0,
    bool isMomentum = false,
  }) {}

  @override
  void magnify(double delta) => magnifyDelta = delta;

  @override
  void rotate(double degrees) => rotateDegrees = degrees;

  @override
  void swipe({required int fingerCount, required SwipeDirection direction}) =>
      swipeDetails = (fingerCount: fingerCount, direction: direction);

  @override
  void keyEvent({required int hidUsage, required bool pressed}) {}

  @override
  void typeText(String text) {}

  @override
  void setModifiers(Modifiers modifiers) {}

  @override
  void releaseAll() {}

  @override
  void dispose() {}
}
