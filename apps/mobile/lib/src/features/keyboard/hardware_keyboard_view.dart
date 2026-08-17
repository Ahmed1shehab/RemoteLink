import 'package:flutter/material.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart' as proto;

import '../../app/theme.dart';

/// What a key does when pressed.
enum KeyCapKind {
  /// Sends a HID usage: press, release.
  normal,

  /// Toggles a modifier that is applied to subsequent keys.
  modifier,

  /// Hands over to the phone's own keyboard, for text and emoji.
  switchToText,
}

/// One key on the rendered keyboard.
@immutable
final class KeyCap {
  const KeyCap(
    this.label, {
    this.usage,
    this.modifierBit,
    this.kind = KeyCapKind.normal,
    this.flex = 1,
    this.spokenLabel,
  });

  /// Modifier key: label plus the bit it toggles.
  const KeyCap.modifier(
    this.label,
    this.modifierBit, {
    this.flex = 1,
    this.spokenLabel,
  })  : usage = null,
        kind = KeyCapKind.modifier;

  final String label;

  /// Overrides what a screen reader announces, where [label] cannot carry it.
  ///
  /// Left null by every current cap: [semanticLabel] resolves them all from the
  /// printed label, so a new key cannot be added without one.
  final String? spokenLabel;

  /// USB HID usage from [proto.HidKey], for normal keys.
  final int? usage;

  /// Bit from [proto.Modifiers], for modifier keys.
  final int? modifierBit;

  final KeyCapKind kind;

  /// Relative width. A spacebar is `flex: 6`, a letter `flex: 1`.
  final double flex;

  /// What a screen reader announces for this key.
  ///
  /// A rendered keyboard is the worst case for icon-only controls, and this one
  /// was entirely unlabelled: the caps are drawn with the glyphs a real
  /// keyboard is printed with, and those are exactly the characters a screen
  /// reader cannot say. '⌘' is announced as "place of interest sign", '⌫' as
  /// "erase to the left", '◀' as "black left-pointing triangle" — or, with
  /// punctuation reading off, as nothing at all, which is worse, because the
  /// key then appears not to exist.
  ///
  /// So the printed label and the spoken label are separate strings by design.
  /// Anything already a word speaks for itself; everything below is a glyph or
  /// an abbreviation that does not.
  String get semanticLabel => spokenLabel ?? spokenKeyLabel(label);
}

/// The spoken form of a printed key label.
String spokenKeyLabel(String label) => _spokenKeyLabels[label] ?? label;

const Map<String, String> _spokenKeyLabels = <String, String>{
  // Glyphs. Each is a real Unicode character with a real Unicode name, and
  // none of those names is the name of the key.
  '⌫': 'Backspace',
  '⌨': 'Switch to the phone keyboard',
  '◀': 'Left arrow',
  '▲': 'Up arrow',
  '▼': 'Down arrow',
  '▶': 'Right arrow',
  '⌘': 'Command',
  '⌥': 'Option',
  '⌃': 'Control',
  ' ': 'Space',
  // Abbreviations. Read aloud, "esc" and "del" are noises.
  'esc': 'Escape',
  'del': 'Delete',
  'tab': 'Tab',
  'caps': 'Caps lock',
  'return': 'Return',
  'shift': 'Shift',
  'ctrl': 'Control',
  'alt': 'Alt',
  'alt gr': 'Alt Gr',
  'CMD': 'Command',
  'WIN': 'Windows',
  'META': 'Meta',
  // Punctuation. Announced inconsistently between platforms and voices, and
  // silently by several when punctuation reading is off — the iOS default.
  '`': 'Backtick',
  '-': 'Minus',
  '=': 'Equals',
  '[': 'Left bracket',
  ']': 'Right bracket',
  r'\': 'Backslash',
  ';': 'Semicolon',
  "'": 'Apostrophe',
  ',': 'Comma',
  '.': 'Full stop',
  '/': 'Slash',
};

/// A rendered hardware keyboard.
///
/// ## Why this exists when the phone already has a keyboard
///
/// They solve different problems and neither replaces the other.
///
/// The phone's own keyboard is better for *text*: it has the user's languages,
/// their IME, emoji, and dictation, and RemoteLink forwards what it produces as
/// Unicode. But it cannot express Ctrl, Alt, F5, or Escape, and it autocorrects.
///
/// This keyboard is better for *control*: every cap is a real HID usage, so
/// Ctrl+Shift+Esc, Alt+F4, and WASD all work, and nothing is rewritten on the
/// way. It is the only way to drive a game, a terminal, or an IDE.
///
/// ## Platform adaptation
///
/// The modifier next to Alt is Command on macOS and Windows elsewhere, and
/// AltGr only exists on PC layouts. The label comes from the *connected
/// computer's* platform, not the phone's — an iPhone driving a Windows PC must
/// show WIN. That is why the desktop sends its `DeviceInfoMessage` on connect.
class HardwareKeyboardView extends StatelessWidget {
  const HardwareKeyboardView({
    required this.platform,
    required this.modifiers,
    required this.capsLock,
    required this.enabled,
    required this.onKey,
    required this.onModifier,
    required this.onSwitchToText,
    super.key,
  });

  final PlatformKind platform;
  final proto.Modifiers modifiers;

  final bool capsLock;
  final bool enabled;

  final void Function(int usage) onKey;
  final void Function(int bit) onModifier;

  /// Hands control to the phone's own keyboard.
  final VoidCallback onSwitchToText;

  /// The Windows/Command key's label for the machine being controlled.
  ///
  /// `unknown` gets its own label rather than falling in with Windows. Treating
  /// "not told yet" as "Windows" is a guess that is wrong half the time and
  /// looks like a bug rather than a gap — which is exactly how it was reported.
  ///
  /// The key still *works* either way: it sends `leftMeta` regardless, and the
  /// desktop maps that to whatever its OS calls it. Only the label is at stake,
  /// so being honest costs nothing.
  String get _metaLabel => switch (platform) {
        PlatformKind.macos => 'CMD',
        PlatformKind.windows || PlatformKind.linux => 'WIN',
        _ => 'META',
      };

  /// True when the layout should follow PC conventions.
  bool get _isPcLayout =>
      platform == PlatformKind.windows || platform == PlatformKind.linux;

  /// The ANSI layout, in keyboard units.
  ///
  /// ## Why every row totals exactly 15 units
  ///
  /// The stagger on a real keyboard is not decoration — it comes from the
  /// leading key of each row being wider than the last: Tab is 1.5u, Caps 1.75u,
  /// Shift 2.25u. Because every row sums to the same total, those widths push
  /// each row right by a fixed amount and the columns line up the way fingers
  /// expect.
  ///
  /// Get the totals wrong and the rows stretch independently, which is what the
  /// first version did: a uniform grid that looked like a keyboard from a
  /// distance and felt wrong under the thumb.
  List<List<KeyCap>> _rows() => <List<KeyCap>>[
        // Function row. Always present rather than hidden behind Fn — a real
        // keyboard has both, and Escape in particular is needed too often to
        // be a layer away.
        <KeyCap>[
          const KeyCap('esc', usage: proto.HidKey.escape),
          const KeyCap('F1', usage: proto.HidKey.f1),
          const KeyCap('F2', usage: proto.HidKey.f2),
          const KeyCap('F3', usage: proto.HidKey.f3),
          const KeyCap('F4', usage: proto.HidKey.f4),
          const KeyCap('F5', usage: proto.HidKey.f5),
          const KeyCap('F6', usage: proto.HidKey.f6),
          const KeyCap('F7', usage: proto.HidKey.f7),
          const KeyCap('F8', usage: proto.HidKey.f8),
          const KeyCap('F9', usage: proto.HidKey.f9),
          const KeyCap('F10', usage: proto.HidKey.f10),
          const KeyCap('F11', usage: proto.HidKey.f11),
          const KeyCap('F12', usage: proto.HidKey.f12),
          const KeyCap('del', usage: proto.HidKey.delete, flex: 2),
        ],
        // 13 × 1u + 2u backspace.
        <KeyCap>[
          const KeyCap('`', usage: proto.HidKey.backquote),
          const KeyCap('1', usage: proto.HidKey.digit1),
          const KeyCap('2', usage: proto.HidKey.digit2),
          const KeyCap('3', usage: proto.HidKey.digit3),
          const KeyCap('4', usage: proto.HidKey.digit4),
          const KeyCap('5', usage: proto.HidKey.digit5),
          const KeyCap('6', usage: proto.HidKey.digit6),
          const KeyCap('7', usage: proto.HidKey.digit7),
          const KeyCap('8', usage: proto.HidKey.digit8),
          const KeyCap('9', usage: proto.HidKey.digit9),
          const KeyCap('0', usage: proto.HidKey.digit0),
          const KeyCap('-', usage: proto.HidKey.minus),
          const KeyCap('=', usage: proto.HidKey.equal),
          const KeyCap('⌫', usage: proto.HidKey.backspace, flex: 2),
        ],
        // 1.5u Tab + 12 × 1u + 1.5u backslash.
        <KeyCap>[
          const KeyCap('tab', usage: proto.HidKey.tab, flex: 1.5),
          const KeyCap('Q', usage: proto.HidKey.keyQ),
          const KeyCap('W', usage: proto.HidKey.keyW),
          const KeyCap('E', usage: proto.HidKey.keyE),
          const KeyCap('R', usage: proto.HidKey.keyR),
          const KeyCap('T', usage: proto.HidKey.keyT),
          const KeyCap('Y', usage: proto.HidKey.keyY),
          const KeyCap('U', usage: proto.HidKey.keyU),
          const KeyCap('I', usage: proto.HidKey.keyI),
          const KeyCap('O', usage: proto.HidKey.keyO),
          const KeyCap('P', usage: proto.HidKey.keyP),
          const KeyCap('[', usage: proto.HidKey.bracketLeft),
          const KeyCap(']', usage: proto.HidKey.bracketRight),
          const KeyCap(r'\', usage: proto.HidKey.backslash, flex: 1.5),
        ],
        // 1.75u Caps + 11 × 1u + 2.25u Enter.
        <KeyCap>[
          const KeyCap('caps', usage: proto.HidKey.capsLock, flex: 1.75),
          const KeyCap('A', usage: proto.HidKey.keyA),
          const KeyCap('S', usage: proto.HidKey.keyS),
          const KeyCap('D', usage: proto.HidKey.keyD),
          const KeyCap('F', usage: proto.HidKey.keyF),
          const KeyCap('G', usage: proto.HidKey.keyG),
          const KeyCap('H', usage: proto.HidKey.keyH),
          const KeyCap('J', usage: proto.HidKey.keyJ),
          const KeyCap('K', usage: proto.HidKey.keyK),
          const KeyCap('L', usage: proto.HidKey.keyL),
          const KeyCap(';', usage: proto.HidKey.semicolon),
          const KeyCap("'", usage: proto.HidKey.quote),
          const KeyCap('return', usage: proto.HidKey.enter, flex: 2.25),
        ],
        // 2.25u Shift + 10 × 1u + 2.75u Shift.
        <KeyCap>[
          const KeyCap.modifier('shift', proto.Modifiers.leftShift, flex: 2.25),
          const KeyCap('Z', usage: proto.HidKey.keyZ),
          const KeyCap('X', usage: proto.HidKey.keyX),
          const KeyCap('C', usage: proto.HidKey.keyC),
          const KeyCap('V', usage: proto.HidKey.keyV),
          const KeyCap('B', usage: proto.HidKey.keyB),
          const KeyCap('N', usage: proto.HidKey.keyN),
          const KeyCap('M', usage: proto.HidKey.keyM),
          const KeyCap(',', usage: proto.HidKey.comma),
          const KeyCap('.', usage: proto.HidKey.period),
          const KeyCap('/', usage: proto.HidKey.slash),
          const KeyCap.modifier(
            'shift',
            proto.Modifiers.rightShift,
            flex: 2.75,
          ),
        ],
        _bottomRow(),
      ];

  /// The modifier row, in the order the target platform actually uses.
  ///
  /// This is the part that was wrong and is worth stating plainly: macOS runs
  /// `fn ⌃ ⌥ ⌘ space`, with Command *adjacent to* the spacebar and Option
  /// outside it. Windows runs `Ctrl Win Alt space`, where the meta key sits in
  /// the middle. Using one order for both puts the most-pressed modifier under
  /// the wrong thumb on one of the two platforms.
  List<KeyCap> _bottomRow() {
    // Shared tail: the arrow cluster, as on a laptop.
    const arrows = <KeyCap>[
      KeyCap('◀', usage: proto.HidKey.arrowLeft, flex: 0.875),
      KeyCap('▲', usage: proto.HidKey.arrowUp, flex: 0.875),
      KeyCap('▼', usage: proto.HidKey.arrowDown, flex: 0.875),
      KeyCap('▶', usage: proto.HidKey.arrowRight, flex: 0.875),
    ];

    if (_isPcLayout) {
      // 1.25 × 3 + 5.25 + 1.25 × 2 + 3.5 = 15u
      return <KeyCap>[
        const KeyCap.modifier('ctrl', proto.Modifiers.leftControl, flex: 1.25),
        KeyCap.modifier(_metaLabel, proto.Modifiers.leftMeta, flex: 1.25),
        const KeyCap.modifier('alt', proto.Modifiers.leftAlt, flex: 1.25),
        const KeyCap(' ', usage: proto.HidKey.space, flex: 5.25),
        const KeyCap.modifier('alt gr', proto.Modifiers.rightAlt, flex: 1.25),
        const KeyCap('⌨', kind: KeyCapKind.switchToText, flex: 1.25),
        ...arrows,
      ];
    }

    // macOS and unknown: 1 + 1 + 1 + 1.25 + 5 + 1.25 + 1 + 3.5 = 15u
    final option = platform == PlatformKind.macos ? '⌥' : 'alt';
    return <KeyCap>[
      // The globe key's slot on a modern Mac keyboard, doing the job it does
      // there: switch to a different keyboard.
      const KeyCap('⌨', kind: KeyCapKind.switchToText),
      const KeyCap.modifier('⌃', proto.Modifiers.leftControl),
      KeyCap.modifier(option, proto.Modifiers.leftAlt),
      KeyCap.modifier(
        platform == PlatformKind.macos ? '⌘' : _metaLabel,
        proto.Modifiers.leftMeta,
        flex: 1.25,
      ),
      const KeyCap(' ', usage: proto.HidKey.space, flex: 5),
      KeyCap.modifier(
        platform == PlatformKind.macos ? '⌘' : _metaLabel,
        proto.Modifiers.rightMeta,
        flex: 1.25,
      ),
      KeyCap.modifier(option, proto.Modifiers.rightAlt),
      ...arrows,
    ];
  }

  bool _isActive(KeyCap cap) => switch (cap.kind) {
        KeyCapKind.modifier =>
          cap.modifierBit != null && modifiers.has(cap.modifierBit!),
        KeyCapKind.switchToText => false,
        KeyCapKind.normal => cap.usage == proto.HidKey.capsLock && capsLock,
      };

  void _press(KeyCap cap) {
    switch (cap.kind) {
      case KeyCapKind.modifier:
        if (cap.modifierBit != null) onModifier(cap.modifierBit!);
      case KeyCapKind.switchToText:
        onSwitchToText();
      case KeyCapKind.normal:
        if (cap.usage != null) onKey(cap.usage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();

    // Keycaps are clamped rather than scaled without limit. See
    // [kKeyCapMaxTextScale]: past that point a label cannot fit a key at any
    // row height, and the labels inside shrink to fit rather than clip.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kKeyCapMaxTextScale,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Keys are sized to fill the width and share the height evenly, so
          // the whole keyboard is reachable without scrolling. A keyboard you
          // have to scroll to reach Enter on is not a keyboard.
          const spacing = 4.0;

          // Rows grow with the text setting, so a larger label has somewhere to
          // go before it has to shrink.
          final scale =
              textScaleFactorOf(context).clamp(1.0, kKeyCapMaxTextScale);
          final minRow = 28.0 * scale;
          final maxRow = 72.0 * scale;

          // Every row contributes its height plus one gap, and the surrounding
          // Padding adds one more gap at each end: `rows + 2`, not `rows + 1`.
          // The original arithmetic was short by exactly one gap, which is why
          // a tight fit overflowed by precisely 4 pixels.
          final gaps = spacing * (rows.length + 2);
          final available = constraints.maxHeight - gaps;
          final rowHeight = (available / rows.length).clamp(minRow, maxRow);

          // The clamp can ask for more height than there is: a short window at
          // a large text size. Scrolling then is the lesser evil — the previous
          // code clamped the same way and simply overflowed, which drops the
          // bottom row, and the bottom row is where the modifiers live.
          final needed = rowHeight * rows.length + gaps;

          final keyboard = Padding(
            padding: const EdgeInsets.all(spacing),
            child: Column(
              children: <Widget>[
                for (final row in rows) ...<Widget>[
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: <Widget>[
                        for (final cap in row) ...<Widget>[
                          Expanded(
                            flex: (cap.flex * 10).round(),
                            child: _Key(
                              cap: cap,
                              active: _isActive(cap),
                              enabled: enabled,
                              onPressed: () => _press(cap),
                            ),
                          ),
                          const SizedBox(width: spacing),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: spacing),
                ],
              ],
            ),
          );

          return needed > constraints.maxHeight
              ? SingleChildScrollView(child: keyboard)
              : keyboard;
        },
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.cap,
    required this.active,
    required this.enabled,
    required this.onPressed,
  });

  final KeyCap cap;
  final bool active;
  final bool enabled;
  final VoidCallback onPressed;

  /// True for keys that stay on until pressed again, which announce a state.
  bool get _isToggle =>
      cap.kind == KeyCapKind.modifier || cap.usage == proto.HidKey.capsLock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: cap.semanticLabel,
      // A held modifier is the one piece of keyboard state whose consequences
      // are invisible: Shift stuck on produces baffling results three
      // keystrokes later. Sighted users get the colour change; `toggled` is how
      // the same fact reaches everyone else.
      toggled: _isToggle ? active : null,
      // The label above replaces the glyph. Without this the reader announces
      // both, and the glyph is the half it cannot say.
      excludeSemantics: true,
      child: Material(
        color: !enabled
            ? scheme.surfaceContainerLow
            : active
                ? scheme.primary
                : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Center(
            // Scales the label down instead of clipping it. A clipped keycap is
            // not merely ugly — 'F11' cut to 'F1' is a different key, and there
            // is no way to tell which one was pressed.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  cap.label,
                  maxLines: 1,
                  style: TextStyle(
                    // Long labels start smaller: ALTGR must stay legible next
                    // to a single-letter key.
                    fontSize: cap.label.length > 3 ? 11 : 14,
                    fontWeight: FontWeight.w600,
                    color: !enabled
                        // Material's own disabled opacity. Disabled controls
                        // are exempt from the contrast minimum, and looking
                        // disabled is the point: the whole keyboard greys out
                        // when the computer is not connected.
                        ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
                        : active
                            ? scheme.onPrimary
                            : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
