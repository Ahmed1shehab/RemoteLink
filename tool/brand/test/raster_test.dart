import 'dart:typed_data';

import 'package:brand/brand.dart';
import 'package:test/test.dart';

/// A dark tile on a white page, which is the shape of the real artwork.
Raster _tileOnWhitePage({
  int side = 40,
  int margin = 6,
  int markInset = 14,
}) {
  final image = Raster.filled(side, side, 255, 255, 255, 255);
  for (var y = margin; y < side - margin; y++) {
    for (var x = margin; x < side - margin; x++) {
      image.setPixel(x, y, 37, 44, 61, 255);
    }
  }
  // A white mark in the middle of the tile, standing in for the logo strokes.
  for (var y = markInset; y < side - markInset; y++) {
    for (var x = markInset; x < side - markInset; x++) {
      image.setPixel(x, y, 255, 255, 255, 255);
    }
  }
  return image;
}

void main() {
  group('resize', () {
    test('averages rather than sampling', () {
      // Two columns, one black and one white. Nearest-neighbour would return
      // whichever it landed on; the average is the only answer that says both
      // were there, and at 16 pixels that is the whole legibility of the mark.
      final source = Raster.filled(2, 1, 0, 0, 0, 255)
        ..setPixel(1, 0, 255, 255, 255, 255);
      final (r, g, b, a) = source.resized(1, 1).pixelAt(0, 0);

      expect(r, inInclusiveRange(126, 129));
      expect(g, inInclusiveRange(126, 129));
      expect(b, inInclusiveRange(126, 129));
      expect(a, 255);
    });

    test('does not bleed a transparent pixel\'s colour into its neighbour', () {
      // The transparent half is white, which is a colour the eye can see
      // arriving: averaging without premultiplying drags the red halfway to
      // white and puts a pale halo round every edge of the mark.
      //
      // Transparent *black* would not catch it — zero channels contribute
      // nothing to the sum either way — which is what this test started as.
      final source = Raster.filled(2, 1, 255, 255, 255, 0)
        ..setPixel(1, 0, 255, 40, 40, 255);
      final (r, g, b, a) = source.resized(1, 1).pixelAt(0, 0);

      expect(r, 255);
      expect(g, 40, reason: 'the invisible white must not lighten the red');
      expect(b, 40);
      expect(a, inInclusiveRange(126, 129));
    });

    test('keeps the requested size', () {
      final resized = _tileOnWhitePage().resized(17, 5);
      expect(resized.width, 17);
      expect(resized.height, 5);
      expect(resized.pixels.length, 17 * 5 * 4);
    });

    test('refuses a size smaller than a pixel', () {
      expect(() => _tileOnWhitePage().resized(0, 8), throwsArgumentError);
    });
  });

  group('croppedToContent', () {
    test('removes the page the tile was exported on', () {
      final cropped = _tileOnWhitePage(side: 40, margin: 6).croppedToContent();

      expect(cropped.width, 28);
      expect(cropped.height, 28);
      // Its own corner is now the tile, not the page.
      expect(cropped.pixelAt(0, 0), (37, 44, 61, 255));
    });

    test('throws rather than returning an empty image', () {
      expect(
        () => Raster.filled(8, 8, 255, 255, 255, 255).croppedToContent(),
        throwsStateError,
      );
    });
  });

  group('withRoundedCorners', () {
    test('clears the corners and keeps the middle', () {
      final rounded =
          Raster.filled(64, 64, 10, 20, 30, 255).withRoundedCorners();

      expect(rounded.pixelAt(0, 0).$4, 0, reason: 'top left');
      expect(rounded.pixelAt(63, 0).$4, 0, reason: 'top right');
      expect(rounded.pixelAt(0, 63).$4, 0, reason: 'bottom left');
      expect(rounded.pixelAt(63, 63).$4, 0, reason: 'bottom right');
      expect(rounded.pixelAt(32, 32).$4, 255, reason: 'centre');
      expect(rounded.pixelAt(32, 0).$4, 255, reason: 'top edge midpoint');
    });

    test('softens the corner rather than cutting it in steps', () {
      final rounded =
          Raster.filled(64, 64, 10, 20, 30, 255).withRoundedCorners();
      var partial = 0;
      for (var i = 0; i < 64; i++) {
        final alpha = rounded.pixelAt(i, 0).$4;
        if (alpha > 0 && alpha < 255) partial++;
      }
      expect(partial, greaterThan(0),
          reason: 'a hard cut leaves a staircase at icon sizes');
    });

    test('leaves the colours alone', () {
      final rounded =
          Raster.filled(8, 8, 10, 20, 30, 255).withRoundedCorners();
      expect(rounded.pixelAt(4, 4), (10, 20, 30, 255));
    });
  });

  group('centredOnSquare', () {
    test('adds transparent margin without moving the artwork off centre', () {
      final padded = Raster.filled(80, 80, 1, 2, 3, 255).centredOnSquare(0.8);

      expect(padded.width, 100);
      expect(padded.height, 100);
      expect(padded.pixelAt(0, 0).$4, 0, reason: 'margin is transparent');
      expect(padded.pixelAt(50, 50), (1, 2, 3, 255));
      expect(padded.pixelAt(10, 50), (1, 2, 3, 255), reason: 'left edge');
      expect(padded.pixelAt(9, 50).$4, 0, reason: 'just outside the artwork');
    });

    test('refuses a fraction outside (0, 1]', () {
      final image = Raster.filled(4, 4, 0, 0, 0, 255);
      expect(() => image.centredOnSquare(0), throwsArgumentError);
      expect(() => image.centredOnSquare(1.2), throwsArgumentError);
    });
  });

  group('asTemplateMask', () {
    test('turns the light mark opaque and the tile transparent', () {
      // What the menu bar needs: macOS throws the colours away and paints the
      // alpha itself. Handing it the tile as it stands paints a rectangle,
      // which is exactly what shipped.
      final mask = _tileOnWhitePage(side: 40, margin: 0, markInset: 14)
          .asTemplateMask();

      expect(mask.pixelAt(20, 20).$4, 255, reason: 'the mark');
      expect(mask.pixelAt(2, 2).$4, 0, reason: 'the tile behind it');
    });

    test('ignores a margin that is already transparent', () {
      final image = Raster.filled(20, 20, 255, 255, 255, 0);
      for (var y = 6; y < 14; y++) {
        for (var x = 6; x < 14; x++) {
          image.setPixel(x, y, 255, 255, 255, 255);
        }
      }
      final mask = image.asTemplateMask();

      expect(mask.pixelAt(10, 10).$4, 255);
      expect(mask.pixelAt(1, 1).$4, 0,
          reason: 'a transparent pixel must not contribute a shape');
    });
  });

  group('encodeIco', () {
    test('describes each entry at the offset it was written to', () {
      final bytes = encodeIco(<Raster>[
        Raster.filled(16, 16, 1, 2, 3, 255),
        Raster.filled(32, 32, 4, 5, 6, 255),
      ]);
      final view = ByteData.sublistView(bytes);

      expect(view.getUint16(0, Endian.little), 0, reason: 'reserved');
      expect(view.getUint16(2, Endian.little), 1, reason: 'type: icon');
      expect(view.getUint16(4, Endian.little), 2, reason: 'count');

      for (var i = 0; i < 2; i++) {
        final entry = 6 + 16 * i;
        final side = view.getUint8(entry);
        final length = view.getUint32(entry + 8, Endian.little);
        final offset = view.getUint32(entry + 12, Endian.little);

        expect(side, i == 0 ? 16 : 32);
        expect(offset + length, lessThanOrEqualTo(bytes.length));
        // Each entry has to be a PNG a decoder can actually open, at the size
        // the directory claims — a directory that agrees with itself and lies
        // about the payload is the failure mode here.
        final embedded =
            decodePng(Uint8List.sublistView(bytes, offset, offset + length));
        expect(embedded.width, side);
      }
    });

    test('writes 256 as the zero the format reserves for it', () {
      // The width field is one byte, and zero is the format's escape for the
      // largest an icon may be. Writing 256 into a `setUint8` truncates to that
      // same zero, so this cannot fail while the field stays one byte — it is
      // here to catch the field being widened or the entry reordered, not to
      // prove the ternary that writes it earns its keep.
      final bytes = encodeIco(<Raster>[Raster.filled(256, 256, 0, 0, 0, 255)]);
      expect(ByteData.sublistView(bytes).getUint8(6), 0);
    });

    test('refuses entries larger than the format allows', () {
      expect(
        () => encodeIco(<Raster>[Raster.filled(512, 512, 0, 0, 0, 255)]),
        throwsArgumentError,
      );
    });

    test('refuses entries that are not square', () {
      expect(
        () => encodeIco(<Raster>[Raster.filled(16, 32, 0, 0, 0, 255)]),
        throwsArgumentError,
      );
    });

    test('refuses an empty icon', () {
      expect(() => encodeIco(<Raster>[]), throwsArgumentError);
    });
  });
}
