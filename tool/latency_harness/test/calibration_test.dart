import 'package:latency_harness/latency_harness.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

final class _FakeInputBackend implements InputBackend {
  _FakeInputBackend({
    this.isAvailable = true,
    this.unavailableReason,
    this.readDelayMicros = 40,
    FakeClock? clock,
  }) : _clock = clock;

  @override
  final bool isAvailable;

  @override
  final String? unavailableReason;

  final int readDelayMicros;
  final FakeClock? _clock;

  int _x = 500;
  int _y = 500;

  @override
  (int, int) get cursorPosition {
    if (_clock != null) {
      _clock.advance(Duration(microseconds: readDelayMicros));
    }
    return (_x, _y);
  }

  @override
  void moveCursorTo(int x, int y) {
    _x = x;
    _y = y;
  }

  @override
  void moveCursorBy(int deltaX, int deltaY) {
    _x += deltaX;
    _y += deltaY;
  }

  @override
  List<ScreenBounds> get displays => const <ScreenBounds>[
        ScreenBounds(x: 0, y: 0, width: 1920, height: 1080),
      ];

  @override
  ScreenBounds get virtualBounds =>
      const ScreenBounds(x: 0, y: 0, width: 1920, height: 1080);

  @override
  void mouseDown(MouseButton button) {}

  @override
  void mouseUp(MouseButton button) {}

  @override
  void scroll({
    required int linesX,
    required int linesY,
    required int pixelsX,
    required int pixelsY,
    bool isMomentum = false,
  }) {}

  @override
  void keyEvent({required int hidUsage, required bool pressed}) {}

  @override
  void typeText(String text) {}

  @override
  void setModifiers(Modifiers modifiers) {}

  @override
  void releaseAll() {}

  // Gestures are irrelevant to latency calibration, which only moves the cursor
  // and reads it back — but the interface requires them.
  @override
  void magnify(double delta) {}

  @override
  void rotate(double degrees) {}

  @override
  void swipe({required int fingerCount, required SwipeDirection direction}) {}

  @override
  void dispose() {}
}

void main() {
  group('applyCalibration', () {
    test('subtracts overhead and clamps to zero', () {
      final raw = <int>[20, 50, 100, 250, 500];
      const overhead = 50.0;

      final calibrated = applyCalibration(raw, overhead);

      expect(calibrated, <double>[0.0, 0.0, 50.0, 200.0, 450.0]);
    });

    test('exact subtraction with zero overhead leaves values unchanged', () {
      final raw = <int>[100, 200, 300];
      final calibrated = applyCalibration(raw, 0.0);

      expect(calibrated, <double>[100.0, 200.0, 300.0]);
    });
  });

  group('CalibrationResult', () {
    test('subtractFrom and subtractFromValue work as expected', () {
      const stats = PercentileStats(
        count: 10,
        p50: 45.0,
        p95: 50.0,
        p99: 55.0,
        p999: 60.0,
        max: 65.0,
        min: 40.0,
      );

      const result = CalibrationResult(
        overheadMicros: 45.0,
        stats: stats,
      );

      expect(result.overheadMillis, 0.045);
      expect(result.subtractFromValue(100), 55.0);
      expect(result.subtractFromValue(30), 0.0);
      expect(
          result.subtractFrom(<int>[40, 50, 145]), <double>[0.0, 5.0, 100.0]);
    });

    test('JSON serialization round-trip', () {
      const stats = PercentileStats(
        count: 100,
        p50: 35.5,
        p95: 42.0,
        p99: 50.0,
        p999: 60.0,
        max: 75.0,
        min: 30.0,
      );

      const original = CalibrationResult(
        overheadMicros: 35.5,
        stats: stats,
      );

      final json = original.toJson();
      final restored = CalibrationResult.fromJson(json);

      expect(restored.overheadMicros, original.overheadMicros);
      expect(restored.overheadMillis, original.overheadMillis);
      expect(restored.stats.p50, original.stats.p50);
      expect(restored.stats.p99, original.stats.p99);
    });
  });

  group('calibrateLocalInput', () {
    test('measures overhead against fake input backend with fake clock', () {
      final clock = FakeClock();
      final input = _FakeInputBackend(
        readDelayMicros: 75,
        clock: clock,
      );

      final result = calibrateLocalInput(
        input,
        clock: clock,
        sampleCount: 100,
      );

      expect(result.stats.count, 100);
      expect(result.overheadMicros, 75.0);
      expect(result.overheadMillis, 0.075);
    });

    test('throws StateError when backend is unavailable', () {
      final clock = FakeClock();
      final input = _FakeInputBackend(
        isAvailable: false,
        unavailableReason: 'Permission required',
        clock: clock,
      );

      expect(
        () => calibrateLocalInput(input, clock: clock, sampleCount: 10),
        throwsStateError,
      );
    });
  });
}
