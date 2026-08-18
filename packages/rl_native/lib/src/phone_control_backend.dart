/// Driving the phone from the desktop — the reverse of everything else here.
///
/// The interface exists and no implementation does, which is the honest state
/// of this feature rather than a gap waiting to be filled in.
///
/// On iOS it cannot be built. Capturing the screen from outside the app needs a
/// ReplayKit broadcast the user starts by hand, and injecting a touch into
/// another app has no public API at all. Both are deliberate platform
/// boundaries, not permissions that can be requested.
///
/// On Android it can be built, through MediaProjection and an
/// AccessibilityService, and is blocked by ADR 0003: this repository ships no
/// compiled native shim, and an AccessibilityService is Kotlin by definition.
/// Building it means revisiting that decision first, not writing more Dart.
///
/// So the interface reports *why*, per platform, rather than merely reporting
/// false. A capability that is off for a reason the user can never discover is
/// indistinguishable from one that is broken.
abstract interface class PhoneControlBackend {
  /// Whether this device can be watched and driven from a desktop.
  bool get isAvailable;

  /// Why not, when [isAvailable] is false. Shown to the user.
  ///
  /// Always non-null when unavailable — a backend that says no without saying
  /// why leaves the UI with nothing to show but a disabled control.
  String? get unavailableReason;
}

/// The only implementation there is: one that says no, and says why.
final class UnsupportedPhoneControlBackend implements PhoneControlBackend {
  const UnsupportedPhoneControlBackend({required this.unavailableReason});

  @override
  bool get isAvailable => false;

  @override
  final String unavailableReason;
}
