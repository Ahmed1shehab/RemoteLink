import 'dart:io';

import 'package:rl_native/rl_native.dart';
import 'package:test/test.dart';

void main() {
  group('PhoneControlBackend', () {
    test('the factory never returns an available backend', () {
      // The assertion that keeps this feature honest. Nothing on any platform
      // can currently capture or drive a phone, so anything that reported
      // otherwise would light up a desktop button leading nowhere.
      expect(NativeBackends.createPhoneControl().isAvailable, isFalse);
    });

    test('it explains itself rather than only refusing', () {
      // A capability that is off for a reason the user can never discover is
      // indistinguishable from one that is broken.
      final reason = NativeBackends.createPhoneControl().unavailableReason;
      expect(reason, isNotNull);
      expect(reason, isNotEmpty);
      expect(
        reason,
        endsWith('.'),
        reason: 'this is shown to a person, not logged',
      );
    });

    test('the reason names the platform it is talking about', () {
      // A shared "not supported" string would tell an iPhone owner the same
      // thing as an Android owner, and only one of them is permanent.
      final reason = NativeBackends.createPhoneControl().unavailableReason!;
      if (Platform.isIOS) {
        expect(reason, contains('iOS'));
      } else if (Platform.isAndroid) {
        expect(reason, contains('accessibility'));
      } else {
        expect(reason, contains('phones'));
      }
    });

    test('an unsupported backend is never available whatever it is given', () {
      const backend = UnsupportedPhoneControlBackend(
        unavailableReason: 'because.',
      );
      expect(backend.isAvailable, isFalse);
      expect(backend.unavailableReason, 'because.');
    });
  });
}
