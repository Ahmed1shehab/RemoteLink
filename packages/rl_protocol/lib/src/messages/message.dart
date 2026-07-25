import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../bytes.dart';
import '../message_type.dart';

/// Base class for every decoded protocol payload.
///
/// A [Message] is the *body* of a [Frame]; the header (sequence, timestamp,
/// flags) lives on the frame. Splitting them means the session layer can route
/// and acknowledge a frame without paying to decode its payload — which matters
/// for screen frames, where the payload is a megabyte of already-encoded video
/// that only the renderer needs to look at.
@immutable
sealed class Message {
  const Message();

  /// Wire code this message serialises under.
  MessageType get type;

  /// Appends this message's payload encoding to [writer].
  void writeTo(ByteWriter writer);

  /// Convenience encoder. Prefer [writeTo] with a pooled writer on hot paths.
  Uint8List encodePayload() {
    final writer = ByteWriter(initialCapacity: 64);
    writeTo(writer);
    return writer.toBytes();
  }
}

/// A payload whose wire code this build does not recognise.
///
/// Produced instead of throwing so that forward compatibility is the default:
/// a v1 client receiving a v1.1 message logs and ignores it rather than
/// dropping the connection.
@immutable
final class UnknownMessage extends Message {
  const UnknownMessage(this.code, this.bytes);

  /// The unrecognised wire code, retained for diagnostics.
  final int code;

  final Uint8List bytes;

  @override
  MessageType get type => MessageType.unknown;

  @override
  void writeTo(ByteWriter writer) => writer.writeBytes(bytes);

  @override
  String toString() =>
      'UnknownMessage(0x${code.toRadixString(16)}, ${bytes.length}B)';
}
