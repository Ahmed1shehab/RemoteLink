import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

/// A deliberately awkward two-monitor desk.
///
/// Not two identical 1080p panels: those would let a wrong-rectangle bug pass,
/// because halfway across the union happens to be the seam and halfway across
/// either screen is a plausible-looking number. This layout is asymmetric in
/// every axis a mapping bug could hide in — different widths, different
/// heights, different scale factors, and the secondary placed to the *left* of
/// the origin so its coordinates are negative.
///
/// ```text
///   x = -1512            x = 0                    x = 1920
///   ┌──────────────┐     ┌──────────────────────────┐
///   │ Built-in     │     │ Studio Display           │
///   │ 1512 x 982   │     │ 1920 x 1080              │
///   │ scale 2.0    │     │ scale 1.0, primary       │
///   └──────────────┘     └──────────────────────────┘
/// ```
const List<MonitorInfo> _desk = <MonitorInfo>[
  MonitorInfo(
    id: 69733248,
    bounds: ScreenBounds(x: 0, y: 0, width: 1920, height: 1080),
    name: 'Studio Display',
    isPrimary: true,
  ),
  MonitorInfo(
    id: 1,
    bounds: ScreenBounds(
      x: -1512,
      y: 98,
      width: 1512,
      height: 982,
      scaleFactor: 2.0,
    ),
    name: 'Built-in Display',
  ),
];

void main() {
  group('the unsupported backend', () {
    const backend = UnsupportedInputBackend('no driver');

    test('reports no monitors', () {
      expect(backend.monitors, isEmpty);
    });

    test('stays inert', () {
      // The null-object contract: on a platform with no input backend the app
      // must run with input disabled, not crash on launch. Reading the topology
      // is one more thing the desktop does unconditionally at connect time, so
      // it has to be as harmless as everything else here.
      expect(backend.isAvailable, isFalse);
      expect(backend.unavailableReason, 'no driver');
      expect(backend.virtualBounds.width, 0);
      expect(backend.virtualBounds.height, 0);
      expect(
        () {
          backend
            ..moveCursorTo(10, 10)
            ..moveCursorBy(1, 1)
            ..mouseDown(MouseButton.left)
            ..mouseUp(MouseButton.left)
            ..releaseAll()
            ..dispose();
        },
        returnsNormally,
      );
      // Still empty after dispose, and still not throwing.
      expect(backend.monitors, isEmpty);
    });

    test('an absolute move against it resolves without throwing', () {
      final (x, y) = MonitorTopology.resolve(
        monitors: backend.monitors,
        virtualBounds: backend.virtualBounds,
        monitorId: 7,
        x: 0.5,
        y: 0.5,
      );
      // A zero-sized desktop has exactly one addressable point.
      expect((x, y), (0, 0));
    });
  });

  group('resolving a normalised point', () {
    test('puts the centre of a monitor on that monitor', () {
      // The bug this feature exists to fix: without a monitor id, (0.5, 0.5)
      // is the centre of the *union*, which on this desk is x = 204 — on the
      // primary, nowhere near the middle of either screen.
      final (unionX, _) = MonitorTopology.resolve(
        monitors: _desk,
        virtualBounds: MonitorTopology.union(_desk),
        monitorId: MonitorTopology.wholeVirtualDesktop,
        x: 0.5,
        y: 0.5,
      );
      expect(unionX, 204);

      final (builtinX, builtinY) = MonitorTopology.resolve(
        monitors: _desk,
        virtualBounds: MonitorTopology.union(_desk),
        monitorId: 1,
        x: 0.5,
        y: 0.5,
      );
      expect(builtinX, -1512 + 756);
      expect(builtinY, 98 + 491);
      expect(builtinX, lessThan(0), reason: 'the built-in is left of origin');
    });

    test('the same normalised point lands differently per monitor', () {
      (int, int) at(int monitorId) => MonitorTopology.resolve(
            monitors: _desk,
            virtualBounds: MonitorTopology.union(_desk),
            monitorId: monitorId,
            x: 0.25,
            y: 0.75,
          );

      // Mixed DPI is the point: the two screens have different pixel counts
      // *and* different scale factors, so a mapping that used one rectangle for
      // both — or divided by the scale factor anywhere — would collapse these.
      expect(at(69733248), (480, 809));
      expect(at(1), (-1134, 834));
    });

    test('the far edge stays on its own monitor', () {
      // `1.0` must not land on the neighbour. Normalising against the full
      // width rather than width - 1 puts this at x = 1920, which is the first
      // column of the display to the right — a tap at the right edge of the
      // left screen jumping to the other screen is the most visible form of
      // this bug.
      final (x, y) = MonitorTopology.resolve(
        monitors: _desk,
        virtualBounds: MonitorTopology.union(_desk),
        monitorId: 69733248,
        x: 1.0,
        y: 1.0,
      );
      expect(x, 1919);
      expect(y, 1079);
      expect(x, lessThan(1920), reason: 'must stay off the neighbour');
    });

    test('an unknown id falls back to the virtual desktop', () {
      // What a phone sends after a monitor is unplugged: an id that resolved
      // to a screen a moment ago and now resolves to nothing. Falling back
      // keeps the cursor drivable; dropping the event would leave the user
      // tapping a touchpad that does nothing until they reconnect.
      final union = MonitorTopology.union(_desk);
      final (x, y) = MonitorTopology.resolve(
        monitors: _desk,
        virtualBounds: union,
        monitorId: 999999,
        x: 0.0,
        y: 0.0,
      );
      expect((x, y), (union.x, union.y));
    });

    test('a non-finite coordinate resolves to a defined point', () {
      // x and y arrive as float32 from a peer, so NaN and infinity cost an
      // attacker nothing to send. `num.clamp` is documented to return NaN for
      // NaN and `NaN.round()` throws `UnsupportedError`; the VM's `double`
      // implementation happens to return the upper limit instead. Pinning the
      // answer here means the behaviour is ours rather than whichever of those
      // the SDK is doing this month.
      for (final bad in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          MonitorTopology.resolve(
            monitors: _desk,
            virtualBounds: MonitorTopology.union(_desk),
            monitorId: 1,
            x: bad,
            y: bad,
          ),
          (-1512, 98),
          reason: '$bad must resolve to the monitor origin, not throw',
        );
      }
    });

    test('out-of-range coordinates clamp instead of escaping the monitor', () {
      final (low, _) = MonitorTopology.resolve(
        monitors: _desk,
        virtualBounds: MonitorTopology.union(_desk),
        monitorId: 69733248,
        x: -5.0,
        y: 0.0,
      );
      final (high, _) = MonitorTopology.resolve(
        monitors: _desk,
        virtualBounds: MonitorTopology.union(_desk),
        monitorId: 69733248,
        x: 5.0,
        y: 0.0,
      );
      expect(low, 0);
      expect(high, 1919);
    });
  });

  group('the virtual desktop union', () {
    test('spans every monitor', () {
      final union = MonitorTopology.union(_desk);
      expect(union.x, -1512);
      expect(union.y, 0);
      expect(union.right, 1920);
      expect(union.bottom, 1080);
    });

    test('takes its scale factor from the primary', () {
      // There is no single scale for a desk mixing 1x and 2x panels. The
      // primary's is the one a consumer ignoring per-monitor DPI assumed.
      expect(MonitorTopology.union(_desk).scaleFactor, 1.0);
    });

    test('is empty when there are no monitors', () {
      final union = MonitorTopology.union(const <MonitorInfo>[]);
      expect(union.isEmpty, isTrue);
      expect(union.width, 0);
    });
  });

  group('lookup', () {
    test('id zero never matches a monitor', () {
      // Zero means "the whole virtual desktop" on the wire. If it could also
      // match a monitor, a display that happened to be assigned zero would
      // silently capture every legacy peer's coordinates.
      expect(MonitorTopology.byId(_desk, 0), isNull);
    });

    test('finds a monitor by id regardless of position in the list', () {
      expect(MonitorTopology.byId(_desk, 1)?.name, 'Built-in Display');
      expect(MonitorTopology.byId(_desk, 69733248)?.name, 'Studio Display');
    });

    test('primary falls back to the first entry when none is flagged', () {
      const unflagged = <MonitorInfo>[
        MonitorInfo(
          id: 5,
          bounds: ScreenBounds(x: 0, y: 0, width: 800, height: 600),
          name: 'Display 1',
        ),
      ];
      expect(MonitorTopology.primary(unflagged)?.id, 5);
      expect(MonitorTopology.primary(const <MonitorInfo>[]), isNull);
    });
  });
}
