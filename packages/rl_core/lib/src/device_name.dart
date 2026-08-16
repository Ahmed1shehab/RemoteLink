import 'package:characters/characters.dart';

import 'device_name_tables.dart';

/// Validates and normalises a peer or device display name.
///
/// Returns the trimmed, NFC-normalised string if valid, or `null` if rejected.
///
/// Rules:
/// - Strings containing control characters (C0/C1, DEL) or ANSI escape sequences are rejected.
/// - Strings containing line breaks (`\n`, `\r`, `\u0085`, `\u2028`, `\u2029`) are rejected.
/// - Strings containing zero-width or formatting marks (`\u200B`, `\uFEFF`, `\u2800`, `\u00AD`, etc.) are rejected.
/// - Leading and trailing whitespace is trimmed.
/// - Empty strings or strings that are empty after trimming are rejected.
/// - Strings containing only whitespace or zero-width / invisible characters are rejected.
/// - Strings are normalised to Unicode NFC.
/// - Strings exceeding 64 user-perceived characters (grapheme clusters) after normalisation are rejected.
/// - Invalid names are rejected (returns `null`), never silently truncated or substituted.
String? sanitiseDeviceName(String? raw) {
  if (raw == null) return null;

  // 1. Reject control characters, DEL, C1 controls, and line breaks in the raw input.
  //    This also rejects all ANSI escape sequences because every ANSI escape
  //    starts with ESC (0x1B) or CSI (0x9B).
  for (final rune in raw.runes) {
    if ((rune >= 0x00 && rune <= 0x1F) ||
        (rune >= 0x7F && rune <= 0x9F) ||
        rune == 0x2028 ||
        rune == 0x2029) {
      return null;
    }
  }

  // 2. Reject dangerous invisible, format, or zero-width characters in the raw input.
  for (final rune in raw.runes) {
    if (rune == 0x200B || // Zero-width space
        rune == 0xFEFF || // BOM / Zero-width no-break space
        rune == 0x2800 || // Braille pattern blank
        rune == 0x00AD || // Soft hyphen
        rune == 0x2060 || // Word joiner
        (rune >= 0x2061 && rune <= 0x2064) || // Invisible operators
        (rune >= 0x202A && rune <= 0x202E) || // Bidi formatting
        (rune >= 0x2066 && rune <= 0x2069) || // Bidi isolates
        (rune >= 0xE0000 && rune <= 0xE007F)) {
      // Unicode Tag characters
      return null;
    }
  }

  // 3. Trim leading and trailing whitespace.
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // 4. Reject strings that have no visible characters (e.g. only whitespace,
  //    standalone zero-width joiners/non-joiners, or bidi marks).
  if (!_hasVisibleCharacters(trimmed)) {
    return null;
  }

  // 5. Normalise to Unicode NFC.
  final normalised = normalizeNfc(trimmed);

  // 6. Cap at 64 user-perceived characters (grapheme clusters).
  if (normalised.characters.length > 64) {
    return null;
  }

  return normalised;
}

/// Checks if [text] has at least one visible graphical character.
bool _hasVisibleCharacters(String text) {
  for (final rune in text.runes) {
    if (_isInvisibleOrWhitespaceRune(rune)) continue;
    return true;
  }
  return false;
}

/// Returns true if [rune] is whitespace, formatting, or invisible.
bool _isInvisibleOrWhitespaceRune(int rune) {
  if (rune == 0x20 || (rune >= 0x09 && rune <= 0x0D)) return true;
  if (rune == 0x00A0 || // Non-breaking space
      rune == 0x1680 || // Ogham space mark
      (rune >= 0x2000 && rune <= 0x200A) || // En quad to Hair space
      rune == 0x202F || // Narrow no-break space
      rune == 0x205F || // Medium mathematical space
      rune == 0x3000 || // Ideographic space
      rune == 0x2800 || // Braille blank
      rune == 0x200B || // Zero-width space
      rune == 0x200C || // ZWNJ
      rune == 0x200D || // ZWJ
      rune == 0x200E || // LRM
      rune == 0x200F || // RLM
      rune == 0x00AD || // Soft hyphen
      rune == 0xFEFF || // BOM
      (rune >= 0x202A && rune <= 0x202E) || // Bidi formatting
      (rune >= 0x2060 && rune <= 0x2069) || // Invisible characters
      (rune >= 0xE0000 && rune <= 0xE007F)) {
    // Tag characters
    return true;
  }
  return false;
}
