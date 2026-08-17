import 'package:rl_protocol/rl_protocol.dart';

import 'monitor_topology.dart';

/// Synthesises input events on the host.
///
/// Deliberately narrow and synchronous. Every method here sits on the path
/// between the user's finger and the cursor, so the budget is single-digit
/// microseconds — no futures, no allocation per call, no logging. Anything that
/// needs to be async belongs in a layer above this one.
abstract interface class InputBackend {
  /// Whether this backend can actually inject events.
  ///
  /// False on macOS until the user grants Accessibility permission. The desktop
  /// app checks this before advertising input capability, so a phone never
  /// shows a touchpad that silently does nothing.
  bool get isAvailable;

  /// Human-readable reason [isAvailable] is false.
  String? get unavailableReason;

  /// Moves the cursor by a relative amount.
  void moveCursorBy(int deltaX, int deltaY);

  /// Moves the cursor to an absolute position in physical pixels.
  void moveCursorTo(int x, int y);

  /// Current cursor position.
  (int x, int y) get cursorPosition;

  void mouseDown(MouseButton button);
  void mouseUp(MouseButton button);

  /// Scrolls. [pixels] is used where the platform supports smooth scrolling and
  /// [lines] where it expects discrete notches.
  void scroll({
    required int linesX,
    required int linesY,
    required int pixelsX,
    required int pixelsY,
    bool isMomentum = false,
  });

  /// Presses or releases a key identified by its USB HID usage.
  void keyEvent({required int hidUsage, required bool pressed});

  /// Injects Unicode text directly, bypassing keycodes and layouts.
  void typeText(String text);

  /// Sets the modifier state to exactly [modifiers].
  ///
  /// Absolute rather than incremental, because a dropped release event would
  /// otherwise leave a modifier latched — the classic "everything is in caps
  /// now" bug that users cannot diagnose or fix from the phone.
  void setModifiers(Modifiers modifiers);

  /// Releases every key and button this backend believes is held.
  ///
  /// Called on disconnect. Without it, losing the connection mid-drag or with
  /// Shift held leaves the desktop stuck in that state until the user notices
  /// and presses the key locally.
  void releaseAll();

  /// Magnifies by [delta], matching macOS pinch gesture convention
  /// (e.g. `0.1` means 10% larger).
  void magnify(double delta);

  /// Rotates by [degrees] (positive is clockwise).
  void rotate(double degrees);

  /// Multi-finger swipe mapped to OS navigation (Mission Control, Task View, Spaces).
  void swipe({required int fingerCount, required SwipeDirection direction});

  /// Every attached display, primary first.
  ///
  /// Replaces the earlier `displays` getter, which returned bare rectangles.
  /// Rectangles alone cannot be addressed: without a stable id there is no way
  /// for the phone to say "the middle of *that* screen", and without a name or
  /// a primary flag there is no way for it to draw a picker the user
  /// recognises.
  ///
  /// Returns an empty list where the platform cannot be asked. Callers must
  /// handle that rather than assuming at least one entry — see [virtualBounds],
  /// which stays valid regardless and is the fallback for absolute positioning.
  ///
  /// Enumeration is a live OS query on every call, not a cached snapshot, so a
  /// monitor plugged in mid-session appears without a reconnect. It is off the
  /// hot path by construction: relative [moveCursorBy] never consults it, and
  /// absolute positioning only does so when the peer names a specific monitor.
  List<MonitorInfo> get monitors;

  /// Bounding box of all displays combined.
  ScreenBounds get virtualBounds;

  void dispose();
}

/// Reads and writes the system clipboard.
///
/// [changeCount] is the load-bearing member. Both platforms expose a cheap
/// monotonically increasing counter that changes whenever the clipboard does,
/// which means change detection is a 50 ms poll of a single integer rather than
/// an event subscription requiring a message loop and a hidden window. That is
/// what makes sub-100 ms clipboard sync affordable at negligible CPU cost.
abstract interface class ClipboardBackend {
  bool get isAvailable;

  /// Increments whenever the clipboard changes, by any application.
  int get changeCount;

  /// Current text, or `null` when the clipboard holds no text flavour.
  String? readText();

  void writeText(String text);

  /// Whether the current contents are marked confidential.
  ///
  /// Password managers set `org.nspasteboard.ConcealedType` on macOS and
  /// `ExcludeClipboardContentFromMonitorProcessing` on Windows. Honouring it
  /// keeps a copied password from being mirrored to a phone and stored in its
  /// clipboard history — which would quietly undo the password manager's whole
  /// security model.
  bool get isConcealed;

  /// PNG bytes of the current image flavour, if any.
  List<int>? readImagePng();

  void writeImagePng(List<int> pngBytes);

  void dispose();
}

/// A backend that reports itself unavailable.
///
/// Used on unsupported platforms and in tests. Every method is a no-op rather
/// than a throw: a null-object here means the desktop app runs on Linux today
/// with input disabled instead of crashing on launch.
final class UnsupportedInputBackend implements InputBackend {
  const UnsupportedInputBackend(this.unavailableReason);

  @override
  final String unavailableReason;

  @override
  bool get isAvailable => false;

  @override
  void moveCursorBy(int deltaX, int deltaY) {}

  @override
  void moveCursorTo(int x, int y) {}

  @override
  (int, int) get cursorPosition => (0, 0);

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

  @override
  void magnify(double delta) {}

  @override
  void rotate(double degrees) {}

  @override
  void swipe({required int fingerCount, required SwipeDirection direction}) {}

  /// No displays, matching how every other member here degrades.
  ///
  /// Empty rather than one synthetic 1920x1080 entry. A fabricated monitor
  /// would make the phone draw a screen picker for a machine that cannot move a
  /// cursor at all, and a tap on it would be silently discarded — the exact
  /// "connected but does nothing" experience this backend exists to prevent.
  @override
  List<MonitorInfo> get monitors => const <MonitorInfo>[];

  @override
  ScreenBounds get virtualBounds =>
      const ScreenBounds(x: 0, y: 0, width: 0, height: 0);

  @override
  void dispose() {}
}

/// Clipboard equivalent of [UnsupportedInputBackend].
final class UnsupportedClipboardBackend implements ClipboardBackend {
  const UnsupportedClipboardBackend();

  @override
  bool get isAvailable => false;

  @override
  int get changeCount => 0;

  @override
  String? readText() => null;

  @override
  void writeText(String text) {}

  @override
  bool get isConcealed => false;

  @override
  List<int>? readImagePng() => null;

  @override
  void writeImagePng(List<int> pngBytes) {}

  @override
  void dispose() {}
}
