import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// A backend that claims it can be driven. No real one does yet.
final class _AvailablePhoneControl implements PhoneControlBackend {
  @override
  bool get isAvailable => true;

  @override
  String? get unavailableReason => null;
}

void main() {
  group('mobileCapabilities', () {
    test('does not advertise phone control when nothing can capture', () {
      // The bit is a promise to take part, and the session uses the
      // intersection of both sides. Advertising it on a phone that cannot be
      // captured would not enable anything — it would make the desktop offer a
      // control that leads nowhere, which is worse than the feature being
      // absent.
      const backend = UnsupportedPhoneControlBackend(
        unavailableReason: 'no.',
      );
      final capabilities = mobileCapabilities(backend);

      expect(capabilities.has(Capabilities.phoneControl), isFalse);
    });

    test('advertises it the moment a backend can', () {
      expect(
        mobileCapabilities(_AvailablePhoneControl())
            .has(Capabilities.phoneControl),
        isTrue,
      );
    });

    test('leaves every other advertised capability alone', () {
      // The bit is added, not substituted. Getting this wrong would silently
      // drop the clipboard or the touchpad on whichever build first gained a
      // phone-control backend.
      const unavailable = UnsupportedPhoneControlBackend(
        unavailableReason: 'no.',
      );
      final withControl = mobileCapabilities(_AvailablePhoneControl());
      final without = mobileCapabilities(unavailable);

      expect(without, kMobileCapabilities);
      expect(
        withControl.bits & ~Capabilities.phoneControl,
        kMobileCapabilities.bits,
      );
    });

    test('the real backend on this platform does not advertise it', () {
      // The end-to-end statement, through the same factory the app uses.
      expect(
        mobileCapabilities(NativeBackends.createPhoneControl())
            .has(Capabilities.phoneControl),
        isFalse,
      );
    });
  });
}
