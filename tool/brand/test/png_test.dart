import 'dart:io';
import 'dart:typed_data';

import 'package:brand/brand.dart';
import 'package:test/test.dart';

/// A raster with a different value in every channel of every pixel.
///
/// Uniform test images are the reason encoder bugs survive: a solid red square
/// round-trips through a decoder that has the channel order backwards, through
/// one that drops the last row, and through one that ignores the width.
Raster _gradient(int width, int height) {
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      pixels[i] = (x * 7 + 3) & 0xFF;
      pixels[i + 1] = (y * 11 + 5) & 0xFF;
      pixels[i + 2] = (x * y + 17) & 0xFF;
      pixels[i + 3] = (200 + x + y) & 0xFF;
    }
  }
  return Raster(width: width, height: height, pixels: pixels);
}

void main() {
  group('png round trip', () {
    test('preserves every pixel of a non-square image', () {
      final original = _gradient(13, 7);
      final decoded = decodePng(encodePng(original));

      expect(decoded.width, 13);
      expect(decoded.height, 7);
      expect(decoded.pixels, original.pixels);
    });

    test('preserves a single pixel', () {
      final decoded = decodePng(
        encodePng(Raster.filled(1, 1, 9, 200, 41, 137)),
      );
      expect(decoded.pixelAt(0, 0), (9, 200, 41, 137));
    });

    test('reads the artwork the icons are generated from', () {
      // The one file this tool exists to read. A decoder that passes its own
      // round trip and cannot read a real export has tested nothing.
      final master = decodePng(
        File('../../assets/brand/logo.png').readAsBytesSync(),
      );
      expect(master.width, greaterThan(512));
      expect(master.width, master.height);
    });
  });

  group('png rejects what it cannot read', () {
    test('a file that is not a PNG', () {
      expect(
        () => decodePng(Uint8List.fromList(List<int>.filled(64, 0x41))),
        throwsA(isA<FormatException>()),
      );
    });

    test('a file too short to hold a signature', () {
      expect(
        () => decodePng(Uint8List.fromList(<int>[137, 80, 78])),
        throwsA(isA<FormatException>()),
      );
    });

    test('a chunk whose length runs past the end of the file', () {
      final valid = encodePng(_gradient(4, 4));
      final truncated = Uint8List.sublistView(valid, 0, valid.length - 10);
      expect(() => decodePng(truncated), throwsA(isA<FormatException>()));
    });

    test('a bit depth other than eight', () {
      final valid = encodePng(_gradient(4, 4));
      final tampered = Uint8List.fromList(valid);
      // Byte 24 is the depth field inside IHDR.
      tampered[24] = 16;
      expect(() => decodePng(tampered), throwsA(isA<FormatException>()));
    });

    test('an interlaced file', () {
      final valid = encodePng(_gradient(4, 4));
      final tampered = Uint8List.fromList(valid)..[28] = 1;
      expect(() => decodePng(tampered), throwsA(isA<FormatException>()));
    });
  });

  group('chunk framing', () {
    test('every chunk carries a correct CRC', () {
      // Not checked on the way back in — this decoder ignores checksums — so a
      // wrong one round-trips here perfectly and is rejected by everything
      // else that will ever open these files.
      final bytes = encodePng(_gradient(5, 5));
      var offset = 8;
      var chunks = 0;
      while (offset < bytes.length) {
        final view = ByteData.sublistView(bytes);
        final length = view.getUint32(offset);
        final stated = view.getUint32(offset + 8 + length);
        final actual = crc32(
          Uint8List.sublistView(bytes, offset + 4, offset + 8 + length),
        );
        expect(actual, stated, reason: 'chunk at $offset');
        offset += 12 + length;
        chunks++;
      }
      expect(chunks, 3, reason: 'IHDR, IDAT, IEND');
    });

    test('crc32 matches the published check value', () {
      // The PNG specification's own worked example.
      expect(crc32(Uint8List.fromList('123456789'.codeUnits)), 0xCBF43926);
    });
  });
}
