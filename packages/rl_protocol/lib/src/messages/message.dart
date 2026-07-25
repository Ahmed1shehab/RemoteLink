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
/// `base`, not `sealed`.
///
/// `sealed` was the first choice and it was wrong. Sealing requires every
/// subtype to live in the *same library*, and the forty-odd message classes are
/// deliberately split across eight files by subsystem. Keeping `sealed` would
/// have meant converting all of them into `part` files of one library — which
/// strips their imports, makes each file unreadable on its own, and is a real
/// cost for navigating the largest package here.
///
/// What sealing would have bought is exhaustiveness checking on switches over
/// `Message`. That turns out to be worth nothing here: both such switches — the
/// session's control-message router and the desktop's command dispatcher —
/// legitimately handle a subset and end in `default`, which defeats
/// exhaustiveness anyway. The exhaustiveness that actually protects this
/// codebase is on `MessageType`, an enum, in `MessageCodec._decodeBody`; adding
/// a wire code there is a compile error until it is given a decoder. That is
/// the check that matters and it is unaffected.
///
/// `base` keeps the useful half of the guarantee: subtypes may extend but not
/// `implement`, so nothing outside can fake a `Message` that satisfies the type
/// without inheriting real `writeTo` behaviour.
@immutable
abstract base class Message {
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
