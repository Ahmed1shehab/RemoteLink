import 'dart:typed_data';

/// CRC-32C (Castagnoli, reversed polynomial `0x82F63B78`).
///
/// Chosen over CRC-32 (IEEE) for two reasons: it has better error-detection
/// properties for the short frames RemoteLink sends, and it is the variant with
/// a hardware instruction (`SSE4.2 CRC32`, ARMv8 `CRC32CX`) that a future
/// native fast path can use without changing the wire format.
///
/// The checksum is a *corruption* check for the pre-encryption debug path and
/// for the plaintext discovery beacon. It is not a security control: once the
/// AEAD is established, Poly1305 provides authentication and the checksum flag
/// is left off to save four bytes per frame.
abstract final class Crc32c {
  static const int _polynomial = 0x82F63B78;

  /// Lazily built 256-entry lookup table. One byte per step is the right
  /// trade-off here — a slicing-by-8 table would be 8 KiB for frames that are
  /// typically under 32 bytes.
  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final table = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var crc = i;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ _polynomial : crc >> 1;
      }
      table[i] = crc;
    }
    return table;
  }

  /// Computes the checksum of [data], optionally over the window
  /// `[start, end)`.
  static int compute(Uint8List data, {int start = 0, int? end}) =>
      update(0xFFFFFFFF, data, start: start, end: end) ^ 0xFFFFFFFF;

  /// Incremental step. Seed with `0xFFFFFFFF` and finalise by XOR-ing with
  /// `0xFFFFFFFF`. Used when checksumming a header and body separately without
  /// concatenating them.
  static int update(int crc, Uint8List data, {int start = 0, int? end}) {
    final limit = end ?? data.length;
    var value = crc;
    for (var i = start; i < limit; i++) {
      value = _table[(value ^ data[i]) & 0xFF] ^ (value >> 8);
    }
    return value;
  }
}
