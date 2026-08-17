import 'dart:typed_data';

import 'package:meta/meta.dart';

/// An IEEE 802 hardware address — six bytes identifying one network adapter.
///
/// Modelled as a type rather than passed around as a `String` because the
/// textual spellings are not interchangeable: Windows writes `AA-BB-CC-DD-EE-FF`
/// and macOS writes `aa:bb:cc:dd:ee:ff` for the same adapter, and a Wake-on-LAN
/// packet built from the wrong spelling wakes nothing while looking correct.
/// Parsing once, at the edge, means everything downstream holds six bytes.
@immutable
final class MacAddress {
  /// Wraps six raw bytes.
  ///
  /// Throws [ArgumentError] on any other length: a MAC is fixed-width, and a
  /// short one would silently produce a magic packet the NIC ignores.
  factory MacAddress(List<int> bytes) {
    if (bytes.length != length) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'a MAC address is exactly $length bytes',
      );
    }
    for (final byte in bytes) {
      if (byte < 0 || byte > 0xff) {
        throw ArgumentError.value(byte, 'bytes', 'not a byte value');
      }
    }
    return MacAddress._(Uint8List.fromList(bytes));
  }

  const MacAddress._(this._bytes);

  final Uint8List _bytes;

  static const int length = 6;

  /// A defensive copy — the internal buffer is never handed out, so a caller
  /// cannot mutate an address another object is holding.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// Parses the spellings that actually turn up in the wild, returning `null`
  /// for anything else.
  ///
  /// Accepted: colon-separated (Unix `ifconfig`), hyphen-separated (Windows
  /// `getmac`), dot-separated in three groups of four (Cisco), and twelve bare
  /// hex digits. Case is irrelevant. Anything else — mixed separators, wrong
  /// group widths, non-hex characters, the wrong number of bytes — is rejected
  /// rather than guessed at, because a MAC recovered from a mis-parse is
  /// indistinguishable from a correct one until the computer fails to wake.
  static MacAddress? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final separators = <String>[
      for (final candidate in const <String>[':', '-', '.'])
        if (trimmed.contains(candidate)) candidate,
    ];
    // Two different separators means the string was assembled by something that
    // did not agree with itself; there is no sensible reading of it.
    if (separators.length > 1) return null;
    final separator = separators.isEmpty ? null : separators.first;

    final groups =
        separator == null ? <String>[trimmed] : trimmed.split(separator);

    // Group width is decided by the shape, and the shape must match the
    // separator: three groups is only ever the dotted Cisco form, so `AA:BB:CC`
    // is a truncated address rather than a Cisco one.
    final int expectedGroupWidth;
    if (groups.length == 1 && separator == null) {
      expectedGroupWidth = length * 2; // bare `AABBCCDDEEFF`
    } else if (groups.length == 3 && separator == '.') {
      expectedGroupWidth = 4; // Cisco `aabb.ccdd.eeff`
    } else if (groups.length == length &&
        (separator == ':' || separator == '-')) {
      expectedGroupWidth = 2; // `AA:BB:CC:DD:EE:FF` or `AA-BB-…`
    } else {
      return null;
    }

    final bytes = Uint8List(length);
    var index = 0;
    for (final group in groups) {
      if (group.length != expectedGroupWidth) return null;
      for (var i = 0; i < group.length; i += 2) {
        final high = _hexDigit(group.codeUnitAt(i));
        final low = _hexDigit(group.codeUnitAt(i + 1));
        if (high == null || low == null) return null;
        bytes[index++] = (high << 4) | low;
      }
    }
    return MacAddress._(bytes);
  }

  /// `int.parse` is not used here: it accepts a leading sign and underscores,
  /// so `+A:BB:…` and `A_:BB:…` would both parse.
  static int? _hexDigit(int codeUnit) {
    if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30; // 0-9
    if (codeUnit >= 0x41 && codeUnit <= 0x46) return codeUnit - 0x37; // A-F
    if (codeUnit >= 0x61 && codeUnit <= 0x66) return codeUnit - 0x57; // a-f
    return null;
  }

  /// The one spelling this codebase stores and sends: uppercase, colons.
  ///
  /// Having a single canonical form is what lets a stored address be compared
  /// with a freshly reported one without normalising at every call site.
  String get canonical => <String>[
        for (final byte in _bytes)
          byte.toRadixString(16).toUpperCase().padLeft(2, '0'),
      ].join(':');

  /// Whether this address can plausibly be the target of a magic packet.
  ///
  /// The all-zero address is what an adapter with no hardware address reports,
  /// the broadcast address is not a host, and an address with the group bit set
  /// is a multicast address — none of them identify a machine to wake, and
  /// advertising one would put a Wake button on the phone that cannot work.
  bool get isWakeable {
    if (_bytes.every((byte) => byte == 0x00)) return false;
    if (_bytes.every((byte) => byte == 0xff)) return false;
    return (_bytes[0] & 0x01) == 0;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MacAddress) return false;
    for (var i = 0; i < length; i++) {
      if (other._bytes[i] != _bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() => canonical;
}
