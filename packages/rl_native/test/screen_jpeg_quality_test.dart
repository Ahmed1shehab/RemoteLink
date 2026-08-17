import 'package:rl_native/rl_native.dart';
import 'package:test/test.dart';

void main() {
  group('screenJpegQualityForBitrate', () {
    test('gives the default to a peer that states the protocol default', () {
      // `ScreenStreamStart.targetBitrateKbps` defaults to 5000. A peer that
      // never thought about bandwidth must land on the value chosen for a
      // typical link, not on an edge of the range.
      expect(screenJpegQualityForBitrate(5000), kDefaultScreenJpegQuality);
    });

    test('asks for less detail when asked for less bandwidth', () {
      expect(
        screenJpegQualityForBitrate(1000),
        lessThan(screenJpegQualityForBitrate(5000)),
      );
      expect(
        screenJpegQualityForBitrate(20000),
        greaterThan(screenJpegQualityForBitrate(5000)),
      );
    });

    test('stays inside the range whatever the peer asks for', () {
      // The wire clamps to 64..100000 kbps, but this function is also called
      // with whatever a future caller invents, and a quality outside 0..1 is
      // undefined behaviour in ImageIO rather than an error.
      for (final kbps in <int>[
        -1,
        0,
        1,
        64,
        5000,
        100000,
        1 << 40,
      ]) {
        final quality = screenJpegQualityForBitrate(kbps);
        expect(quality, greaterThanOrEqualTo(kMinScreenJpegQuality));
        expect(quality, lessThanOrEqualTo(kMaxScreenJpegQuality));
      }
    });

    test('treats a nonsense bitrate as no opinion rather than as zero', () {
      // Zero would otherwise map to negative infinity doublings and clamp to
      // the floor — the worst picture in the app handed out for a field a peer
      // simply failed to set.
      expect(screenJpegQualityForBitrate(0), kDefaultScreenJpegQuality);
      expect(screenJpegQualityForBitrate(-500), kDefaultScreenJpegQuality);
    });

    test('never reaches 1.0, where JPEG stops saving anything', () {
      expect(screenJpegQualityForBitrate(100000), lessThan(1.0));
    });
  });
}
