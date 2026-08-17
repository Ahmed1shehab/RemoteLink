import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

/// Encodes then decodes [message], asserting the type survives the trip.
T _roundTrip<T extends Message>(MessageCodec codec, T message) {
  final frame = codec.encode(message);
  final wire = frame.encode();
  final decodedFrame = Frame.readFrom(ByteReader(wire));
  final decoded = codec.decode(decodedFrame);
  expect(decoded, isA<T>(), reason: '${message.type.name} lost its type');
  return decoded as T;
}

void main() {
  late MessageCodec codec;

  setUp(() => codec = MessageCodec(clock: FakeClock()));

  group('sequencing', () {
    test('sequence numbers increment per encoded frame', () {
      expect(codec.encode(const ClipboardRequest()).sequence, 0);
      expect(codec.encode(const ClipboardRequest()).sequence, 1);
      expect(codec.encode(const ClipboardRequest()).sequence, 2);
    });

    test('reset returns sequencing to zero for a re-established session', () {
      codec
        ..encode(const ClipboardRequest())
        ..encode(const ClipboardRequest())
        ..resetSequence();
      expect(codec.encode(const ClipboardRequest()).sequence, 0);
    });
  });

  group('compression', () {
    test('small payloads are never compressed', () {
      // The input hot path must not pay for DEFLATE.
      final frame = codec.encode(const MouseMove(deltaX: 3, deltaY: -5));
      expect(frame.flags.isCompressed, isFalse);
      expect(frame.payload.length, lessThan(8));
    });

    test('large compressible payloads shrink and round trip', () {
      final repetitive = 'the quick brown fox ' * 200;
      final frame = codec.encode(TextInput(repetitive));

      expect(frame.flags.isCompressed, isTrue);
      expect(frame.payload.length, lessThan(repetitive.length ~/ 2));

      final decoded = codec.decode(Frame.readFrom(ByteReader(frame.encode())));
      expect((decoded as TextInput).text, repetitive);
    });

    test('incompressible payloads stay raw rather than growing', () {
      // Pseudo-random bytes stand in for already-compressed content such as a
      // PNG clipboard image; DEFLATE would add overhead for no gain.
      var state = 0x12345678;
      final noise = String.fromCharCodes(
        List<int>.generate(4096, (_) {
          state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
          return 0x20 + (state % 90);
        }),
      );

      final frame = codec.encode(TextInput(noise));
      final decoded = codec.decode(Frame.readFrom(ByteReader(frame.encode())));
      expect((decoded as TextInput).text, noise);
    });

    test('a payload flagged compressed but not deflated is rejected', () {
      final corrupt = Frame(
        type: MessageType.textInput,
        sequence: 0,
        timestampMicros: 0,
        flags: const FrameFlags(FrameFlags.compressed),
        payload: Uint8List.fromList(<int>[0xFF, 0xFF, 0xFF, 0xFF]),
      );
      expect(() => codec.decode(corrupt), throwsA(isA<ProtocolError>()));
    });
  });

  group('message round trips', () {
    test('MouseMove preserves signed deltas', () {
      final decoded =
          _roundTrip(codec, const MouseMove(deltaX: -1234, deltaY: 5678));
      expect(decoded.deltaX, -1234);
      expect(decoded.deltaY, 5678);
    });

    test('MouseMove.merge sums deltas for coalescing', () {
      const a = MouseMove(deltaX: 3, deltaY: -2);
      const b = MouseMove(deltaX: -1, deltaY: 5);
      expect(a.merge(b).deltaX, 2);
      expect(a.merge(b).deltaY, 3);
    });

    test('MouseButtonEvent preserves click count', () {
      final decoded = _roundTrip(
        codec,
        const MouseButtonEvent(
          button: MouseButton.right,
          pressed: true,
          clickCount: 2,
        ),
      );
      expect(decoded.button, MouseButton.right);
      expect(decoded.pressed, isTrue);
      expect(decoded.clickCount, 2);
    });

    test('MouseScroll keeps line and pixel deltas independent', () {
      final decoded = _roundTrip(
        codec,
        const MouseScroll(
          linesX: -1,
          linesY: 3,
          pixelsX: -12,
          pixelsY: 40,
          isMomentum: true,
        ),
      );
      expect(decoded.linesY, 3);
      expect(decoded.pixelsY, 40);
      expect(decoded.isMomentum, isTrue);
      expect(decoded.isPrecise, isTrue);
    });

    test('KeyEvent preserves usage and absolute modifier state', () {
      final decoded = _roundTrip(
        codec,
        const KeyEvent(
          hidUsage: HidKey.keyC,
          pressed: true,
          modifiers: Modifiers(Modifiers.leftControl | Modifiers.leftShift),
        ),
      );
      expect(decoded.hidUsage, HidKey.keyC);
      expect(decoded.modifiers.hasControl, isTrue);
      expect(decoded.modifiers.hasShift, isTrue);
      expect(decoded.modifiers.hasAlt, isFalse);
    });

    test('TextInput carries emoji and non-Latin scripts intact', () {
      const sample = 'مرحبا 👋 日本語 café';
      expect(_roundTrip(codec, const TextInput(sample)).text, sample);
    });

    test('NamedShortcut round trips', () {
      final decoded =
          _roundTrip(codec, const NamedShortcutMessage(NamedShortcut.paste));
      expect(decoded.shortcut, NamedShortcut.paste);
    });

    test('ClipboardUpdate preserves multiple flavours', () {
      final update = ClipboardUpdate(
        items: <ClipboardItem>[
          ClipboardItem.text('plain'),
          ClipboardItem(
            contentType: ClipboardContentType.html,
            data: Uint8List.fromList('<b>rich</b>'.codeUnits),
          ),
        ],
        contentHash: Uint8List.fromList(List<int>.filled(16, 7)),
        originDeviceId: 'ABCDEFGHJKMNPQRSTVWXYZ0123',
        originSequence: 9,
      );

      final decoded = _roundTrip(codec, update);
      expect(decoded.items, hasLength(2));
      expect(decoded.plainText, 'plain');
      expect(decoded.items[1].contentType, ClipboardContentType.html);
      expect(decoded.originSequence, 9);
    });

    test('MediaState round trips with artwork omitted', () {
      final decoded = _roundTrip(
        codec,
        const MediaState(
          isPlaying: true,
          title: 'Title',
          artist: 'Artist',
          album: 'Album',
          positionSeconds: 12.5,
          durationSeconds: 210,
          volume: 0.75,
          isMuted: false,
          sourceApplication: 'Spotify',
        ),
      );
      expect(decoded.title, 'Title');
      expect(decoded.isPlaying, isTrue);
      expect(decoded.artworkPng, isNull);
      expect(decoded.positionSeconds, closeTo(12.5, 0.001));
    });

    test('SystemStatus round trips with optional fields absent', () {
      final decoded = _roundTrip(
        codec,
        const SystemStatus(volume: 0.5, isMuted: true, uptimeSeconds: 3600),
      );
      expect(decoded.batteryPercent, isNull);
      expect(decoded.cpuPercent, isNull);
      expect(decoded.isMuted, isTrue);
    });

    test('SystemStatus round trips with every optional field present', () {
      final decoded = _roundTrip(
        codec,
        const SystemStatus(
          volume: 0.5,
          isMuted: false,
          uptimeSeconds: 60,
          batteryPercent: 88,
          isCharging: true,
          cpuPercent: 12.5,
          memoryPercent: 64,
        ),
      );
      expect(decoded.batteryPercent, 88);
      expect(decoded.isCharging, isTrue);
      expect(decoded.cpuPercent, closeTo(12.5, 0.001));
    });

    test('DeviceInfoMessage round trips a full identity', () {
      const id = DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123');
      final decoded = _roundTrip(
        codec,
        const DeviceInfoMessage(
          DeviceInfo(
            id: id,
            name: "Ahmed's MacBook Pro",
            platform: PlatformKind.macos,
            role: PeerRole.server,
            appVersion: '0.1.0',
            model: 'Mac16,7',
          ),
        ),
      );
      expect(decoded.info.id, id);
      expect(decoded.info.name, "Ahmed's MacBook Pro");
      expect(decoded.info.platform, PlatformKind.macos);
      expect(decoded.info.role, PeerRole.server);
      expect(decoded.info.model, 'Mac16,7');
    });

    test('ClientHello round trips key material and capabilities', () {
      final decoded = _roundTrip(
        codec,
        ClientHello(
          minVersion: 1,
          maxVersion: 1,
          ephemeralPublicKey: Uint8List.fromList(List<int>.filled(32, 1)),
          clientNonce: Uint8List.fromList(List<int>.filled(32, 2)),
          capabilities: const Capabilities(
            Capabilities.mouse | Capabilities.keyboard,
          ),
          knownServerId: const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123'),
        ),
      );
      expect(decoded.ephemeralPublicKey, hasLength(32));
      expect(decoded.capabilities.has(Capabilities.mouse), isTrue);
      expect(decoded.capabilities.has(Capabilities.screenCapture), isFalse);
      expect(decoded.knownServerId?.value, 'ABCDEFGHJKMNPQRSTVWXYZ0123');
    });

    test('ErrorMessage round trips its code', () {
      final decoded = _roundTrip(
        codec,
        const ErrorMessage(
          code: ProtocolErrorCode.rateLimited,
          detail: 'slow down',
          retryAfterMillis: 5000,
        ),
      );
      expect(decoded.code, ProtocolErrorCode.rateLimited);
      expect(decoded.retryAfterMillis, 5000);
    });

    test('Ping and Pong carry the timestamps RTT is computed from', () {
      final ping = _roundTrip(codec, const Ping(senderMicros: 999));
      expect(ping.senderMicros, 999);

      final pong = _roundTrip(
        codec,
        const Pong(originalSenderMicros: 999, responderMicros: 1500),
      );
      expect(pong.originalSenderMicros, 999);
    });

    test('ScreenStreamStart round trips through codec', () {
      final decoded = _roundTrip(
        codec,
        const ScreenStreamStart(
          monitorId: 1,
          codec: ScreenCodec.h264,
          targetFps: 60,
          targetBitrateKbps: 4000,
          maxWidth: 1920,
          maxHeight: 1080,
        ),
      );
      expect(decoded.monitorId, 1);
      expect(decoded.codec, ScreenCodec.h264);
      expect(decoded.targetFps, 60);
    });

    test('ScreenStreamStop round trips through codec', () {
      final decoded = _roundTrip(
        codec,
        const ScreenStreamStop(reason: ScreenStopReason.decoderError),
      );
      expect(decoded.reason, ScreenStopReason.decoderError);
    });

    test('ScreenFrame round trips through codec', () {
      final decoded = _roundTrip(
        codec,
        ScreenFrame(
          sequence: 1,
          ptsMicros: 100,
          isKeyframe: true,
          width: 1280,
          height: 720,
          data: Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
      );
      expect(decoded.sequence, 1);
      expect(decoded.isKeyframe, isTrue);
      expect(decoded.data, <int>[1, 2, 3, 4]);
    });

    test('ScreenConfigure round trips through codec', () {
      final decoded = _roundTrip(
        codec,
        const ScreenConfigure(targetBitrateKbps: 3500),
      );
      expect(decoded.targetBitrateKbps, 3500);
      expect(decoded.targetFps, isNull);
    });
  });

  group('forward compatibility', () {
    test('a message type from a future version decodes as unknown', () {
      final frame = Frame(
        type: MessageType.unknown,
        sequence: 0,
        timestampMicros: 0,
        payload: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final decoded = codec.decode(frame);
      expect(decoded, isA<UnknownMessage>());
      expect((decoded as UnknownMessage).bytes, <int>[1, 2, 3]);
    });

    test('trailing bytes from a newer peer are ignored, not fatal', () {
      // Simulates a future build appending a field to MouseMove.
      final writer = ByteWriter()
        ..writeVarInt(10)
        ..writeVarInt(20)
        ..writeBytes(<int>[0xAA, 0xBB, 0xCC]);

      final frame = Frame(
        type: MessageType.mouseMove,
        sequence: 0,
        timestampMicros: 0,
        payload: writer.toBytes(),
      );

      final decoded = codec.decode(frame) as MouseMove;
      expect(decoded.deltaX, 10);
      expect(decoded.deltaY, 20);
    });
  });

  group('PermissionTier', () {
    test('read-only cannot send input or sync the clipboard', () {
      const tier = PermissionTier.readOnly;
      expect(tier.allows(MessageType.mouseMove), isFalse);
      expect(tier.allows(MessageType.keyEvent), isFalse);
      expect(tier.allows(MessageType.clipboardUpdate), isFalse);
      expect(tier.allows(MessageType.mediaState), isTrue);
    });

    test('standard covers input and clipboard but not power', () {
      const tier = PermissionTier.standard;
      expect(tier.allows(MessageType.mouseMove), isTrue);
      expect(tier.allows(MessageType.clipboardUpdate), isTrue);
      expect(tier.allows(MessageType.fileChunk), isFalse);
      expect(tier.allows(MessageType.powerCommand), isFalse);
    });

    test('extended adds files and launching but still not power', () {
      const tier = PermissionTier.extended;
      expect(tier.allows(MessageType.fileChunk), isTrue);
      expect(tier.allows(MessageType.launchApplication), isTrue);
      expect(tier.allows(MessageType.powerCommand), isFalse);
    });

    test('admin allows everything including power', () {
      const tier = PermissionTier.admin;
      expect(tier.allows(MessageType.powerCommand), isTrue);
      expect(tier.allows(MessageType.runCommand), isTrue);
    });
  });

  group('DeviceId', () {
    test('derives deterministically from a digest', () {
      final digest = List<int>.generate(32, (i) => i);
      final a = DeviceId.fromDigest(digest);
      final b = DeviceId.fromDigest(digest);
      expect(a, b);
      expect(a.value, hasLength(DeviceId.length));
    });

    test('different digests produce different ids', () {
      final a = DeviceId.fromDigest(List<int>.generate(32, (i) => i));
      final b = DeviceId.fromDigest(List<int>.generate(32, (i) => i + 1));
      expect(a, isNot(b));
    });

    test('parsing folds Crockford aliases and separators', () {
      const canonical = 'ABCDEFGHJKMNPQRSTVWXYZ0123';
      expect(DeviceId.tryParse(canonical)?.value, canonical);
      expect(DeviceId.tryParse(canonical.toLowerCase())?.value, canonical);

      // I, L, and O are typing hazards; Crockford folds them to 1, 1, and 0.
      expect(DeviceId.tryParse('IBCDEFGHJKMNPQRSTVWXYZ0123')?.value,
          startsWith('1BCDE'));
      expect(DeviceId.tryParse('OBCDEFGHJKMNPQRSTVWXYZ0123')?.value,
          startsWith('0BCDE'));
    });

    test('rejects wrong lengths and invalid characters', () {
      expect(DeviceId.tryParse('TOOSHORT'), isNull);
      expect(DeviceId.tryParse('U' * 26), isNull);
    });
  });
}
