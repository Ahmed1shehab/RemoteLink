import 'package:meta/meta.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';

/// USB HID Keyboard/Keypad usage IDs (Usage Page 0x07).
///
/// These are the protocol's canonical key identities. Sending HID usages rather
/// than Windows virtual-key codes or macOS `CGKeyCode`s matters for three
/// reasons:
///
/// 1. **Neither platform's codes are a superset of the other.** Picking one
///    would force a lossy translation on the sender, which cannot know the
///    receiver's layout or even its OS until the handshake completes.
/// 2. **It is already the hardware's language**, so both backends translate
///    with a static table and no heuristics.
/// 3. **It keeps the sender dumb.** The phone reports which key was pressed;
///    deciding what that means on this particular machine is the desktop's job,
///    where the layout actually lives.
///
/// Each backend maps a usage to whatever its OS treats as the identity of that
/// key for shortcut purposes — a Windows virtual-key code, an ANSI `CGKeyCode`
/// on macOS. Both resolve shortcuts layout-independently, so Ctrl+C is Copy on
/// a French keyboard as well as a US one.
///
/// Text that depends on the layout at all — accented characters, emoji, CJK
/// composed in the phone's own IME — does not travel this path. It goes through
/// `TextInput`, which injects Unicode directly and bypasses keycodes entirely.
abstract final class HidKey {
  // Letters.
  static const int keyA = 0x04;
  static const int keyB = 0x05;
  static const int keyC = 0x06;
  static const int keyD = 0x07;
  static const int keyE = 0x08;
  static const int keyF = 0x09;
  static const int keyG = 0x0A;
  static const int keyH = 0x0B;
  static const int keyI = 0x0C;
  static const int keyJ = 0x0D;
  static const int keyK = 0x0E;
  static const int keyL = 0x0F;
  static const int keyM = 0x10;
  static const int keyN = 0x11;
  static const int keyO = 0x12;
  static const int keyP = 0x13;
  static const int keyQ = 0x14;
  static const int keyR = 0x15;
  static const int keyS = 0x16;
  static const int keyT = 0x17;
  static const int keyU = 0x18;
  static const int keyV = 0x19;
  static const int keyW = 0x1A;
  static const int keyX = 0x1B;
  static const int keyY = 0x1C;
  static const int keyZ = 0x1D;

  // Digit row.
  static const int digit1 = 0x1E;
  static const int digit2 = 0x1F;
  static const int digit3 = 0x20;
  static const int digit4 = 0x21;
  static const int digit5 = 0x22;
  static const int digit6 = 0x23;
  static const int digit7 = 0x24;
  static const int digit8 = 0x25;
  static const int digit9 = 0x26;
  static const int digit0 = 0x27;

  // Control and whitespace.
  static const int enter = 0x28;
  static const int escape = 0x29;
  static const int backspace = 0x2A;
  static const int tab = 0x2B;
  static const int space = 0x2C;

  // Punctuation.
  static const int minus = 0x2D;
  static const int equal = 0x2E;
  static const int bracketLeft = 0x2F;
  static const int bracketRight = 0x30;
  static const int backslash = 0x31;
  static const int semicolon = 0x33;
  static const int quote = 0x34;
  static const int backquote = 0x35;
  static const int comma = 0x36;
  static const int period = 0x37;
  static const int slash = 0x38;
  static const int capsLock = 0x39;

  // Function row.
  static const int f1 = 0x3A;
  static const int f2 = 0x3B;
  static const int f3 = 0x3C;
  static const int f4 = 0x3D;
  static const int f5 = 0x3E;
  static const int f6 = 0x3F;
  static const int f7 = 0x40;
  static const int f8 = 0x41;
  static const int f9 = 0x42;
  static const int f10 = 0x43;
  static const int f11 = 0x44;
  static const int f12 = 0x45;
  static const int f13 = 0x68;
  static const int f14 = 0x69;
  static const int f15 = 0x6A;
  static const int f16 = 0x6B;
  static const int f17 = 0x6C;
  static const int f18 = 0x6D;
  static const int f19 = 0x6E;
  static const int f20 = 0x6F;

  // Navigation cluster.
  static const int printScreen = 0x46;
  static const int scrollLock = 0x47;
  static const int pause = 0x48;
  static const int insert = 0x49;
  static const int home = 0x4A;
  static const int pageUp = 0x4B;
  static const int delete = 0x4C;
  static const int end = 0x4D;
  static const int pageDown = 0x4E;
  static const int arrowRight = 0x4F;
  static const int arrowLeft = 0x50;
  static const int arrowDown = 0x51;
  static const int arrowUp = 0x52;

  // Numeric keypad.
  static const int numLock = 0x53;
  static const int numpadDivide = 0x54;
  static const int numpadMultiply = 0x55;
  static const int numpadSubtract = 0x56;
  static const int numpadAdd = 0x57;
  static const int numpadEnter = 0x58;
  static const int numpad1 = 0x59;
  static const int numpad2 = 0x5A;
  static const int numpad3 = 0x5B;
  static const int numpad4 = 0x5C;
  static const int numpad5 = 0x5D;
  static const int numpad6 = 0x5E;
  static const int numpad7 = 0x5F;
  static const int numpad8 = 0x60;
  static const int numpad9 = 0x61;
  static const int numpad0 = 0x62;
  static const int numpadDecimal = 0x63;

  /// The extra key present on ISO but not ANSI keyboards.
  static const int nonUsBackslash = 0x64;

  /// Menu / context-menu key.
  static const int application = 0x65;

  static const int power = 0x66;
  static const int numpadEqual = 0x67;

  // Editing keys, present on Sun and some full-size layouts.
  static const int menu = 0x76;
  static const int undo = 0x7A;
  static const int cut = 0x7B;
  static const int copy = 0x7C;
  static const int paste = 0x7D;
  static const int find = 0x7E;

  // Modifiers.
  static const int controlLeft = 0xE0;
  static const int shiftLeft = 0xE1;
  static const int altLeft = 0xE2;

  /// Windows key on PC keyboards, Command on Apple keyboards.
  static const int metaLeft = 0xE3;

  static const int controlRight = 0xE4;
  static const int shiftRight = 0xE5;

  /// Right Alt. On many European layouts this is AltGr and produces different
  /// characters — which is exactly why it is a distinct usage from [altLeft].
  static const int altRight = 0xE6;

  static const int metaRight = 0xE7;

  /// True when [usage] is one of the eight modifier keys.
  static bool isModifier(int usage) => usage >= controlLeft && usage <= metaRight;

  /// The [Modifiers] bit corresponding to a modifier [usage], or `0`.
  static int modifierBit(int usage) => switch (usage) {
        controlLeft => Modifiers.leftControl,
        shiftLeft => Modifiers.leftShift,
        altLeft => Modifiers.leftAlt,
        metaLeft => Modifiers.leftMeta,
        controlRight => Modifiers.rightControl,
        shiftRight => Modifiers.rightShift,
        altRight => Modifiers.rightAlt,
        metaRight => Modifiers.rightMeta,
        _ => 0,
      };
}

/// Modifier state as a bitmask.
///
/// Bit order matches the HID keyboard boot-protocol modifier byte, so a report
/// from a physical keyboard maps across with no shifting.
extension type const Modifiers(int bits) {
  static const Modifiers none = Modifiers(0);

  static const int leftControl = 1 << 0;
  static const int leftShift = 1 << 1;
  static const int leftAlt = 1 << 2;
  static const int leftMeta = 1 << 3;
  static const int rightControl = 1 << 4;
  static const int rightShift = 1 << 5;
  static const int rightAlt = 1 << 6;
  static const int rightMeta = 1 << 7;

  static const int anyControl = leftControl | rightControl;
  static const int anyShift = leftShift | rightShift;
  static const int anyAlt = leftAlt | rightAlt;
  static const int anyMeta = leftMeta | rightMeta;

  bool get hasControl => bits & anyControl != 0;
  bool get hasShift => bits & anyShift != 0;
  bool get hasAlt => bits & anyAlt != 0;
  bool get hasMeta => bits & anyMeta != 0;
  bool get isEmpty => bits == 0;

  bool has(int mask) => bits & mask != 0;

  Modifiers plus(int mask) => Modifiers(bits | mask);
  Modifiers minus(int mask) => Modifiers(bits & ~mask);

  /// The HID usages that must be held to realise this state.
  List<int> toUsages() => <int>[
        if (has(leftControl)) HidKey.controlLeft,
        if (has(leftShift)) HidKey.shiftLeft,
        if (has(leftAlt)) HidKey.altLeft,
        if (has(leftMeta)) HidKey.metaLeft,
        if (has(rightControl)) HidKey.controlRight,
        if (has(rightShift)) HidKey.shiftRight,
        if (has(rightAlt)) HidKey.altRight,
        if (has(rightMeta)) HidKey.metaRight,
      ];
}

/// A key press or release.
///
/// Press and release are separate so that held-key behaviour (arrow-key repeat,
/// holding Shift while selecting, WASD in a game) works. OS auto-repeat is
/// suppressed by [isRepeat]: the desktop injects the repeat itself, avoiding a
/// packet per repeat over the network.
@immutable
final class KeyEvent extends Message {
  const KeyEvent({
    required this.hidUsage,
    required this.pressed,
    required this.modifiers,
    this.isRepeat = false,
  });

  /// USB HID usage ID from [HidKey].
  final int hidUsage;

  final bool pressed;

  /// Absolute modifier state at the time of the event.
  ///
  /// Sent as an absolute snapshot, not a delta, so a lost modifier release
  /// cannot leave the desktop with a phantom stuck Shift. The desktop
  /// reconciles its state to this value before injecting the key.
  final Modifiers modifiers;

  final bool isRepeat;

  @override
  MessageType get type => MessageType.keyEvent;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint16(hidUsage)
      ..writeUint8(modifiers.bits)
      ..writeUint8((pressed ? 1 : 0) | (isRepeat ? 2 : 0));
  }

  static KeyEvent readFrom(ByteReader reader) {
    final hidUsage = reader.readUint16();
    final modifiers = Modifiers(reader.readUint8());
    final flags = reader.readUint8();
    return KeyEvent(
      hidUsage: hidUsage,
      pressed: flags & 1 != 0,
      modifiers: modifiers,
      isRepeat: flags & 2 != 0,
    );
  }

  @override
  String toString() => 'KeyEvent(0x${hidUsage.toRadixString(16)}, '
      '${pressed ? 'down' : 'up'}, mods=0x${modifiers.bits.toRadixString(16)})';
}

/// Direct Unicode text injection.
///
/// This is how emoji, accented characters, CJK, and anything else the user
/// composed on the phone's own IME reach the desktop. It sidesteps keycodes and
/// keyboard layouts entirely: Windows injects the UTF-16 units with
/// `KEYEVENTF_UNICODE`, macOS with `CGEventKeyboardSetUnicodeString`.
///
/// The trade-off is that applications see synthetic characters rather than key
/// presses, so games and shortcut handlers will not react. That is why ordinary
/// typing still goes through `KeyEvent` and only non-ASCII text takes this path.
@immutable
final class TextInput extends Message {
  const TextInput(this.text);

  final String text;

  @override
  MessageType get type => MessageType.textInput;

  @override
  void writeTo(ByteWriter writer) => writer.writeString(text);

  static TextInput readFrom(ByteReader reader) =>
      TextInput(reader.readString(maxLength: 64 * 1024));

  @override
  String toString() => 'TextInput(${text.length} chars)';
}

/// Shortcuts named by intent rather than by keystroke.
///
/// "Copy" is Ctrl+C on Windows and Cmd+C on macOS. Sending the *intent* lets
/// the desktop resolve it correctly, so the phone's Copy button works on both
/// platforms with no branching in the mobile app.
enum NamedShortcut {
  /// A shortcut code this build does not know.
  ///
  /// Present so that a newer phone sending a shortcut we have never heard of
  /// decodes cleanly and is dropped by the dispatcher, rather than failing the
  /// frame and tearing down the session.
  unrecognised(0),

  copy(1),
  paste(2),
  cut(3),
  undo(4),
  redo(5),
  selectAll(6),
  save(7),
  find(8),
  newWindow(9),
  closeWindow(10),
  closeTab(11),
  newTab(12),
  nextTab(13),
  previousTab(14),
  refresh(15),
  quitApplication(16),

  /// Task Manager on Windows, Activity Monitor on macOS.
  taskManager(17),

  /// Alt+Tab / Cmd+Tab.
  switchApplication(18),

  /// Show desktop / Mission Control.
  showDesktop(19),

  /// Lock the screen.
  lockScreen(20),

  screenshot(21),
  screenshotRegion(22),
  zoomIn(23),
  zoomOut(24),
  zoomReset(25),
  fullscreen(26);

  const NamedShortcut(this.wireValue);

  final int wireValue;

  static NamedShortcut fromWire(int value) => values.firstWhere(
        (shortcut) => shortcut.wireValue == value,
        orElse: () => NamedShortcut.unrecognised,
      );
}

/// Requests a platform-resolved shortcut.
@immutable
final class NamedShortcutMessage extends Message {
  const NamedShortcutMessage(this.shortcut);

  final NamedShortcut shortcut;

  @override
  MessageType get type => MessageType.namedShortcut;

  @override
  void writeTo(ByteWriter writer) => writer.writeVarUint(shortcut.wireValue);

  static NamedShortcutMessage readFrom(ByteReader reader) =>
      NamedShortcutMessage(NamedShortcut.fromWire(reader.readVarUint()));
}

/// Absolute modifier resynchronisation.
///
/// Sent when the phone's keyboard view loses focus or the app is backgrounded.
/// Without it, backgrounding while holding Shift would leave Shift latched on
/// the desktop until the user noticed and pressed it again.
@immutable
final class ModifierStateMessage extends Message {
  const ModifierStateMessage(this.modifiers);

  final Modifiers modifiers;

  @override
  MessageType get type => MessageType.modifierState;

  @override
  void writeTo(ByteWriter writer) => writer.writeUint8(modifiers.bits);

  static ModifierStateMessage readFrom(ByteReader reader) =>
      ModifierStateMessage(Modifiers(reader.readUint8()));
}
