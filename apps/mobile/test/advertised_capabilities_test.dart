import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// Every capability the phone's UI hides a feature behind.
///
/// Keep this in step with `grep -rn '.has(Capabilities.' apps/mobile/lib`.
/// A bit that appears there and not in [kMobileCapabilities] disables its
/// feature completely and silently, which is the failure this file exists to
/// stop happening a third time.
const Map<String, int> _gatedInTheUi = <String, int>{
  'gestures (touchpad pinch and rotate)': Capabilities.gestures,
  'screenCapture (screen viewer)': Capabilities.screenCapture,
  'mediaControl (transport buttons)': Capabilities.mediaControl,
  'brightness (brightness slider)': Capabilities.brightness,
};

void main() {
  group('the capabilities this phone advertises', () {
    // Against the real constant, deliberately. Every existing widget test for
    // these features builds its own capability set by hand — which proves the
    // widget reads the bit correctly and proves nothing about whether the app
    // ever sends it. Both live bugs here passed a green suite for exactly that
    // reason.
    for (final entry in _gatedInTheUi.entries) {
      test('include ${entry.key}', () {
        expect(
          kMobileCapabilities.has(entry.value),
          isTrue,
          reason: 'The UI hides a feature unless this bit survives the '
              'handshake, and the handshake keeps only the intersection of '
              'both sides — so a bit missing here means the feature is dead '
              'no matter what the desktop can do.',
        );
      });
    }

    test('survive an intersection with a desktop that offers everything', () {
      // The shape of the real negotiation: whatever the desktop can do, the
      // phone's own list is the ceiling.
      const desktopOffersEverything = Capabilities(0xFFFFFFFF);
      final negotiated = kMobileCapabilities.intersect(desktopOffersEverything);

      for (final entry in _gatedInTheUi.entries) {
        expect(
          negotiated.has(entry.value),
          isTrue,
          reason: '${entry.key} did not survive negotiation',
        );
      }
    });

    test('do not claim anything a phone cannot take part in', () {
      // The other direction, so this file does not become a licence to paste
      // every bit in. A phone has no screen to be remote-controlled and runs
      // no commands for the desktop.
      expect(kMobileCapabilities.has(Capabilities.runCommands), isFalse);
      expect(kMobileCapabilities.has(Capabilities.powerControl), isFalse);
      expect(kMobileCapabilities.has(Capabilities.launchApps), isFalse);
    });
  });
}
