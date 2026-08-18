import 'dart:typed_data';

import 'png.dart';
import 'raster.dart';

/// Packs several sizes into one Windows `.ico`.
///
/// Windows picks the entry closest to the size it needs, so the taskbar, the
/// title bar and the Alt-Tab card each get artwork drawn for them rather than
/// one bitmap scaled three ways.
///
/// Each entry holds a PNG rather than the older DIB layout. Windows has read
/// PNG-in-ICO since Vista, and it is what makes a 256-pixel entry affordable —
/// as an uncompressed DIB the same entry is a quarter of a megabyte.
Uint8List encodeIco(List<Raster> sizes) {
  if (sizes.isEmpty) {
    throw ArgumentError('an .ico needs at least one image');
  }
  for (final image in sizes) {
    if (image.width != image.height) {
      throw ArgumentError('icon entries must be square, '
          'got ${image.width}x${image.height}');
    }
    if (image.width > 256) {
      throw ArgumentError('an .ico entry cannot exceed 256 pixels, '
          'got ${image.width}');
    }
  }

  final encoded = <Uint8List>[for (final image in sizes) encodePng(image)];
  final directory = ByteData(6 + 16 * sizes.length)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, sizes.length, Endian.little);

  var offset = directory.lengthInBytes;
  for (var i = 0; i < sizes.length; i++) {
    final entry = 6 + 16 * i;
    // 256 is written as zero: the field is one byte, and zero is the documented
    // escape for the largest size an icon may be.
    final side = sizes[i].width == 256 ? 0 : sizes[i].width;
    directory
      ..setUint8(entry, side)
      ..setUint8(entry + 1, side)
      ..setUint8(entry + 2, 0)
      ..setUint8(entry + 3, 0)
      ..setUint16(entry + 4, 1, Endian.little)
      ..setUint16(entry + 6, 32, Endian.little)
      ..setUint32(entry + 8, encoded[i].length, Endian.little)
      ..setUint32(entry + 12, offset, Endian.little);
    offset += encoded[i].length;
  }

  final out = BytesBuilder(copy: false)..add(directory.buffer.asUint8List());
  for (final png in encoded) {
    out.add(png);
  }
  return out.takeBytes();
}
