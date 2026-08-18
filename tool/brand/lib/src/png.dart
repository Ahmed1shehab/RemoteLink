import 'dart:io';
import 'dart:typed_data';

import 'raster.dart';

/// The eight bytes every PNG starts with.
const List<int> _signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

/// Reads a PNG into a plain RGBA raster.
///
/// ## Why this exists rather than a package
///
/// Nothing in this repository draws pictures at runtime, so a dependency on an
/// imaging library would be carried by every `pub get` in order to serve a
/// script that runs when the logo changes — which is roughly never. The subset
/// actually needed is small: one artwork file, 8 bits a channel, not
/// interlaced. Everything outside that subset throws instead of guessing, so a
/// file this cannot read fails loudly at generation time rather than producing
/// an icon nobody looks at closely until it ships.
Raster decodePng(Uint8List bytes) {
  if (bytes.length < 8) {
    throw const FormatException('not a PNG: file is shorter than the header');
  }
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _signature[i]) {
      throw const FormatException('not a PNG: signature does not match');
    }
  }

  final view = ByteData.sublistView(bytes);
  var offset = 8;

  int? width;
  int? height;
  var colourType = -1;
  var sawEnd = false;
  final compressed = BytesBuilder(copy: false);
  Uint8List? palette;
  Uint8List? paletteAlpha;

  while (offset + 8 <= bytes.length) {
    final length = view.getUint32(offset);
    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    final start = offset + 8;
    final end = start + length;
    if (end + 4 > bytes.length) {
      throw const FormatException('truncated PNG: a chunk runs past the end');
    }

    switch (type) {
      case 'IHDR':
        width = view.getUint32(start);
        height = view.getUint32(start + 4);
        final depth = bytes[start + 8];
        colourType = bytes[start + 9];
        final interlace = bytes[start + 12];
        if (depth != 8) {
          throw FormatException('only 8-bit PNGs are supported, got $depth');
        }
        if (interlace != 0) {
          throw const FormatException('interlaced PNGs are not supported');
        }
      case 'PLTE':
        palette = Uint8List.sublistView(bytes, start, end);
      case 'tRNS':
        paletteAlpha = Uint8List.sublistView(bytes, start, end);
      case 'IDAT':
        // Split across chunks at the encoder's whim, and the compressed stream
        // continues across the boundary — so they are joined before inflating
        // rather than inflated one at a time.
        compressed.add(Uint8List.sublistView(bytes, start, end));
      case 'IEND':
        sawEnd = true;
        offset = bytes.length;
        continue;
      default:
      // Unknown chunks are skipped by design. Editors write colour profiles
      // and private metadata, and none of it changes the pixels.
    }

    offset = end + 4;
  }

  if (width == null || height == null) {
    throw const FormatException('PNG has no IHDR');
  }
  // A file that simply stops has chunks that all parse and pixels that are
  // missing, and it decodes into a picture with a blank bottom half rather than
  // an error. IEND is how a PNG says it is complete.
  if (!sawEnd) {
    throw const FormatException('truncated PNG: the file ends before IEND');
  }

  final channels = switch (colourType) {
    0 => 1,
    2 => 3,
    3 => 1,
    4 => 2,
    6 => 4,
    _ => throw FormatException('unsupported PNG colour type $colourType'),
  };

  final raw = Uint8List.fromList(
    ZLibCodec().decode(compressed.takeBytes()),
  );
  final scanlines = _unfilter(raw, width, height, channels);

  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final source = i * channels;
    final target = i * 4;
    switch (colourType) {
      case 0:
        final grey = scanlines[source];
        pixels[target] = grey;
        pixels[target + 1] = grey;
        pixels[target + 2] = grey;
        pixels[target + 3] = 255;
      case 2:
        pixels[target] = scanlines[source];
        pixels[target + 1] = scanlines[source + 1];
        pixels[target + 2] = scanlines[source + 2];
        pixels[target + 3] = 255;
      case 3:
        if (palette == null) {
          throw const FormatException('indexed PNG without a palette');
        }
        final index = scanlines[source];
        pixels[target] = palette[index * 3];
        pixels[target + 1] = palette[index * 3 + 1];
        pixels[target + 2] = palette[index * 3 + 2];
        pixels[target + 3] =
            index < (paletteAlpha?.length ?? 0) ? paletteAlpha![index] : 255;
      case 4:
        final grey = scanlines[source];
        pixels[target] = grey;
        pixels[target + 1] = grey;
        pixels[target + 2] = grey;
        pixels[target + 3] = scanlines[source + 1];
      case 6:
        pixels[target] = scanlines[source];
        pixels[target + 1] = scanlines[source + 1];
        pixels[target + 2] = scanlines[source + 2];
        pixels[target + 3] = scanlines[source + 3];
    }
  }

  return Raster(width: width, height: height, pixels: pixels);
}

/// Undoes the per-scanline filter each row carries in its first byte.
Uint8List _unfilter(Uint8List raw, int width, int height, int channels) {
  final stride = width * channels;
  final out = Uint8List(stride * height);
  if (raw.length < (stride + 1) * height) {
    throw const FormatException('PNG pixel data is shorter than the header '
        'says it should be');
  }

  for (var y = 0; y < height; y++) {
    final filter = raw[y * (stride + 1)];
    final source = y * (stride + 1) + 1;
    final target = y * stride;
    final above = target - stride;

    for (var x = 0; x < stride; x++) {
      final value = raw[source + x];
      final left = x >= channels ? out[target + x - channels] : 0;
      final up = y > 0 ? out[above + x] : 0;
      final upLeft = (y > 0 && x >= channels) ? out[above + x - channels] : 0;

      out[target + x] = switch (filter) {
        0 => value,
        1 => value + left,
        2 => value + up,
        3 => value + ((left + up) >> 1),
        4 => value + _paeth(left, up, upLeft),
        _ => throw FormatException('unknown PNG row filter $filter'),
      };
    }
  }
  return out;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

/// Writes an 8-bit RGBA PNG.
///
/// Every row is written with filter 0. Choosing filters adaptively would shrink
/// the file, but these are icons of at most a megabyte generated once, and a
/// filter heuristic is a place for a bug to hide where nothing would catch it.
Uint8List encodePng(Raster image) {
  final stride = image.width * 4;
  final raw = Uint8List((stride + 1) * image.height);
  for (var y = 0; y < image.height; y++) {
    raw[y * (stride + 1)] = 0;
    raw.setRange(
      y * (stride + 1) + 1,
      y * (stride + 1) + 1 + stride,
      image.pixels,
      y * stride,
    );
  }

  final header = ByteData(13)
    ..setUint32(0, image.width)
    ..setUint32(4, image.height)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);

  final out = BytesBuilder(copy: false)
    ..add(_signature)
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(
      _chunk(
        'IDAT',
        Uint8List.fromList(ZLibCodec(level: 9).encode(raw)),
      ),
    )
    ..add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final out = Uint8List(12 + data.length);
  final view = ByteData.sublistView(out)..setUint32(0, data.length);
  for (var i = 0; i < 4; i++) {
    out[4 + i] = type.codeUnitAt(i);
  }
  out.setRange(8, 8 + data.length, data);
  view.setUint32(
      8 + data.length, crc32(Uint8List.sublistView(out, 4, 8 + data.length)));
  return out;
}

final Uint32List _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[i] = c;
  }
  return table;
}

/// The CRC-32 every PNG chunk ends with.
///
/// Public because the tests need it directly: this decoder ignores checksums,
/// so a chunk written with a wrong one round-trips here perfectly and is
/// rejected by every real decoder — exactly the bug that would ship unnoticed.
int crc32(Uint8List bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
