import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/control/control_screen.dart';
import 'package:remotelink_mobile/src/features/host/phone_host_service.dart';
import 'package:rl_protocol/rl_protocol.dart';

void main() {
  group('which tabs a session is worth showing', () {
    test('a computer offers all five', () {
      // What a desktop with every permission granted intersects to. The exact
      // set matters less than that nothing is filtered out of it: this is the
      // case the screen was built for and the one every existing test assumes.
      const desktop = Capabilities(
        Capabilities.mouse |
            Capabilities.keyboard |
            Capabilities.mediaControl |
            Capabilities.clipboardText |
            Capabilities.fileTransfer,
      );

      expect(visibleTabs(desktop), ControlTab.values);
    });

    test('a phone offers the two that mean anything between phones', () {
      // The intersection of two phones is the host capability set, because
      // that is all the listening end claims. There is no cursor on the other
      // side to move and no media session to drive, so a touchpad tab would be
      // a surface that swallows gestures and sends nothing.
      expect(
        visibleTabs(kPhoneHostCapabilities),
        <ControlTab>[ControlTab.clipboard, ControlTab.send],
      );
    });

    test('a computer that cannot inject input keeps the rest', () {
      // macOS before Accessibility is granted. The desktop advertises live
      // capabilities, so this is a real state a connection can be in, and the
      // clipboard and file transfer still work throughout it.
      const noInput = Capabilities(
        Capabilities.mediaControl |
            Capabilities.clipboardText |
            Capabilities.fileTransfer,
      );

      expect(
        visibleTabs(noInput),
        <ControlTab>[ControlTab.media, ControlTab.clipboard, ControlTab.send],
      );
    });

    test('an unread handshake shows everything rather than nothing', () {
      // The moment between the screen appearing and the session being
      // readable. Hiding tabs here would flicker four of them out and back on
      // every single connection, to pre-empt a case that only arises when the
      // peer is a phone.
      expect(visibleTabs(null), ControlTab.values);
    });

    test('every tab names a capability this phone actually advertises', () {
      // The trap this catches is the one [kMobileCapabilities] documents: a
      // bit missing from what the phone claims is absent from the intersection,
      // so the desktop can be perfectly capable and the tab still never
      // appears — with nothing logged and nothing failing.
      for (final tab in ControlTab.values) {
        expect(
          kMobileCapabilities.has(tab.capability),
          isTrue,
          reason: 'the ${tab.name} tab is gated on a bit this phone does not '
              'advertise, so it can never appear',
        );
      }
    });
  });
}
