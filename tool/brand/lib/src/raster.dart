import 'dart:math' as math;
import 'dart:typed_data';

/// An 8-bit RGBA image, four bytes a pixel, row-major, not premultiplied.
final class Raster {
  Raster({
    required this.width,
    required this.height,
    required this.pixels,
  }) : assert(
          pixels.length == width * height * 4,
          'pixel buffer does not match the stated size',
        );

  /// A raster filled with one colour.
  factory Raster.filled(int width, int height, int r, int g, int b, int a) {
    final pixels = Uint8List(width * height * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
      pixels[i + 3] = a;
    }
    return Raster(width: width, height: height, pixels: pixels);
  }

  final int width;
  final int height;
  final Uint8List pixels;

  int _index(int x, int y) => (y * width + x) * 4;

  /// The four channels of one pixel.
  (int, int, int, int) pixelAt(int x, int y) {
    final i = _index(x, y);
    return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]);
  }

  void setPixel(int x, int y, int r, int g, int b, int a) {
    final i = _index(x, y);
    pixels[i] = r;
    pixels[i + 1] = g;
    pixels[i + 2] = b;
    pixels[i + 3] = a;
  }

  /// Area-averaged rescale.
  ///
  /// Every destination pixel is the mean of the source rectangle it covers, so
  /// a 1254-pixel artwork reduced to 16 keeps the strokes visible instead of
  /// landing on whichever handful of source pixels a nearest-neighbour sample
  /// happened to hit. At icon sizes that is the difference between a legible
  /// mark and a smear.
  ///
  /// Colour is averaged premultiplied and divided back out afterwards. Without
  /// that, a transparent pixel's colour — which is arbitrary, and in a trimmed
  /// icon is usually black — is mixed into its opaque neighbours, and the
  /// result is a dark halo around every edge.
  Raster resized(int targetWidth, int targetHeight) {
    if (targetWidth < 1 || targetHeight < 1) {
      throw ArgumentError('a raster cannot be smaller than one pixel');
    }
    final out = Uint8List(targetWidth * targetHeight * 4);
    final scaleX = width / targetWidth;
    final scaleY = height / targetHeight;

    for (var y = 0; y < targetHeight; y++) {
      final y0 = y * scaleY;
      final y1 = (y + 1) * scaleY;
      final firstRow = y0.floor();
      final lastRow = math.min((y1.ceil()) - 1, height - 1);

      for (var x = 0; x < targetWidth; x++) {
        final x0 = x * scaleX;
        final x1 = (x + 1) * scaleX;
        final firstColumn = x0.floor();
        final lastColumn = math.min((x1.ceil()) - 1, width - 1);

        var r = 0.0;
        var g = 0.0;
        var b = 0.0;
        var a = 0.0;
        var total = 0.0;

        for (var sy = firstRow; sy <= lastRow; sy++) {
          final coverY = math.min(y1, sy + 1.0) - math.max(y0, sy.toDouble());
          if (coverY <= 0) continue;
          for (var sx = firstColumn; sx <= lastColumn; sx++) {
            final coverX = math.min(x1, sx + 1.0) - math.max(x0, sx.toDouble());
            if (coverX <= 0) continue;
            final weight = coverX * coverY;
            final i = _index(sx, sy);
            final alpha = pixels[i + 3] / 255;
            r += pixels[i] * alpha * weight;
            g += pixels[i + 1] * alpha * weight;
            b += pixels[i + 2] * alpha * weight;
            a += pixels[i + 3] * weight;
            total += weight;
          }
        }

        final target = (y * targetWidth + x) * 4;
        if (total == 0 || a == 0) {
          out[target + 3] = 0;
          continue;
        }
        final alpha = a / total;
        final unpremultiply = total * (alpha / 255);
        out[target] = _clampByte(r / unpremultiply);
        out[target + 1] = _clampByte(g / unpremultiply);
        out[target + 2] = _clampByte(b / unpremultiply);
        out[target + 3] = _clampByte(alpha);
      }
    }

    return Raster(width: targetWidth, height: targetHeight, pixels: out);
  }

  /// The centred square covering [fraction] of the shorter side.
  ///
  /// This is how the full-bleed variants are made. The artwork is a rounded
  /// tile on a white page, and iOS and Android round their own corners — laying
  /// the tile in directly leaves white triangles poking out of the OS mask.
  /// Cropping inside the tile throws the corners away and lets the OS cut its
  /// own.
  Raster croppedToCentre(double fraction) {
    if (fraction <= 0 || fraction > 1) {
      throw ArgumentError('crop fraction must be within (0, 1], got $fraction');
    }
    final side = (math.min(width, height) * fraction).round();
    final left = (width - side) ~/ 2;
    final top = (height - side) ~/ 2;

    final out = Uint8List(side * side * 4);
    for (var y = 0; y < side; y++) {
      final source = _index(left, top + y);
      out.setRange(y * side * 4, (y + 1) * side * 4, pixels, source);
    }
    return Raster(width: side, height: side, pixels: out);
  }

  /// The artwork with the page it was exported on cut away.
  ///
  /// The master is a dark tile centred on white. Every place the mark is drawn
  /// — the sidebar, the Dock, the taskbar — has its own background, and a white
  /// rectangle around the tile reads as a sticker stuck to the window rather
  /// than an icon. This finds the tile and returns only that.
  ///
  /// The edge is found by luminance rather than by an exact colour match,
  /// because the export is antialiased and its shadow means no two "white"
  /// pixels are the same white.
  Raster croppedToContent({double threshold = 0.82}) {
    bool isContent(int x, int y) {
      final (r, g, b, a) = pixelAt(x, y);
      if (a < 8) return false;
      return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 < threshold;
    }

    var left = width;
    var right = -1;
    var top = height;
    var bottom = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!isContent(x, y)) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    if (right < left || bottom < top) {
      throw StateError('the artwork is blank: nothing darker than $threshold');
    }

    final cropWidth = right - left + 1;
    final cropHeight = bottom - top + 1;
    final out = Uint8List(cropWidth * cropHeight * 4);
    for (var y = 0; y < cropHeight; y++) {
      out.setRange(
        y * cropWidth * 4,
        (y + 1) * cropWidth * 4,
        pixels,
        _index(left, top + y),
      );
    }
    return Raster(width: cropWidth, height: cropHeight, pixels: out);
  }

  /// Rounds the corners, making everything outside the shape transparent.
  ///
  /// Cropping to the tile leaves its rounded corners filled with whatever the
  /// export put there — here, white. Nothing downstream can fix that: a clip in
  /// the UI hides it on one screen and the Dock shows it on another. So the
  /// corners are cut in the pixels, once.
  ///
  /// [radiusFraction] is of the shorter side. The supplied artwork is drawn on
  /// roughly a 22% radius, which is also close enough to Apple's own squircle
  /// that the two do not visibly disagree.
  Raster withRoundedCorners({double radiusFraction = 0.22}) {
    final radius = math.min(width, height) * radiusFraction;
    final out = Uint8List.fromList(pixels);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // Distance from the pixel centre to the rounded rectangle, negative
        // inside. Sampling the centre and softening over one pixel is what
        // keeps the corner from looking like a staircase at 16 pixels.
        final px = x + 0.5;
        final py = y + 0.5;
        final dx = math.max(radius - px, px - (width - radius));
        final dy = math.max(radius - py, py - (height - radius));
        final double distance;
        if (dx > 0 && dy > 0) {
          distance = math.sqrt(dx * dx + dy * dy) - radius;
        } else {
          distance = math.max(dx, dy) - radius;
        }

        final coverage = (0.5 - distance).clamp(0.0, 1.0);
        if (coverage >= 1) continue;
        final i = _index(x, y);
        out[i + 3] = _clampByte(out[i + 3] * coverage);
      }
    }

    return Raster(width: width, height: height, pixels: out);
  }

  /// Centres this raster on a transparent square, occupying [fraction] of it.
  ///
  /// macOS icons are drawn inside a grid with the artwork filling about four
  /// fifths of the canvas — the rest is the room the Dock's own shadow and
  /// magnification need. Filling the canvas edge to edge is what makes an app
  /// look a size bigger than everything beside it.
  Raster centredOnSquare(double fraction) {
    if (fraction <= 0 || fraction > 1) {
      throw ArgumentError('fraction must be within (0, 1], got $fraction');
    }
    final side = (math.max(width, height) / fraction).round();
    final out = Uint8List(side * side * 4);
    final left = (side - width) ~/ 2;
    final top = (side - height) ~/ 2;
    for (var y = 0; y < height; y++) {
      out.setRange(
        ((top + y) * side + left) * 4,
        ((top + y) * side + left + width) * 4,
        pixels,
        y * width * 4,
      );
    }
    return Raster(width: side, height: side, pixels: out);
  }

  /// A monochrome mask of the artwork, light shapes becoming opaque.
  ///
  /// macOS asks for a *template* image in the menu bar: it throws the colours
  /// away and paints the alpha channel itself, in black or white to match the
  /// bar. Handing it the artwork as it stands produces a filled rectangle,
  /// because every pixel of the tile is opaque — which is exactly what shipped,
  /// and why the menu the user is told to quit from could not be seen.
  ///
  /// So the mark is recovered from brightness: the tile's own background
  /// becomes fully transparent and the white strokes fully opaque, with
  /// [softness] of the range either side left as antialiasing rather than
  /// clipped to a hard edge.
  Raster asTemplateMask({double softness = 0.15}) {
    final background = _dominantBackgroundLuminance();
    final span = math.max(1e-6, 1 - background);
    final out = Uint8List(width * height * 4);

    for (var i = 0; i < width * height; i++) {
      final source = i * 4;
      final luminance = (0.2126 * pixels[source] +
              0.7152 * pixels[source + 1] +
              0.0722 * pixels[source + 2]) /
          255;
      // Weighted by the pixel's own alpha so an already-transparent margin
      // cannot contribute a shape of its own.
      final coverage = ((luminance - background) / span).clamp(0.0, 1.0) *
          (pixels[source + 3] / 255);
      final eased = softness <= 0
          ? (coverage >= 0.5 ? 1.0 : 0.0)
          : _smoothstep(softness, 1 - softness, coverage);

      // Black, because a template image's colour is never used and black is
      // what every decoder shows if one ever is.
      out[source + 3] = _clampByte(eased * 255);
    }

    return Raster(width: width, height: height, pixels: out);
  }

  /// The luminance of the most common colour around the outside edge.
  ///
  /// Sampled from the border rather than a single corner: one corner is a
  /// drop shadow or a stray antialiased pixel away from being unrepresentative,
  /// and getting this wrong shifts the whole mask.
  double _dominantBackgroundLuminance() {
    final counts = <int, int>{};
    void sample(int x, int y) {
      final i = _index(x, y);
      if (pixels[i + 3] == 0) return;
      final luminance = (0.2126 * pixels[i] +
              0.7152 * pixels[i + 1] +
              0.0722 * pixels[i + 2]) /
          255;
      // Bucketed, so antialiasing noise does not defeat the count.
      final bucket = (luminance * 32).round();
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }

    // A tenth of the way in, which is inside the tile and clear of the page.
    final inset = math.max(1, math.min(width, height) ~/ 10);
    for (var x = inset; x < width - inset; x++) {
      sample(x, inset);
      sample(x, height - 1 - inset);
    }
    for (var y = inset; y < height - inset; y++) {
      sample(inset, y);
      sample(width - 1 - inset, y);
    }

    if (counts.isEmpty) return 0;
    var best = 0;
    var bestCount = -1;
    counts.forEach((bucket, count) {
      if (count > bestCount) {
        best = bucket;
        bestCount = count;
      }
    });
    return best / 32;
  }
}

double _smoothstep(double edge0, double edge1, double x) {
  if (edge1 <= edge0) return x >= edge1 ? 1 : 0;
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

int _clampByte(double value) => value.round().clamp(0, 255);
