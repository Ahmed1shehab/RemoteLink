import 'dart:ui' show Size;

import 'package:rl_protocol/rl_protocol.dart';

/// Smallest frame width this phone will ask for, in pixels.
///
/// Below this a desk stops being legible at all — window titles and menu bar
/// text turn to mush — and the saving is not worth it, because the payload is
/// already small enough that the link is no longer the constraint.
const int kMinStreamedFrameWidth = 960;

/// Largest frame width this phone will ask for, in pixels.
///
/// Deliberately far below a modern phone's physical pixel count. A 6-inch panel
/// at three times scale has around 2600 physical pixels along its long edge,
/// and asking the desk for a frame that wide roughly quadruples the payload
/// versus this cap — to render detail at a density no one can resolve on a
/// screen held at arm's length. The desk is being shrunk to palm size either
/// way; what is illegible at 1440 is illegible at 2600.
const int kMaxStreamedFrameWidth = 1440;

/// Pixels requested per logical pixel of the phone's own screen.
///
/// Two rather than the device's real pixel ratio: it keeps a little detail in
/// hand for the moment the user rotates and the picture spans the long edge,
/// without paying for the full retina factor that the cap above rejects anyway.
const double _pixelsPerLogicalPixel = 2.0;

/// Target frame rate requested from the desk.
///
/// A ceiling, not a promise. The desktop paces its capture loop against how
/// fast the link actually drains, so asking for 30 does not commit either side
/// to 30 — it only says "no faster than this, however good the network looks".
const int kStreamedFrameRate = 30;

/// The [ScreenStreamStart] this phone should send for its own screen.
///
/// Split out as a plain function over a [Size] rather than read off a
/// `MediaQuery` inside the widget so the arithmetic can be tested for what it
/// actually produces. The previous request was a hard-coded 1920x1080 — a
/// number chosen for a desk, sent by a phone, and never once compared against
/// the screen it was going to be drawn on.
///
/// [logicalSize] is the viewer's own size in logical pixels; orientation does
/// not matter, because the longer edge is what the picture spans once the
/// phone is turned.
ScreenStreamStart screenStreamRequestFor({
  required int monitorId,
  required Size logicalSize,
}) {
  final longestEdge = logicalSize.width > logicalSize.height
      ? logicalSize.width
      : logicalSize.height;

  // A zero or nonsense size means the view has not been laid out yet. Ask for
  // the floor rather than for nothing: `maxWidth: 0` means "unconstrained" on
  // the wire, which would request a full native-resolution desk — the exact
  // failure this function exists to prevent, arrived at by accident.
  final budget = longestEdge.isFinite && longestEdge > 0
      ? (longestEdge * _pixelsPerLogicalPixel).round()
      : kMinStreamedFrameWidth;

  final target = budget.clamp(kMinStreamedFrameWidth, kMaxStreamedFrameWidth);

  return ScreenStreamStart(
    monitorId: monitorId,
    targetFps: kStreamedFrameRate,
    codec: ScreenCodec.jpeg,
    // Both axes carry the same budget. The desk scales to fit inside the pair
    // while keeping its aspect ratio, so on a landscape desk the width binds
    // and the height comes out proportionally smaller — and on a monitor in
    // portrait, the reverse. Constraining only one axis would let the other
    // run to native resolution on a rotated display.
    maxWidth: target,
    maxHeight: target,
  );
}
