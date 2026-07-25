import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';

/// What kind of content a clipboard payload holds.
enum ClipboardContentType {
  /// UTF-8 plain text.
  text(1),

  /// A single URL. Split from [text] so the phone can offer "open" affordances
  /// and the desktop can populate the URL pasteboard flavour on macOS.
  url(2),

  /// PNG image bytes. PNG rather than the source format because it is lossless
  /// and universally accepted by both pasteboards.
  imagePng(3),

  /// HTML fragment, carried alongside a plain-text fallback so that pasting
  /// into a rich editor preserves formatting and pasting into a terminal does
  /// not produce tag soup.
  html(4),

  /// Rich Text Format.
  rtf(5),

  /// A list of file paths. The paths are meaningless to the receiver on their
  /// own; they are an offer that the file-transfer subsystem fulfils.
  fileList(6);

  const ClipboardContentType(this.wireValue);

  final int wireValue;

  static ClipboardContentType fromWire(int value) => values.firstWhere(
        (contentType) => contentType.wireValue == value,
        orElse: () => ClipboardContentType.text,
      );
}

/// One representation of clipboard content.
///
/// A single clipboard change can carry several flavours (HTML plus a plain-text
/// fallback, say). Both pasteboards are multi-flavour, so preserving that
/// structure end to end is what makes a copy from a browser paste correctly
/// into both Word and Notepad.
@immutable
final class ClipboardItem {
  const ClipboardItem({required this.contentType, required this.data});

  /// Builds a UTF-8 text item.
  factory ClipboardItem.text(String value) => ClipboardItem(
        contentType: ClipboardContentType.text,
        data: Uint8List.fromList(utf8.encode(value)),
      );

  final ClipboardContentType contentType;

  /// Raw bytes in the encoding implied by [contentType]. Textual flavours are
  /// always UTF-8; binary flavours are the format's own bytes.
  final Uint8List data;

  /// Decodes [data] as UTF-8, replacing malformed sequences rather than
  /// throwing — a corrupt clipboard flavour should not break the session.
  String get asText => utf8.decode(data, allowMalformed: true);

  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(contentType.wireValue)
      ..writeLengthPrefixedBytes(data);
  }

  static ClipboardItem readFrom(ByteReader reader) => ClipboardItem(
        contentType: ClipboardContentType.fromWire(reader.readUint8()),
        data: reader.readLengthPrefixedBytes(maxLength: 8 * 1024 * 1024),
      );
}

/// Announces a local clipboard change.
///
/// Sent automatically by the clipboard watcher on both sides — there is no
/// "send clipboard" button anywhere in the product. The design constraint is
/// that copying on one device and pasting on the other must involve exactly the
/// same muscle memory as copying and pasting on one device.
///
/// ## Preventing the echo loop
///
/// Naive bidirectional mirroring oscillates forever: A pushes to B, B's watcher
/// sees a change and pushes back to A, and so on. Two mechanisms stop it.
///
/// [contentHash] lets a receiver drop an update identical to what it already
/// holds — this alone breaks the loop after one round trip.
///
/// [originDeviceId] plus [originSequence] make the suppression exact rather
/// than heuristic: a receiver records the origin when it applies an update, and
/// its own watcher suppresses the change it caused. This matters when the user
/// legitimately re-copies identical text, which a hash-only scheme would
/// silently swallow.
@immutable
final class ClipboardUpdate extends Message {
  const ClipboardUpdate({
    required this.items,
    required this.contentHash,
    required this.originDeviceId,
    required this.originSequence,
    this.isSensitive = false,
  });

  /// Representations, most specific first.
  final List<ClipboardItem> items;

  /// First 16 bytes of SHA-256 over the canonical item encoding.
  ///
  /// Truncated because this is a change-detection fingerprint, not a security
  /// control; 128 bits makes accidental collision impossible in practice.
  final Uint8List contentHash;

  /// Which device originated this content.
  final String originDeviceId;

  /// Monotonic counter within the origin device, breaking ties when both sides
  /// change their clipboard simultaneously. Highest wins; on an exact tie the
  /// lexicographically greater device ID wins, so both sides converge on the
  /// same answer without a round trip.
  final int originSequence;

  /// Set when the source marked the content as a password or otherwise
  /// transient. Receivers do not persist it in clipboard history and expire it
  /// from the pasteboard where the OS supports that.
  final bool isSensitive;

  @override
  MessageType get type => MessageType.clipboardUpdate;

  @override
  void writeTo(ByteWriter writer) {
    writer.writeVarUint(items.length);
    for (final item in items) {
      item.writeTo(writer);
    }
    writer
      ..writeLengthPrefixedBytes(contentHash)
      ..writeString(originDeviceId)
      ..writeVarUint(originSequence)
      ..writeBool(isSensitive);
  }

  static ClipboardUpdate readFrom(ByteReader reader) {
    final count = reader.readVarUint();
    if (count > 16) {
      throw ProtocolError(
        'clipboard_flavour_limit',
        'clipboard update declared $count flavours, cap is 16',
      );
    }
    final items = <ClipboardItem>[
      for (var i = 0; i < count; i++) ClipboardItem.readFrom(reader),
    ];
    return ClipboardUpdate(
      items: items,
      contentHash: reader.readLengthPrefixedBytes(maxLength: 64),
      originDeviceId: reader.readString(maxLength: 64),
      originSequence: reader.readVarUint(),
      isSensitive: reader.readBool(),
    );
  }

  /// The plain-text or URL flavour, if present.
  String? get plainText {
    for (final item in items) {
      if (item.contentType == ClipboardContentType.text ||
          item.contentType == ClipboardContentType.url) {
        return item.asText;
      }
    }
    return null;
  }
}

/// Asks the peer to send its current clipboard.
///
/// Used on connect, so that a phone that was asleep while the user copied on
/// the desktop still has the content available the moment it wakes.
@immutable
final class ClipboardRequest extends Message {
  const ClipboardRequest();

  @override
  MessageType get type => MessageType.clipboardRequest;

  @override
  void writeTo(ByteWriter writer) {}

  static ClipboardRequest readFrom(ByteReader reader) =>
      const ClipboardRequest();
}

/// Enables or disables automatic mirroring for this session.
@immutable
final class ClipboardSyncToggle extends Message {
  const ClipboardSyncToggle({
    required this.enabled,
    required this.allowImages,
    required this.allowFiles,
  });

  final bool enabled;
  final bool allowImages;
  final bool allowFiles;

  @override
  MessageType get type => MessageType.clipboardSyncToggle;

  @override
  void writeTo(ByteWriter writer) {
    writer.writeUint8(
      (enabled ? 1 : 0) | (allowImages ? 2 : 0) | (allowFiles ? 4 : 0),
    );
  }

  static ClipboardSyncToggle readFrom(ByteReader reader) {
    final flags = reader.readUint8();
    return ClipboardSyncToggle(
      enabled: flags & 1 != 0,
      allowImages: flags & 2 != 0,
      allowFiles: flags & 4 != 0,
    );
  }
}
