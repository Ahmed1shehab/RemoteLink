import 'package:rl_protocol/rl_protocol.dart';

/// Translates USB HID usages to platform key identifiers.
///
/// One table per platform, built once and looked up in constant time. Both maps
/// are deliberately incomplete in the same way: they cover the keys a physical
/// keyboard has, and nothing else. A usage with no entry is dropped rather than
/// guessed at, because a wrong guess injects a keystroke the user did not ask
/// for — considerably worse than injecting nothing.
abstract final class KeyMap {
  /// HID usage to Windows virtual-key code.
  ///
  /// Virtual keys are *logical*: on an AZERTY keyboard the physical Q position
  /// generates `VK_A`, and Windows resolves `Ctrl+VK_A` to Select All. Sending
  /// virtual keys therefore makes shortcuts land correctly on every layout,
  /// which is what a remote control wants. Scan codes would give physical-key
  /// fidelity instead, and are the wrong trade here.
  static const Map<int, int> hidToVirtualKey = <int, int>{
    // Letters map to their ASCII uppercase values, which is how Windows
    // defines VK_A through VK_Z.
    HidKey.keyA: 0x41, HidKey.keyB: 0x42, HidKey.keyC: 0x43,
    HidKey.keyD: 0x44, HidKey.keyE: 0x45, HidKey.keyF: 0x46,
    HidKey.keyG: 0x47, HidKey.keyH: 0x48, HidKey.keyI: 0x49,
    HidKey.keyJ: 0x4A, HidKey.keyK: 0x4B, HidKey.keyL: 0x4C,
    HidKey.keyM: 0x4D, HidKey.keyN: 0x4E, HidKey.keyO: 0x4F,
    HidKey.keyP: 0x50, HidKey.keyQ: 0x51, HidKey.keyR: 0x52,
    HidKey.keyS: 0x53, HidKey.keyT: 0x54, HidKey.keyU: 0x55,
    HidKey.keyV: 0x56, HidKey.keyW: 0x57, HidKey.keyX: 0x58,
    HidKey.keyY: 0x59, HidKey.keyZ: 0x5A,

    // Digits likewise map to ASCII.
    HidKey.digit1: 0x31, HidKey.digit2: 0x32, HidKey.digit3: 0x33,
    HidKey.digit4: 0x34, HidKey.digit5: 0x35, HidKey.digit6: 0x36,
    HidKey.digit7: 0x37, HidKey.digit8: 0x38, HidKey.digit9: 0x39,
    HidKey.digit0: 0x30,

    HidKey.enter: 0x0D, // VK_RETURN
    HidKey.escape: 0x1B, // VK_ESCAPE
    HidKey.backspace: 0x08, // VK_BACK
    HidKey.tab: 0x09, // VK_TAB
    HidKey.space: 0x20, // VK_SPACE

    HidKey.minus: 0xBD, // VK_OEM_MINUS
    HidKey.equal: 0xBB, // VK_OEM_PLUS
    HidKey.bracketLeft: 0xDB, // VK_OEM_4
    HidKey.bracketRight: 0xDD, // VK_OEM_6
    HidKey.backslash: 0xDC, // VK_OEM_5
    HidKey.semicolon: 0xBA, // VK_OEM_1
    HidKey.quote: 0xDE, // VK_OEM_7
    HidKey.backquote: 0xC0, // VK_OEM_3
    HidKey.comma: 0xBC, // VK_OEM_COMMA
    HidKey.period: 0xBE, // VK_OEM_PERIOD
    HidKey.slash: 0xBF, // VK_OEM_2
    HidKey.capsLock: 0x14, // VK_CAPITAL
    HidKey.nonUsBackslash: 0xE2, // VK_OEM_102

    HidKey.f1: 0x70, HidKey.f2: 0x71, HidKey.f3: 0x72, HidKey.f4: 0x73,
    HidKey.f5: 0x74, HidKey.f6: 0x75, HidKey.f7: 0x76, HidKey.f8: 0x77,
    HidKey.f9: 0x78, HidKey.f10: 0x79, HidKey.f11: 0x7A, HidKey.f12: 0x7B,
    HidKey.f13: 0x7C, HidKey.f14: 0x7D, HidKey.f15: 0x7E, HidKey.f16: 0x7F,
    HidKey.f17: 0x80, HidKey.f18: 0x81, HidKey.f19: 0x82, HidKey.f20: 0x83,

    HidKey.printScreen: 0x2C, // VK_SNAPSHOT
    HidKey.scrollLock: 0x91, // VK_SCROLL
    HidKey.pause: 0x13, // VK_PAUSE
    HidKey.insert: 0x2D, // VK_INSERT
    HidKey.home: 0x24, // VK_HOME
    HidKey.pageUp: 0x21, // VK_PRIOR
    HidKey.delete: 0x2E, // VK_DELETE
    HidKey.end: 0x23, // VK_END
    HidKey.pageDown: 0x22, // VK_NEXT
    HidKey.arrowRight: 0x27, // VK_RIGHT
    HidKey.arrowLeft: 0x25, // VK_LEFT
    HidKey.arrowDown: 0x28, // VK_DOWN
    HidKey.arrowUp: 0x26, // VK_UP
    HidKey.application: 0x5D, // VK_APPS

    HidKey.numLock: 0x90, // VK_NUMLOCK
    HidKey.numpadDivide: 0x6F, HidKey.numpadMultiply: 0x6A,
    HidKey.numpadSubtract: 0x6D, HidKey.numpadAdd: 0x6B,
    HidKey.numpadEnter: 0x0D,
    HidKey.numpad0: 0x60, HidKey.numpad1: 0x61, HidKey.numpad2: 0x62,
    HidKey.numpad3: 0x63, HidKey.numpad4: 0x64, HidKey.numpad5: 0x65,
    HidKey.numpad6: 0x66, HidKey.numpad7: 0x67, HidKey.numpad8: 0x68,
    HidKey.numpad9: 0x69, HidKey.numpadDecimal: 0x6E,

    HidKey.controlLeft: 0xA2, // VK_LCONTROL
    HidKey.shiftLeft: 0xA0, // VK_LSHIFT
    HidKey.altLeft: 0xA4, // VK_LMENU
    HidKey.metaLeft: 0x5B, // VK_LWIN
    HidKey.controlRight: 0xA3, // VK_RCONTROL
    HidKey.shiftRight: 0xA1, // VK_RSHIFT
    HidKey.altRight: 0xA5, // VK_RMENU
    HidKey.metaRight: 0x5C, // VK_RWIN
  };

  /// Windows virtual keys that require `KEYEVENTF_EXTENDEDKEY`.
  ///
  /// These are the keys that live outside the original 84-key layout and are
  /// distinguished on the wire by an `0xE0` scan-code prefix. Omitting the flag
  /// is a subtle bug: the arrow keys still work, but right Alt stops behaving
  /// as AltGr and Home/End get confused with their numpad twins when Num Lock
  /// is off.
  static const Set<int> windowsExtendedKeys = <int>{
    0x2D, 0x2E, 0x24, 0x23, 0x21, 0x22, // Insert Delete Home End PgUp PgDn
    0x25, 0x26, 0x27, 0x28, // Arrows
    0x90, 0x6F, 0x0D, // NumLock, numpad divide, numpad enter
    0xA3, 0xA5, // Right Control, Right Alt
    0x5B, 0x5C, 0x5D, // Left Win, Right Win, Apps
    0x2C, // PrintScreen
  };

  /// HID usage to macOS `CGKeyCode` (ANSI virtual key codes from
  /// `Carbon/HIToolbox/Events.h`).
  ///
  /// These identify physical positions on an ANSI keyboard. AppKit matches
  /// command-key equivalents against the current layout, so Cmd+`kVK_ANSI_C`
  /// still means Copy on AZERTY — the same practical result as the Windows
  /// virtual-key path, reached differently.
  static const Map<int, int> hidToMacKeyCode = <int, int>{
    HidKey.keyA: 0x00, HidKey.keyS: 0x01, HidKey.keyD: 0x02,
    HidKey.keyF: 0x03, HidKey.keyH: 0x04, HidKey.keyG: 0x05,
    HidKey.keyZ: 0x06, HidKey.keyX: 0x07, HidKey.keyC: 0x08,
    HidKey.keyV: 0x09, HidKey.keyB: 0x0B, HidKey.keyQ: 0x0C,
    HidKey.keyW: 0x0D, HidKey.keyE: 0x0E, HidKey.keyR: 0x0F,
    HidKey.keyY: 0x10, HidKey.keyT: 0x11, HidKey.keyO: 0x1F,
    HidKey.keyU: 0x20, HidKey.keyI: 0x22, HidKey.keyP: 0x23,
    HidKey.keyL: 0x25, HidKey.keyJ: 0x26, HidKey.keyK: 0x28,
    HidKey.keyN: 0x2D, HidKey.keyM: 0x2E,

    HidKey.digit1: 0x12, HidKey.digit2: 0x13, HidKey.digit3: 0x14,
    HidKey.digit4: 0x15, HidKey.digit6: 0x16, HidKey.digit5: 0x17,
    HidKey.digit9: 0x19, HidKey.digit7: 0x1A, HidKey.digit8: 0x1C,
    HidKey.digit0: 0x1D,

    HidKey.equal: 0x18,
    HidKey.minus: 0x1B,
    HidKey.bracketRight: 0x1E,
    HidKey.bracketLeft: 0x21,
    HidKey.quote: 0x27,
    HidKey.semicolon: 0x29,
    HidKey.backslash: 0x2A,
    HidKey.comma: 0x2B,
    HidKey.slash: 0x2C,
    HidKey.period: 0x2F,
    HidKey.backquote: 0x32,
    HidKey.nonUsBackslash: 0x0A,

    HidKey.enter: 0x24,
    HidKey.tab: 0x30,
    HidKey.space: 0x31,
    HidKey.backspace: 0x33,
    HidKey.escape: 0x35,
    HidKey.capsLock: 0x39,

    HidKey.f1: 0x7A, HidKey.f2: 0x78, HidKey.f3: 0x63, HidKey.f4: 0x76,
    HidKey.f5: 0x60, HidKey.f6: 0x61, HidKey.f7: 0x62, HidKey.f8: 0x64,
    HidKey.f9: 0x65, HidKey.f10: 0x6D, HidKey.f11: 0x67, HidKey.f12: 0x6F,
    HidKey.f13: 0x69, HidKey.f14: 0x6B, HidKey.f15: 0x71, HidKey.f16: 0x6A,
    HidKey.f17: 0x40, HidKey.f18: 0x4F, HidKey.f19: 0x50, HidKey.f20: 0x5A,

    HidKey.home: 0x73,
    HidKey.pageUp: 0x74,
    HidKey.delete: 0x75,
    HidKey.end: 0x77,
    HidKey.pageDown: 0x79,
    HidKey.arrowLeft: 0x7B,
    HidKey.arrowRight: 0x7C,
    HidKey.arrowDown: 0x7D,
    HidKey.arrowUp: 0x7E,
    HidKey.insert: 0x72, // Help on Apple keyboards

    HidKey.numpadDecimal: 0x41,
    HidKey.numpadMultiply: 0x43,
    HidKey.numpadAdd: 0x45,
    HidKey.numLock: 0x47, // Clear on Apple keyboards
    HidKey.numpadDivide: 0x4B,
    HidKey.numpadEnter: 0x4C,
    HidKey.numpadSubtract: 0x4E,
    HidKey.numpadEqual: 0x51,
    HidKey.numpad0: 0x52, HidKey.numpad1: 0x53, HidKey.numpad2: 0x54,
    HidKey.numpad3: 0x55, HidKey.numpad4: 0x56, HidKey.numpad5: 0x57,
    HidKey.numpad6: 0x58, HidKey.numpad7: 0x59, HidKey.numpad8: 0x5B,
    HidKey.numpad9: 0x5C,

    HidKey.controlLeft: 0x3B,
    HidKey.shiftLeft: 0x38,
    HidKey.altLeft: 0x3A,
    HidKey.metaLeft: 0x37,
    HidKey.controlRight: 0x3E,
    HidKey.shiftRight: 0x3C,
    HidKey.altRight: 0x3D,
    HidKey.metaRight: 0x36,
  };

  /// `CGEventFlags` bits for modifier state on macOS.
  static const int macFlagShift = 0x00020000;
  static const int macFlagControl = 0x00040000;
  static const int macFlagOption = 0x00080000;
  static const int macFlagCommand = 0x00100000;

  /// Converts protocol [Modifiers] to a `CGEventFlags` mask.
  static int macFlagsFor(Modifiers modifiers) =>
      (modifiers.hasShift ? macFlagShift : 0) |
      (modifiers.hasControl ? macFlagControl : 0) |
      (modifiers.hasAlt ? macFlagOption : 0) |
      (modifiers.hasMeta ? macFlagCommand : 0);

  /// Resolves a platform-neutral shortcut into concrete key events.
  ///
  /// This is where "Copy" becomes Ctrl+C or Cmd+C. Keeping the mapping on the
  /// desktop — where the OS is known — means the phone ships one Copy button
  /// rather than a per-platform branch, and adding a shortcut needs no mobile
  /// release.
  static (Modifiers, int)? resolveShortcut(
    NamedShortcut shortcut,
    PlatformKind platform,
  ) {
    final primary = platform.usesCommandModifier
        ? Modifiers.leftMeta
        : Modifiers.leftControl;

    (Modifiers, int) combo(int mask, int usage) => (Modifiers(mask), usage);

    return switch (shortcut) {
      NamedShortcut.copy => combo(primary, HidKey.keyC),
      NamedShortcut.paste => combo(primary, HidKey.keyV),
      NamedShortcut.cut => combo(primary, HidKey.keyX),
      NamedShortcut.undo => combo(primary, HidKey.keyZ),
      NamedShortcut.redo => platform.usesCommandModifier
          ? combo(primary | Modifiers.leftShift, HidKey.keyZ)
          : combo(primary, HidKey.keyY),
      NamedShortcut.selectAll => combo(primary, HidKey.keyA),
      NamedShortcut.save => combo(primary, HidKey.keyS),
      NamedShortcut.find => combo(primary, HidKey.keyF),
      NamedShortcut.newWindow => combo(primary, HidKey.keyN),
      NamedShortcut.closeWindow => platform.usesCommandModifier
          ? combo(primary | Modifiers.leftShift, HidKey.keyW)
          : combo(Modifiers.leftAlt, HidKey.f4),
      NamedShortcut.closeTab => combo(primary, HidKey.keyW),
      NamedShortcut.newTab => combo(primary, HidKey.keyT),
      NamedShortcut.nextTab => combo(
          primary | Modifiers.leftAlt,
          HidKey.arrowRight,
        ),
      NamedShortcut.previousTab => combo(
          primary | Modifiers.leftAlt,
          HidKey.arrowLeft,
        ),
      NamedShortcut.refresh => combo(primary, HidKey.keyR),
      NamedShortcut.quitApplication => platform.usesCommandModifier
          ? combo(primary, HidKey.keyQ)
          : combo(Modifiers.leftAlt, HidKey.f4),

      // Task Manager is Ctrl+Shift+Esc on Windows. macOS has no keyboard
      // equivalent for Activity Monitor, so the desktop launches it instead —
      // returning null routes this to the application launcher.
      NamedShortcut.taskManager => platform.usesCommandModifier
          ? null
          : combo(
              Modifiers.leftControl | Modifiers.leftShift,
              HidKey.escape,
            ),

      NamedShortcut.switchApplication => platform.usesCommandModifier
          ? combo(Modifiers.leftMeta, HidKey.tab)
          : combo(Modifiers.leftAlt, HidKey.tab),
      NamedShortcut.showDesktop => platform.usesCommandModifier
          ? combo(Modifiers.leftMeta, HidKey.f3)
          : combo(Modifiers.leftMeta, HidKey.keyD),
      NamedShortcut.lockScreen => platform.usesCommandModifier
          ? combo(Modifiers.leftControl | Modifiers.leftMeta, HidKey.keyQ)
          : combo(Modifiers.leftMeta, HidKey.keyL),
      NamedShortcut.screenshot => platform.usesCommandModifier
          ? combo(primary | Modifiers.leftShift, HidKey.digit3)
          : combo(Modifiers.leftMeta | Modifiers.leftShift, HidKey.keyS),
      NamedShortcut.screenshotRegion => platform.usesCommandModifier
          ? combo(primary | Modifiers.leftShift, HidKey.digit4)
          : combo(Modifiers.leftMeta | Modifiers.leftShift, HidKey.keyS),
      NamedShortcut.zoomIn => combo(primary, HidKey.equal),
      NamedShortcut.zoomOut => combo(primary, HidKey.minus),
      NamedShortcut.zoomReset => combo(primary, HidKey.digit0),
      NamedShortcut.fullscreen => platform.usesCommandModifier
          ? combo(primary | Modifiers.leftControl, HidKey.keyF)
          : combo(0, HidKey.f11),

      NamedShortcut.unrecognised => null,
    };
  }
}
