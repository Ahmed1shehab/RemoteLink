import 'package:flutter/widgets.dart';

import 'screen_coordinate_mapping.dart';

/// Height of the drawn pointer in logical pixels.
///
/// Larger than the pointer would be on the desk, and deliberately. The desk has
/// been shrunk to fit a phone, so a cursor drawn at the same relative size would
/// be a couple of pixels tall and invisible against a busy screen. This is
/// drawn at a size a person can find, not at a size that is to scale.
const double kRemoteCursorHeight = 22;

/// The desk's mouse pointer, drawn over the streamed picture.
///
/// The picture does not contain it: the platform capture APIs composite windows
/// but not the cursor, so a viewer that renders only the frame shows a desk with
/// no pointer on it. Everything else about remote control can be working
/// perfectly and it will still feel broken, because the user cannot see what
/// they are aiming at.
///
/// Drawn from the position on the frame rather than from where the user last
/// touched, so it also tracks movement the desk made on its own — another app
/// warping the pointer, a second person at the keyboard.
class RemoteCursor extends StatelessWidget {
  const RemoteCursor({
    super.key,
    required this.normalised,
    required this.containerSize,
    required this.imageSize,
  });

  /// Cursor position within the frame, in 0..1, or null if it is not on this
  /// display.
  final Offset? normalised;

  final Size containerSize;
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    final position = normalised == null
        ? null
        : mapNormalisedToContainerPosition(
            normalised: normalised!,
            containerSize: containerSize,
            imageSize: imageSize,
          );
    if (position == null) return const SizedBox.shrink();

    return Positioned(
      left: position.dx,
      top: position.dy,
      // Never intercepts a touch. The cursor sits directly under wherever the
      // user is about to tap, so a hit-testing overlay there would swallow
      // exactly the taps that matter most.
      child: IgnorePointer(
        child: CustomPaint(
          size: const Size(kRemoteCursorHeight * 0.62, kRemoteCursorHeight),
          painter: _ArrowPainter(),
        ),
      ),
    );
  }
}

/// The familiar arrow, drawn rather than shipped as an asset.
///
/// White fill with a dark outline so it stays visible against both a light
/// document and a dark editor — the same reason every desktop draws its cursor
/// this way.
class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Hotspot at the origin, matching where the pointer actually points. An
    // arrow centred on the position would report a click roughly ten pixels
    // from where the desk thinks the pointer is.
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, h * 0.78)
      ..lineTo(w * 0.30, h * 0.60)
      ..lineTo(w * 0.52, h)
      ..lineTo(w * 0.76, h * 0.88)
      ..lineTo(w * 0.54, h * 0.50)
      ..lineTo(w, h * 0.46)
      ..close();

    canvas
      ..drawPath(
        path,
        Paint()
          ..color = const Color(0xE6000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(path, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => false;
}
