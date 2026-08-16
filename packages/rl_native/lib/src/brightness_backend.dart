/// Display brightness backend for RemoteLink host platforms.
library;

/// Controls display brightness on the host.
///
/// Separate from [InputBackend] and [MediaBackend] because the mechanisms have
/// nothing in common: input is synthesised HID events on a microsecond budget,
/// media control goes through transport sessions/audio services, and display
/// brightness talks to display services, WMI, or DDC/CI monitor buses.
abstract interface class BrightnessBackend {
  /// Whether this backend can read or adjust display brightness.
  bool get isAvailable;

  /// Human-readable reason [isAvailable] is false.
  String? get unavailableReason;

  /// Reads the current brightness level, normalized `0.0`–`1.0`.
  Future<double> level();

  /// Sets the brightness level, normalized `0.0`–`1.0`.
  Future<void> setLevel(double level);

  void dispose();
}

/// Fallback backend for unsupported platforms or missing permissions.
final class UnsupportedBrightnessBackend implements BrightnessBackend {
  const UnsupportedBrightnessBackend([this.unavailableReason]);

  @override
  final String? unavailableReason;

  @override
  bool get isAvailable => false;

  @override
  Future<double> level() async => 0.0;

  @override
  Future<void> setLevel(double level) async {}

  @override
  void dispose() {}
}
