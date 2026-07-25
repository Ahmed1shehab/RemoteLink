/// RemoteLink binary wire protocol.
///
/// This package is pure Dart with no socket, no keys, and no platform calls, so
/// every byte of the format can be tested in isolation. It defines four things:
///
/// * [ByteWriter] / [ByteReader] — bounds-checked big-endian primitives.
/// * [Frame] — the fixed 20-byte header plus opaque payload.
/// * [MessageType] and the [Message] hierarchy — typed payloads.
/// * [MessageCodec] — sequencing, compression, and type dispatch.
///
/// The full wire specification lives in `docs/PROTOCOL.md`.
library;

export 'src/bytes.dart';
export 'src/codec.dart';
export 'src/crc32c.dart';
export 'src/frame.dart';
export 'src/message_type.dart';
export 'src/messages/clipboard.dart';
export 'src/messages/control.dart';
export 'src/messages/input.dart';
export 'src/messages/keyboard.dart';
export 'src/messages/media.dart';
export 'src/messages/message.dart';
export 'src/messages/pairing.dart';
export 'src/messages/system.dart';
