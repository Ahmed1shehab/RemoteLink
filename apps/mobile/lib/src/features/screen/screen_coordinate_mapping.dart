import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Computes the destination rectangle where an image of size [imageSize] is
/// drawn inside a container of size [containerSize] under [BoxFit.contain] with
/// [Alignment.center].
///
/// Returns [Rect.zero] if either size is non-positive or empty.
Rect computeContainedImageRect({
  required Size containerSize,
  required Size imageSize,
}) {
  if (containerSize.width <= 0 ||
      containerSize.height <= 0 ||
      imageSize.width <= 0 ||
      imageSize.height <= 0) {
    return Rect.zero;
  }

  final scale = math.min(
    containerSize.width / imageSize.width,
    containerSize.height / imageSize.height,
  );

  final drawnWidth = imageSize.width * scale;
  final drawnHeight = imageSize.height * scale;

  final drawnLeft = (containerSize.width - drawnWidth) / 2.0;
  final drawnTop = (containerSize.height - drawnHeight) / 2.0;

  return Rect.fromLTWH(drawnLeft, drawnTop, drawnWidth, drawnHeight);
}

/// Maps a touch position [touchPosition] in container coordinates to
/// normalised (0.0..1.0) coordinates within the drawn image rectangle.
///
/// If [touchPosition] falls in the letterbox or pillarbox bars outside the
/// drawn image rectangle, this returns `null` (rejecting the touch).
///
/// If either [containerSize] or [imageSize] is invalid or empty, this returns `null`.
Offset? mapTouchToNormalisedCoordinates({
  required Offset touchPosition,
  required Size containerSize,
  required Size imageSize,
}) {
  final drawnRect = computeContainedImageRect(
    containerSize: containerSize,
    imageSize: imageSize,
  );

  if (drawnRect.isEmpty || drawnRect.width <= 0 || drawnRect.height <= 0) {
    return null;
  }

  // Reject touches outside the drawn image rectangle (letterbox / pillarbox bars).
  // Use inclusive bounds so corner and edge taps (0,0) and (1,1) are accepted.
  if (touchPosition.dx < drawnRect.left ||
      touchPosition.dx > drawnRect.right ||
      touchPosition.dy < drawnRect.top ||
      touchPosition.dy > drawnRect.bottom) {
    return null;
  }

  final normX =
      ((touchPosition.dx - drawnRect.left) / drawnRect.width).clamp(0.0, 1.0);
  final normY =
      ((touchPosition.dy - drawnRect.top) / drawnRect.height).clamp(0.0, 1.0);

  return Offset(normX, normY);
}
