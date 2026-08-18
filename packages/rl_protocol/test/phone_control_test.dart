import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

/// Encodes then decodes through the real codec, asserting the type survives.
///
/// Through the codec rather than calling `readFrom` directly: the codec's
/// dispatch table is a separate place a message can be forgotten, and a message
/// with a perfect `writeTo`/`readFrom` pair that nothing routes to decodes as
/// `unknown` on the wire. That is exactly the mistake this exercises.
T _roundTrip<T extends Message>(MessageCodec codec, T message) {
  final frame = codec.encode(message);
  final decoded = codec.decode(Frame.readFrom(ByteReader(frame.encode())));
  expect(decoded, isA<T>(), reason: '${message.type.name} lost its type');
  return decoded as T;
}

void main() {
  late MessageCodec codec;

  setUp(() => codec = MessageCodec(clock: FakeClock()));

  group('wire codes', () {
    test('every phone-control code is in the 0x0C block and unique', () {
      // The block is registered in docs/PROTOCOL.md, and a code that strays
      // outside it lands in another subsystem's range — where it will collide
      // with something that has not been written yet, silently, years later.
      final codes = <int>{};
      for (final type in MessageType.values) {
        if (!type.name.startsWith('phoneControl')) continue;
        expect(
          type.code >> 8,
          0x0C,
          reason: '${type.name} is outside the phone-control block',
        );
        expect(codes.add(type.code), isTrue, reason: 'duplicate code');
      }
      expect(codes, hasLength(7));
    });

    test('the capability bit collides with nothing already assigned', () {
      // Capability bits are a single integer shared by every subsystem, and
      // two features on one bit is not a compile error — it is two features
      // that switch each other on.
      const assigned = <int>[
        Capabilities.mouse,
        Capabilities.keyboard,
        Capabilities.clipboardText,
        Capabilities.clipboardImage,
        Capabilities.clipboardFiles,
        Capabilities.screenCapture,
        Capabilities.mediaControl,
        Capabilities.mediaMetadata,
        Capabilities.fileTransfer,
        Capabilities.powerControl,
        Capabilities.launchApps,
        Capabilities.runCommands,
        Capabilities.gamepad,
        Capabilities.presentation,
        Capabilities.compression,
        Capabilities.unreliableChannel,
        Capabilities.sessionResumption,
        Capabilities.gestures,
        Capabilities.brightness,
      ];
      expect(assigned, isNot(contains(Capabilities.phoneControl)));
    });
  });

  group('PhoneControlStart', () {
    test('survives a round trip through the codec', () {
      final decoded = _roundTrip(
        codec,
        const PhoneControlStart(
          codec: ScreenCodec.jpeg,
          targetFps: 24,
          targetBitrateKbps: 1500,
        ),
      );

      expect(decoded.codec, ScreenCodec.jpeg);
      expect(decoded.targetFps, 24);
      expect(decoded.targetBitrateKbps, 1500);
    });

    test('defaults survive a round trip', () {
      final decoded = _roundTrip(codec, const PhoneControlStart());
      expect(decoded.codec, ScreenCodec.h264);
      expect(decoded.targetFps, 30);
      expect(decoded.targetBitrateKbps, 2000);
    });
  });

  group('PhoneControlStop', () {
    test('carries the reason it was stopped', () {
      final decoded = _roundTrip(
        codec,
        const PhoneControlStop(reason: ScreenStopReason.switchingDisplay),
      );
      expect(decoded.reason, ScreenStopReason.switchingDisplay);
    });
  });

  group('PhoneControlFrame', () {
    test('survives a round trip with its payload intact', () {
      final payload = Uint8List.fromList(
        List<int>.generate(512, (i) => (i * 7) & 0xFF),
      );
      final decoded = _roundTrip(
        codec,
        PhoneControlFrame(
          sequence: 4242,
          ptsMicros: 1234567890123,
          isKeyframe: true,
          width: 1179,
          height: 2556,
          data: payload,
        ),
      );

      expect(decoded.sequence, 4242);
      expect(decoded.ptsMicros, 1234567890123);
      expect(decoded.isKeyframe, isTrue);
      expect(decoded.width, 1179);
      expect(decoded.height, 2556);
      expect(decoded.data, payload);
    });

    test('an empty payload is carried, not confused with absence', () {
      final decoded = _roundTrip(
        codec,
        PhoneControlFrame(
          sequence: 0,
          ptsMicros: 0,
          isKeyframe: false,
          width: 0,
          height: 0,
          data: Uint8List(0),
        ),
      );
      expect(decoded.data, isEmpty);
      expect(decoded.isKeyframe, isFalse);
    });

    test('copies its payload rather than aliasing the caller buffer', () {
      // Capture buffers get reused. Holding a reference to one means the frame
      // quietly changes content between being built and being written.
      final buffer = Uint8List.fromList(<int>[1, 2, 3]);
      final frame = PhoneControlFrame(
        sequence: 1,
        ptsMicros: 1,
        isKeyframe: true,
        width: 1,
        height: 1,
        data: buffer,
      );
      buffer[0] = 99;
      expect(frame.data[0], 1);
    });
  });

  group('PhoneControlPointer', () {
    test('survives a round trip', () {
      final decoded = _roundTrip(
        codec,
        const PhoneControlPointer(x: 0.25, y: 0.75, pressed: true),
      );
      expect(decoded.x, closeTo(0.25, 1e-6));
      expect(decoded.y, closeTo(0.75, 1e-6));
      expect(decoded.pressed, isTrue);
    });

    test('a release is distinguishable from a press', () {
      final decoded = _roundTrip(
        codec,
        const PhoneControlPointer(x: 0, y: 0, pressed: false),
      );
      expect(decoded.pressed, isFalse);
    });
  });

  group('PhoneControlScroll', () {
    test('keeps the sign of both axes', () {
      // Sign is direction. A scroll that survives the trip with the right
      // magnitude and the wrong sign is worse than one that is dropped.
      final decoded = _roundTrip(
        codec,
        const PhoneControlScroll(deltaX: -12.5, deltaY: 40.25),
      );
      expect(decoded.deltaX, closeTo(-12.5, 1e-6));
      expect(decoded.deltaY, closeTo(40.25, 1e-6));
    });
  });

  group('PhoneControlNavigation', () {
    test('every action survives a round trip', () {
      for (final action in PhoneNavigationAction.values) {
        final decoded = _roundTrip(
          codec,
          PhoneControlNavigation(action: action),
        );
        expect(decoded.action, action);
      }
    });

    test('an unknown action byte decodes to back rather than throwing', () {
      // A newer peer may know actions this build does not. Throwing on the
      // unknown byte would close the session over a single navigation press.
      expect(PhoneNavigationAction.fromWire(0), PhoneNavigationAction.back);
      expect(PhoneNavigationAction.fromWire(255), PhoneNavigationAction.back);
    });
  });

  group('PhoneControlTextInput', () {
    test('survives a round trip, including non-ASCII', () {
      final decoded = _roundTrip(
        codec,
        const PhoneControlTextInput(text: 'naïve café — 中文 🎉'),
      );
      expect(decoded.text, 'naïve café — 中文 🎉');
    });

    test('empty text round trips', () {
      expect(_roundTrip(codec, const PhoneControlTextInput(text: '')).text, '');
    });
  });

  group('lossiness', () {
    test('the continuous streams are lossy and the discrete ones are not', () {
      // Lossy means "coalesce me when the queue backs up". Right for a frame
      // and for a pointer position, where only the newest matters. Wrong for a
      // keystroke or a Back press, where dropping one loses the whole event.
      expect(MessageType.phoneControlFrame.isLossy, isTrue);
      expect(MessageType.phoneControlPointer.isLossy, isTrue);
      expect(MessageType.phoneControlScroll.isLossy, isTrue);

      expect(MessageType.phoneControlStart.isLossy, isFalse);
      expect(MessageType.phoneControlStop.isLossy, isFalse);
      expect(MessageType.phoneControlNavigation.isLossy, isFalse);
      expect(MessageType.phoneControlTextInput.isLossy, isFalse);
    });
  });

  group('permission tiers', () {
    test('read-only is denied the phone entirely, screen included', () {
      // Matching the desk's own screen, which read-only was deliberately
      // refused: someone setting a device to "read only" is asking for less
      // access, not for a window onto a phone.
      const tier = PermissionTier.readOnly;
      for (final type in MessageType.values) {
        if (!type.name.startsWith('phoneControl')) continue;
        expect(tier.allows(type), isFalse, reason: type.name);
      }
    });

    test('standard may drive it', () {
      const tier = PermissionTier.standard;
      for (final type in MessageType.values) {
        if (!type.name.startsWith('phoneControl')) continue;
        expect(tier.allows(type), isTrue, reason: type.name);
      }
    });

    test('a tier that cannot watch a screen cannot watch a phone either', () {
      // Whichever tier this is, the point is that the two screen-sharing
      // directions are governed by one answer. Granting the reverse direction
      // to a tier denied the forward one would be a way around the setting.
      for (final tier in PermissionTier.values) {
        expect(
          tier.allows(MessageType.phoneControlFrame),
          tier.canViewScreen,
          reason: '${tier.name} disagrees with itself about screens',
        );
        expect(
          tier.allows(MessageType.phoneControlPointer),
          tier.canSendInput,
          reason: '${tier.name} disagrees with itself about input',
        );
      }
    });
  });
}
