import 'package:meta/meta.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// Screen geometry in the host's *cursor* coordinate space.
///
/// Deliberately not "physical pixels": the two platforms disagree, and the only
/// coordinate space that matters here is the one the cursor APIs accept.
/// `CGEventCreateMouseEvent` takes global points, so macOS bounds are points;
/// `SetCursorPos` in a per-monitor-DPI-aware process takes physical pixels, so
/// Windows bounds are pixels. [scaleFactor] carries the ratio between the two
/// so a phone can size a screen preview correctly, but positioning never needs
/// it — a point inside [x], [y], [width], [height] is directly usable by
/// `moveCursorTo` on the backend that produced it.
@immutable
final class ScreenBounds {
  const ScreenBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.scaleFactor = 1.0,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  /// DPI scale, e.g. `2.0` on a Retina or 200%-scaled display.
  final double scaleFactor;

  int get right => x + width;
  int get bottom => y + height;

  bool get isEmpty => width <= 0 || height <= 0;

  @override
  String toString() => 'ScreenBounds(${width}x$height @ $x,$y)';
}

/// One display, as the host enumerates it.
///
/// The reason this exists rather than a bare [ScreenBounds] is addressing. A
/// normalised `[0,1]` coordinate is only unambiguous once you know *which*
/// rectangle it is normalised against, and on a two-monitor desk the rectangle
/// the user means is one screen, not the union of both. Everything else here
/// ([name], [scaleFactor], [isPrimary]) exists so the phone can draw a picker
/// that looks like the desk rather than a list of numbered rectangles.
@immutable
final class MonitorInfo {
  const MonitorInfo({
    required this.id,
    required this.bounds,
    required this.name,
    this.isPrimary = false,
  });

  /// Opaque handle identifying this display, stable while it stays connected.
  ///
  /// An *index* would have been simpler and is wrong: unplugging the first of
  /// three monitors renumbers the other two, so a phone holding "monitor 1"
  /// would silently start addressing a different screen mid-session. An id the
  /// host derives from the display itself survives that — a stale id resolves
  /// to nothing and falls back, which is visible and recoverable, rather than
  /// resolving to the wrong screen, which is not.
  ///
  /// Always non-zero for a real display: zero is reserved on the wire to mean
  /// "the whole virtual desktop" (see [MonitorTopology.wholeVirtualDesktop]).
  final int id;

  final ScreenBounds bounds;

  /// Human-readable label, e.g. `Built-in Display` or `Display 2`.
  final String name;

  final bool isPrimary;

  /// DPI scale of this display. Mirrors `bounds.scaleFactor`; monitors in a
  /// mixed-DPI setup each carry their own.
  double get scaleFactor => bounds.scaleFactor;

  @override
  String toString() =>
      'MonitorInfo($id, "$name", $bounds${isPrimary ? ', primary' : ''})';
}

/// Pure geometry over a list of [MonitorInfo].
///
/// Split out from the backends deliberately. Resolving a normalised coordinate
/// is the part of multi-monitor support that is easy to get subtly wrong and
/// impossible to test against real hardware — a two-monitor mixed-DPI layout is
/// not something CI has — so it is a pure function over an injectable list
/// rather than a method that reads the machine's actual displays.
abstract final class MonitorTopology {
  /// Monitor id meaning "map across the whole virtual desktop".
  ///
  /// Aliases the wire constant rather than redeclaring it: two copies of a
  /// reserved value are two things that can drift apart, and this one is load
  /// bearing for every peer that predates the field.
  static const int wholeVirtualDesktop = kWholeVirtualDesktopMonitorId;

  /// The monitor with [id], or `null` when no monitor matches.
  ///
  /// A linear scan: this runs on the input path and a desk has single-digit
  /// monitors, so a map would cost more to build than the scan costs to walk.
  static MonitorInfo? byId(List<MonitorInfo> monitors, int id) {
    if (id == wholeVirtualDesktop) return null;
    for (final monitor in monitors) {
      if (monitor.id == id) return monitor;
    }
    return null;
  }

  /// The primary monitor, or the first one, or `null` when there are none.
  static MonitorInfo? primary(List<MonitorInfo> monitors) {
    for (final monitor in monitors) {
      if (monitor.isPrimary) return monitor;
    }
    return monitors.isEmpty ? null : monitors.first;
  }

  /// Bounding box of every monitor combined.
  ///
  /// The scale factor of the union is the primary display's: a virtual desktop
  /// spanning a Retina and a 1x panel has no single scale, and the primary is
  /// the one a consumer that ignores per-monitor DPI would have assumed.
  static ScreenBounds union(List<MonitorInfo> monitors) {
    if (monitors.isEmpty) {
      return const ScreenBounds(x: 0, y: 0, width: 0, height: 0);
    }

    var left = monitors.first.bounds.x;
    var top = monitors.first.bounds.y;
    var right = monitors.first.bounds.right;
    var bottom = monitors.first.bounds.bottom;

    for (final monitor in monitors.skip(1)) {
      final bounds = monitor.bounds;
      if (bounds.x < left) left = bounds.x;
      if (bounds.y < top) top = bounds.y;
      if (bounds.right > right) right = bounds.right;
      if (bounds.bottom > bottom) bottom = bounds.bottom;
    }

    return ScreenBounds(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
      scaleFactor: primary(monitors)?.scaleFactor ?? 1.0,
    );
  }

  /// Maps a normalised `[0,1]` point onto host coordinates.
  ///
  /// [monitorId] selects the rectangle to normalise against: a real monitor id
  /// picks that screen, and [wholeVirtualDesktop] — or an id no longer present,
  /// which is what a phone holding a stale topology sends after a monitor is
  /// unplugged — falls back to [virtualBounds]. Falling back rather than
  /// dropping the event matters: a dropped absolute move leaves the cursor
  /// wherever it was with no feedback, and the user's only recourse is to
  /// reconnect.
  static (int x, int y) resolve({
    required List<MonitorInfo> monitors,
    required ScreenBounds virtualBounds,
    required int monitorId,
    required double x,
    required double y,
  }) {
    final bounds = byId(monitors, monitorId)?.bounds ?? virtualBounds;
    return (
      bounds.x + _project(x, bounds.width),
      bounds.y + _project(y, bounds.height),
    );
  }

  /// Projects a normalised coordinate onto `[0, extent)`.
  static int _project(double normalised, int extent) {
    // The value arrived as a float32 from a peer, so NaN costs an attacker
    // nothing to send. Whether that crashes depends on which `clamp` you
    // believe: `num.clamp` is documented to return NaN for NaN, and
    // `NaN.round()` throws `UnsupportedError` — but the VM's `double.clamp`
    // currently returns the upper limit instead, so today it silently produces
    // the far edge. Relying on either is a latent crash one SDK release away,
    // and neither is a *defined* answer, so non-finite input gets one here.
    if (!normalised.isFinite) return 0;
    if (extent <= 0) return 0;

    // `extent - 1`, not `extent`. Normalising against the full width puts
    // `1.0` one pixel past the right edge — on a single screen that is a
    // harmless clamp, but on a monitor with a neighbour to its right it lands
    // the cursor on the *other screen*, which is exactly the bug per-monitor
    // addressing exists to fix.
    return (normalised.clamp(0.0, 1.0) * (extent - 1)).round();
  }
}
