import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';

import 'bytes.dart';
import 'frame.dart';
import 'message_type.dart';
import 'messages/clipboard.dart';
import 'messages/control.dart';
import 'messages/file_transfer.dart';
import 'messages/input.dart';
import 'messages/keyboard.dart';
import 'messages/media.dart';
import 'messages/message.dart';
import 'messages/pairing.dart';
import 'messages/screen.dart';
import 'messages/system.dart';

/// Payloads at or above this size are worth compressing.
///
/// Below roughly 512 bytes DEFLATE's header plus the CPU cost outweighs any
/// saving, and the input hot path — where every microsecond is visible as
/// cursor lag — is entirely below this threshold. So the fast path never
/// compresses, without needing a special case.
const int kCompressionThreshold = 512;

/// Ratio a compressed payload must beat to be used.
///
/// Already-compressed content (PNG clipboard images, encoded video frames)
/// often grows slightly under DEFLATE. Falling back to the raw bytes when the
/// saving is under 10% avoids paying CPU to make packets bigger.
const double kCompressionMinRatio = 0.9;

/// Turns [Message] objects into [Frame]s and back.
///
/// The codec owns three concerns that would otherwise be smeared across the
/// session layer: sequence numbering, optional compression, and dispatching a
/// wire code to the right decoder. It holds no socket and no keys, which keeps
/// it fully unit-testable without any I/O.
final class MessageCodec {
  MessageCodec({required Clock clock, bool compressionEnabled = true})
      : _clock = clock,
        _compressionEnabled = compressionEnabled;

  final Clock _clock;
  final bool _compressionEnabled;

  static final ZLibCodec _deflate = ZLibCodec(raw: true, level: 6);

  /// Reused across every encode on a connection. Safe because encoding is
  /// synchronous and single-isolate: the buffer is written and copied out
  /// before control returns to the event loop.
  final ByteWriter _payloadWriter = ByteWriter(initialCapacity: 1024);

  int _sequence = 0;

  /// Sequence number the next encoded frame will carry.
  int get nextSequence => _sequence;

  /// Wraps [message] in a frame, compressing and requesting an ack as needed.
  ///
  /// [requireAck] should be reserved for messages whose loss the application
  /// must notice. Every acked message costs a round trip of bookkeeping, and
  /// TCP already guarantees delivery — acks here exist for *application*-level
  /// confirmation (a file chunk was written to disk), not for reliability.
  Frame encode(Message message, {bool requireAck = false, bool? compress}) {
    _payloadWriter.reset();
    message.writeTo(_payloadWriter);
    var payload = _payloadWriter.toBytes();

    var flags = FrameFlags.none;
    final shouldCompress = compress ??
        (_compressionEnabled &&
            payload.length >= kCompressionThreshold &&
            !message.type.isLossy);

    if (shouldCompress) {
      final compressed = Uint8List.fromList(_deflate.encode(payload));
      if (compressed.length < payload.length * kCompressionMinRatio) {
        payload = compressed;
        flags = flags.withFlag(FrameFlags.compressed);
      }
    }

    if (requireAck) flags = flags.withFlag(FrameFlags.requiresAck);

    final frame = Frame(
      type: message.type,
      sequence: _sequence,
      timestampMicros: _clock.monotonicMicros(),
      flags: flags,
      payload: payload,
    );
    _sequence = (_sequence + 1) & 0xFFFFFFFF;
    return frame;
  }

  /// Decodes a frame's payload into a typed message.
  ///
  /// Unknown wire codes yield [UnknownMessage] rather than throwing, which is
  /// what makes adding a message type a non-breaking change. Malformed payloads
  /// for a *known* type do throw [ProtocolError] — that is a real violation and
  /// the session must close, because a truncated payload means the stream may
  /// be desynchronised.
  Message decode(Frame frame) {
    final payload =
        frame.flags.isCompressed ? _decompress(frame.payload) : frame.payload;
    final reader = ByteReader(payload);

    // Bytes left over after a decoder finishes are not an error: a newer peer
    // may have appended fields to a message this build already knows. Ignoring
    // the tail is exactly the forward-compatibility guarantee the wire format
    // makes, so no length check happens here.
    return _decodeBody(frame.type, reader, payload);
  }

  Message _decodeBody(MessageType type, ByteReader reader, Uint8List raw) =>
      switch (type) {
        // Session control.
        MessageType.clientHello => ClientHello.readFrom(reader),
        MessageType.serverHello => ServerHello.readFrom(reader),
        MessageType.handshakeFinish => HandshakeFinish.readFrom(reader),
        MessageType.ping => Ping.readFrom(reader),
        MessageType.pong => Pong.readFrom(reader),
        MessageType.ack => Ack.readFrom(reader),
        MessageType.error => ErrorMessage.readFrom(reader),
        MessageType.close => CloseMessage.readFrom(reader),
        MessageType.resumptionTicket => ResumptionTicket.readFrom(reader),
        MessageType.resumeSession => ResumeSession.readFrom(reader),

        // Pairing.
        MessageType.pairRequest => PairRequest.readFrom(reader),
        MessageType.pairChallenge => PairChallenge.readFrom(reader),
        MessageType.pairConfirm => PairConfirm.readFrom(reader),
        MessageType.pairComplete => PairComplete.readFrom(reader),
        MessageType.pairReject => PairReject.readFrom(reader),
        MessageType.unpair => Unpair.readFrom(reader),

        // Pointer input.
        MessageType.mouseMove => MouseMove.readFrom(reader),
        MessageType.mouseMoveAbsolute => MouseMoveAbsolute.readFrom(reader),
        MessageType.mouseButton => MouseButtonEvent.readFrom(reader),
        MessageType.mouseScroll => MouseScroll.readFrom(reader),
        MessageType.gestureZoom => GestureZoom.readFrom(reader),
        MessageType.gestureRotate => GestureRotate.readFrom(reader),
        MessageType.gestureSwipe => GestureSwipe.readFrom(reader),
        MessageType.penInput => PenInput.readFrom(reader),

        // Keyboard input.
        MessageType.keyEvent => KeyEvent.readFrom(reader),
        MessageType.textInput => TextInput.readFrom(reader),
        MessageType.namedShortcut => NamedShortcutMessage.readFrom(reader),
        MessageType.modifierState => ModifierStateMessage.readFrom(reader),

        // Clipboard.
        MessageType.clipboardUpdate => ClipboardUpdate.readFrom(reader),
        MessageType.clipboardRequest => ClipboardRequest.readFrom(reader),
        MessageType.clipboardSyncToggle => ClipboardSyncToggle.readFrom(reader),

        // Media.
        MessageType.mediaCommand => MediaCommand.readFrom(reader),
        MessageType.volumeCommand => VolumeCommand.readFrom(reader),
        MessageType.mediaState => MediaState.readFrom(reader),
        MessageType.brightnessCommand => BrightnessCommand.readFrom(reader),

        // File transfer.
        MessageType.fileOffer => FileOffer.readFrom(reader),
        MessageType.fileAccept => FileAccept.readFrom(reader),
        MessageType.fileChunk => FileChunk.readFrom(reader),
        MessageType.fileComplete => FileComplete.readFrom(reader),
        MessageType.fileAbort => FileAbort.readFrom(reader),

        // System.
        MessageType.powerCommand => PowerCommand.readFrom(reader),
        MessageType.launchApplication => LaunchApplication.readFrom(reader),
        MessageType.openUrl => OpenUrl.readFrom(reader),
        MessageType.runCommand => RunCommand.readFrom(reader),
        MessageType.systemStatus => SystemStatus.readFrom(reader),

        // Screen.
        MessageType.screenTopology => ScreenTopology.readFrom(reader),

        // Device management.
        MessageType.deviceInfo => DeviceInfoMessage.readFrom(reader),
        MessageType.deviceRename => DeviceRename.readFrom(reader),
        MessageType.permissionGrant => PermissionGrant.readFrom(reader),
        MessageType.permissionRequest => PermissionRequest.readFrom(reader),

        // Declared in the wire format but implemented in a later milestone.
        // They decode as opaque so a newer peer can send them without breaking
        // this build, and so a capture still shows the correct type name.
        MessageType.screenStreamStart ||
        MessageType.screenStreamStop ||
        MessageType.screenFrame ||
        MessageType.screenConfigure ||
        MessageType.slideCommand ||
        MessageType.laserPointer ||
        MessageType.presentationBlank ||
        MessageType.gamepadState ||
        MessageType.motionState =>
          UnknownMessage(type.code, raw),
        MessageType.unknown => UnknownMessage(type.code, raw),
      };

  Uint8List _decompress(Uint8List payload) {
    try {
      return Uint8List.fromList(_deflate.decode(payload));
    } on Object catch (e) {
      throw ProtocolError(
        'decompress_failed',
        'payload declared compressed but DEFLATE rejected it',
        cause: e,
      );
    }
  }

  /// Resets sequence numbering. Called when a session is re-established, since
  /// the peer's expectations restart with it.
  void resetSequence() => _sequence = 0;
}
