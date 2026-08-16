import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Prefixed deliberately. `TextInput` and `KeyEvent` are names Flutter's own
// services library already owns, and this file legitimately needs both worlds:
// Flutter's for the capture field, ours for what goes on the wire. A prefix
// makes every line say which one it means, and is immune to whatever
// `material.dart` happens to re-export.
import 'package:rl_protocol/rl_protocol.dart' as proto;
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import 'hardware_keyboard_view.dart';

/// Length of the sentinel buffer the capture field is reset to.
///
/// Long enough that a burst of held backspaces still has characters to consume
/// before the field empties; short enough that resetting it is imperceptible.
const int _sentinelLength = 64;

/// Full keyboard, sending real key events to the computer.
///
/// ## Capturing a soft keyboard
///
/// There is nothing to type *into* here — the text belongs on the computer. But
/// a phone's keyboard only appears for a focused text field, and the platform
/// reports edits rather than key presses.
///
/// So the screen hosts an invisible `TextField` primed with a run of spaces and
/// the cursor at the end, and infers what happened from how its contents
/// changed:
///
/// * **Longer** — characters were typed. Send them as `TextInput`, which
///   injects Unicode directly and therefore handles emoji, accents, and
///   anything composed by the phone's own IME without touching keycodes.
/// * **Shorter** — backspace, once per character removed. Send `KeyEvent` for
///   the real backspace key so held-repeat and modifier combinations behave.
///
/// Then reset to the sentinel so there is always room to delete. The
/// alternative — leaving the field to accumulate — breaks the moment the user
/// deletes past the start, which is exactly what happens when they hold
/// backspace.
class KeyboardScreen extends ConsumerStatefulWidget {
  const KeyboardScreen({super.key});

  @override
  ConsumerState<KeyboardScreen> createState() => _KeyboardScreenState();
}

/// Which keyboard the user is looking at.
enum KeyboardMode {
  /// The phone's own keyboard, forwarded as Unicode. Right for text: the
  /// user's languages, their IME, emoji, dictation.
  text,

  /// A rendered hardware keyboard sending real HID usages. Right for control:
  /// Ctrl, Alt, function keys, Escape, WASD — none of which a soft keyboard
  /// can express.
  keys,
}

class _KeyboardScreenState extends ConsumerState<KeyboardScreen> {
  final TextEditingController _capture = TextEditingController();
  final FocusNode _focus = FocusNode();

  // Defaults to the rendered keyboard. It is the one that can do everything —
  // the phone's keyboard cannot send Escape or Ctrl — so it is the safer thing
  // to land on, and switching is one tap.
  KeyboardMode _mode = KeyboardMode.keys;
  bool _capsLock = false;

  /// What has been sent to the computer since the transcript was last cleared.
  ///
  /// The capture field cannot itself be shown: it is permanently reset to a run
  /// of spaces so there is always room to detect backspace, so displaying it
  /// would show the sentinel rather than the user's text. This mirrors what was
  /// actually put on the wire instead — which is the honest thing to show, and
  /// happens to be what the user wants to see.
  String _transcript = '';

  final ScrollController _transcriptScroll = ScrollController();

  proto.Modifiers _modifiers = proto.Modifiers.none;

  /// Modifiers the user locked on, which survive a keystroke.
  int _locked = 0;

  @override
  void initState() {
    super.initState();
    _resetCapture();
  }

  @override
  void dispose() {
    _capture.dispose();
    _focus.dispose();
    _transcriptScroll.dispose();
    super.dispose();
  }

  void _resetCapture() {
    _capture.value = TextEditingValue(
      text: ' ' * _sentinelLength,
      selection: const TextSelection.collapsed(offset: _sentinelLength),
    );
  }

  Future<void> _send(proto.Message message) async {
    final client = ref.read(clientProvider).valueOrNull;
    if (client == null) return;
    await client.send(message);
  }

  void _onCaptureChanged(String value) {
    final delta = value.length - _sentinelLength;

    if (delta > 0) {
      final typed = value.substring(_sentinelLength);
      unawaited(_send(proto.TextInput(typed)));
      setState(() => _transcript += typed);
    } else if (delta < 0) {
      for (var i = 0; i < -delta; i++) {
        unawaited(_tapKey(proto.HidKey.backspace, clearModifiers: false));
      }
      setState(() {
        final removed = -delta;
        _transcript = _transcript.length <= removed
            ? ''
            : _transcript.substring(0, _transcript.length - removed);
      });
    }

    _resetCapture();
    _scrollTranscriptToEnd();
  }

  /// Presses and releases a key with the current modifiers applied.
  Future<void> _tapKey(int usage, {bool clearModifiers = true}) async {
    final modifiers = _modifiers;
    await _send(
      proto.KeyEvent(hidUsage: usage, pressed: true, modifiers: modifiers),
    );
    await _send(
      proto.KeyEvent(hidUsage: usage, pressed: false, modifiers: modifiers),
    );
    unawaited(HapticFeedback.selectionClick());

    // Unlocked modifiers are one-shot, matching how a sticky-keys accessibility
    // mode behaves: press Ctrl, press C, Ctrl releases itself. Holding them
    // would strand the user in a modified state they cannot see.
    if (clearModifiers && _locked != _modifiers.bits) {
      setState(() => _modifiers = proto.Modifiers(_locked));
      unawaited(_send(proto.ModifierStateMessage(proto.Modifiers(_locked))));
    }
  }

  void _toggleModifier(int bit) {
    setState(() {
      if (_modifiers.has(bit)) {
        // Second tap locks it; third clears it.
        if (_locked & bit != 0) {
          _locked &= ~bit;
          _modifiers = _modifiers.minus(bit);
        } else {
          _locked |= bit;
        }
      } else {
        _modifiers = _modifiers.plus(bit);
      }
    });
    unawaited(_send(proto.ModifierStateMessage(_modifiers)));
  }

  Future<void> _shortcut(proto.NamedShortcut shortcut) async {
    await _send(proto.NamedShortcutMessage(shortcut));
    unawaited(HapticFeedback.selectionClick());
  }

  /// Keeps the newest text visible as it is typed.
  ///
  /// Deferred to after the frame because the transcript grows in the same
  /// `setState` that triggers the rebuild — scrolling before layout would use
  /// the previous extent and land a character short.
  void _scrollTranscriptToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_transcriptScroll.hasClients) return;
      _transcriptScroll.jumpTo(_transcriptScroll.position.maxScrollExtent);
    });
  }

  void _setMode(KeyboardMode mode) {
    setState(() => _mode = mode);
    // The phone's keyboard must not sit over a rendered one, and must come back
    // when switching to text mode — the soft keyboard is the whole point there.
    if (mode == KeyboardMode.keys) {
      _focus.unfocus();
    } else {
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        ref.watch(clientStateProvider).valueOrNull == ClientState.connected;
    final platform = ref.watch(connectedPlatformProvider);

    return Column(
      children: <Widget>[
        // Invisible but genuinely laid out. `Offstage` would skip layout, and a
        // text field that is never laid out cannot reliably hold the platform
        // text-input connection the soft keyboard attaches to.
        SizedBox(
          width: 1,
          height: 1,
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _capture,
              focusNode: _focus,
              // Not autofocused: the screen opens on the rendered keyboard, and
              // autofocus would raise the phone's keyboard over it. Focus is
              // taken only when the user actually switches to Text.
              autofocus: false,
              // No autocorrect, no suggestions, no capitalisation: the phone
              // must not rewrite what the user is typing into their computer.
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              keyboardType: TextInputType.multiline,
              maxLines: null,
              onChanged: _onCaptureChanged,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SegmentedButton<KeyboardMode>(
            segments: const <ButtonSegment<KeyboardMode>>[
              ButtonSegment<KeyboardMode>(
                value: KeyboardMode.text,
                icon: Icon(Icons.abc),
                label: Text('Text'),
              ),
              ButtonSegment<KeyboardMode>(
                value: KeyboardMode.keys,
                icon: Icon(Icons.keyboard_alt_outlined),
                label: Text('Keys'),
              ),
            ],
            selected: <KeyboardMode>{_mode},
            onSelectionChanged: (selection) => _setMode(selection.first),
          ),
        ),
        Expanded(
          child: switch (_mode) {
            KeyboardMode.keys => HardwareKeyboardView(
                platform: platform,
                modifiers: _modifiers,
                capsLock: _capsLock,
                enabled: connected,
                onKey: _onHardwareKey,
                onModifier: _toggleModifier,
                onSwitchToText: () => _setMode(KeyboardMode.text),
              ),
            KeyboardMode.text => GestureDetector(
                // Tapping anywhere raises the phone's keyboard: the whole area
                // is the affordance, since there is no visible field to aim at.
                onTap: () => _focus.requestFocus(),
                behavior: HitTestBehavior.opaque,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _TypedEcho(
                        text: _transcript,
                        scrollController: _transcriptScroll,
                        onTap: () => _focus.requestFocus(),
                        onClear: () => setState(() => _transcript = ''),
                      ),
                      const SizedBox(height: 16),
                      _SectionLabel(
                        label: connected ? 'Shortcuts' : 'Not connected',
                      ),
                      _ShortcutGrid(
                        enabled: connected,
                        onShortcut: _shortcut,
                      ),
                      const SizedBox(height: 16),
                      const _SectionLabel(label: 'Modifiers'),
                      _ModifierRow(
                        modifiers: _modifiers,
                        locked: _locked,
                        enabled: connected,
                        onToggle: _toggleModifier,
                      ),
                      const SizedBox(height: 16),
                      const _SectionLabel(label: 'Keys'),
                      _SpecialKeys(
                        enabled: connected,
                        onKey: (usage) => unawaited(_tapKey(usage)),
                      ),
                    ],
                  ),
                ),
              ),
          },
        ),
      ],
    );
  }

  /// A key pressed on the rendered keyboard.
  ///
  /// Caps Lock is tracked locally as well as sent, because the desktop's actual
  /// lock state is not reported back and an unlit Caps key on a keyboard that
  /// has it enabled is worse than not showing the state at all.
  void _onHardwareKey(int usage) {
    if (usage == proto.HidKey.capsLock) {
      setState(() => _capsLock = !_capsLock);
    }
    unawaited(_tapKey(usage));
  }
}

/// Shows what has actually been sent to the computer.
///
/// Not a text field the user edits — it is an echo of what went on the wire.
/// That distinction matters: an editable field would imply the text lives here
/// and can be corrected before sending, when in truth every character has
/// already arrived. Showing it read-only keeps the model honest, and backspace
/// removes from here exactly as it removes on the computer.
class _TypedEcho extends StatelessWidget {
  const _TypedEcho({
    required this.text,
    required this.scrollController,
    required this.onTap,
    required this.onClear,
  });

  final String text;
  final ScrollController scrollController;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 96, maxHeight: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.keyboard_alt_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Sent to your computer',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                if (text.isNotEmpty)
                  InkWell(
                    onTap: onClear,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        'Clear',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                            ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Text(
                  text.isEmpty ? 'Tap here, then type.' : text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    color: text.isEmpty
                        ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                        : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      );
}

class _ShortcutGrid extends StatelessWidget {
  const _ShortcutGrid({required this.enabled, required this.onShortcut});

  final bool enabled;
  final Future<void> Function(proto.NamedShortcut) onShortcut;

  /// Sent as *intent*, not as keystrokes.
  ///
  /// The desktop resolves each to the right chord for its platform — Cmd+C on
  /// macOS, Ctrl+C on Windows — so this list ships once instead of branching
  /// per platform, and adding a shortcut needs no mobile release.
  static const List<(proto.NamedShortcut, String, IconData)> _entries =
      <(proto.NamedShortcut, String, IconData)>[
    (proto.NamedShortcut.copy, 'Copy', Icons.copy),
    (proto.NamedShortcut.paste, 'Paste', Icons.paste),
    (proto.NamedShortcut.cut, 'Cut', Icons.cut),
    (proto.NamedShortcut.undo, 'Undo', Icons.undo),
    (proto.NamedShortcut.redo, 'Redo', Icons.redo),
    (proto.NamedShortcut.selectAll, 'Select all', Icons.select_all),
    (proto.NamedShortcut.save, 'Save', Icons.save_outlined),
    (proto.NamedShortcut.find, 'Find', Icons.search),
    (proto.NamedShortcut.switchApplication, 'Switch app', Icons.apps),
    (proto.NamedShortcut.closeTab, 'Close tab', Icons.tab_unselected),
    (proto.NamedShortcut.refresh, 'Refresh', Icons.refresh),
    (
      proto.NamedShortcut.taskManager,
      'Task manager',
      Icons.monitor_heart_outlined
    ),
  ];

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final (shortcut, label, icon) in _entries)
            ActionChip(
              avatar: Icon(icon, size: 18),
              label: Text(label),
              onPressed: enabled ? () => onShortcut(shortcut) : null,
            ),
        ],
      );
}

class _ModifierRow extends StatelessWidget {
  const _ModifierRow({
    required this.modifiers,
    required this.locked,
    required this.enabled,
    required this.onToggle,
  });

  final proto.Modifiers modifiers;
  final int locked;
  final bool enabled;
  final void Function(int bit) onToggle;

  static const List<(int, String)> _entries = <(int, String)>[
    (proto.Modifiers.leftControl, 'Ctrl'),
    (proto.Modifiers.leftShift, 'Shift'),
    (proto.Modifiers.leftAlt, 'Alt'),
    (proto.Modifiers.leftMeta, 'Cmd'),
  ];

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        children: <Widget>[
          for (final (bit, label) in _entries)
            FilterChip(
              label: Text(label),
              selected: modifiers.has(bit),
              // A locked modifier is visually distinct from a one-shot one,
              // because "Shift is stuck on" is otherwise invisible and produces
              // baffling results three keystrokes later.
              avatar:
                  locked & bit != 0 ? const Icon(Icons.lock, size: 16) : null,
              onSelected: enabled ? (_) => onToggle(bit) : null,
            ),
        ],
      );
}

class _SpecialKeys extends StatelessWidget {
  const _SpecialKeys({required this.enabled, required this.onKey});

  final bool enabled;
  final void Function(int usage) onKey;

  static const List<(int, String)> _entries = <(int, String)>[
    (proto.HidKey.escape, 'Esc'),
    (proto.HidKey.tab, 'Tab'),
    (proto.HidKey.enter, 'Enter'),
    (proto.HidKey.backspace, '⌫'),
    (proto.HidKey.delete, 'Del'),
    (proto.HidKey.home, 'Home'),
    (proto.HidKey.end, 'End'),
    (proto.HidKey.pageUp, 'PgUp'),
    (proto.HidKey.pageDown, 'PgDn'),
    (proto.HidKey.arrowLeft, '←'),
    (proto.HidKey.arrowUp, '↑'),
    (proto.HidKey.arrowDown, '↓'),
    (proto.HidKey.arrowRight, '→'),
    (proto.HidKey.f1, 'F1'),
    (proto.HidKey.f2, 'F2'),
    (proto.HidKey.f3, 'F3'),
    (proto.HidKey.f4, 'F4'),
    (proto.HidKey.f5, 'F5'),
    (proto.HidKey.f11, 'F11'),
    (proto.HidKey.f12, 'F12'),
  ];

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final (usage, label) in _entries)
            SizedBox(
              width: 68,
              child: OutlinedButton(
                onPressed: enabled ? () => onKey(usage) : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(label),
              ),
            ),
        ],
      );
}
