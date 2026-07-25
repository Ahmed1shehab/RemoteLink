import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';

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

class _KeyboardScreenState extends ConsumerState<KeyboardScreen> {
  final TextEditingController _capture = TextEditingController();
  final FocusNode _focus = FocusNode();

  Modifiers _modifiers = Modifiers.none;

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
    super.dispose();
  }

  void _resetCapture() {
    _capture.value = TextEditingValue(
      text: ' ' * _sentinelLength,
      selection: const TextSelection.collapsed(offset: _sentinelLength),
    );
  }

  Future<void> _send(Message message) async {
    final client = ref.read(clientProvider).valueOrNull;
    if (client == null) return;
    await client.send(message);
  }

  void _onCaptureChanged(String value) {
    final delta = value.length - _sentinelLength;

    if (delta > 0) {
      final typed = value.substring(_sentinelLength);
      unawaited(_send(TextInput(typed)));
    } else if (delta < 0) {
      for (var i = 0; i < -delta; i++) {
        unawaited(_tapKey(HidKey.backspace, clearModifiers: false));
      }
    }

    _resetCapture();
  }

  /// Presses and releases a key with the current modifiers applied.
  Future<void> _tapKey(int usage, {bool clearModifiers = true}) async {
    final modifiers = _modifiers;
    await _send(
      KeyEvent(hidUsage: usage, pressed: true, modifiers: modifiers),
    );
    await _send(
      KeyEvent(hidUsage: usage, pressed: false, modifiers: modifiers),
    );
    unawaited(HapticFeedback.selectionClick());

    // Unlocked modifiers are one-shot, matching how a sticky-keys accessibility
    // mode behaves: press Ctrl, press C, Ctrl releases itself. Holding them
    // would strand the user in a modified state they cannot see.
    if (clearModifiers && _locked != _modifiers.bits) {
      setState(() => _modifiers = Modifiers(_locked));
      unawaited(_send(ModifierStateMessage(Modifiers(_locked))));
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
    unawaited(_send(ModifierStateMessage(_modifiers)));
  }

  Future<void> _shortcut(NamedShortcut shortcut) async {
    await _send(NamedShortcutMessage(shortcut));
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        ref.watch(clientStateProvider).valueOrNull == ClientState.connected;

    return GestureDetector(
      // Tapping anywhere raises the keyboard: the whole screen is the affordance
      // since there is no visible field to aim at.
      onTap: () => _focus.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: <Widget>[
          // Invisible but genuinely laid out. `Offstage` would skip layout, and
          // a text field that is never laid out cannot reliably hold the
          // platform text-input connection the soft keyboard attaches to.
          SizedBox(
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _capture,
                focusNode: _focus,
                autofocus: true,
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
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
        ],
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
  final Future<void> Function(NamedShortcut) onShortcut;

  /// Sent as *intent*, not as keystrokes.
  ///
  /// The desktop resolves each to the right chord for its platform — Cmd+C on
  /// macOS, Ctrl+C on Windows — so this list ships once instead of branching
  /// per platform, and adding a shortcut needs no mobile release.
  static const List<(NamedShortcut, String, IconData)> _entries =
      <(NamedShortcut, String, IconData)>[
    (NamedShortcut.copy, 'Copy', Icons.copy),
    (NamedShortcut.paste, 'Paste', Icons.paste),
    (NamedShortcut.cut, 'Cut', Icons.cut),
    (NamedShortcut.undo, 'Undo', Icons.undo),
    (NamedShortcut.redo, 'Redo', Icons.redo),
    (NamedShortcut.selectAll, 'Select all', Icons.select_all),
    (NamedShortcut.save, 'Save', Icons.save_outlined),
    (NamedShortcut.find, 'Find', Icons.search),
    (NamedShortcut.switchApplication, 'Switch app', Icons.apps),
    (NamedShortcut.closeTab, 'Close tab', Icons.tab_unselected),
    (NamedShortcut.refresh, 'Refresh', Icons.refresh),
    (NamedShortcut.taskManager, 'Task manager', Icons.monitor_heart_outlined),
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

  final Modifiers modifiers;
  final int locked;
  final bool enabled;
  final void Function(int bit) onToggle;

  static const List<(int, String)> _entries = <(int, String)>[
    (Modifiers.leftControl, 'Ctrl'),
    (Modifiers.leftShift, 'Shift'),
    (Modifiers.leftAlt, 'Alt'),
    (Modifiers.leftMeta, 'Cmd'),
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
              avatar: locked & bit != 0
                  ? const Icon(Icons.lock, size: 16)
                  : null,
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
    (HidKey.escape, 'Esc'),
    (HidKey.tab, 'Tab'),
    (HidKey.enter, 'Enter'),
    (HidKey.backspace, '⌫'),
    (HidKey.delete, 'Del'),
    (HidKey.home, 'Home'),
    (HidKey.end, 'End'),
    (HidKey.pageUp, 'PgUp'),
    (HidKey.pageDown, 'PgDn'),
    (HidKey.arrowLeft, '←'),
    (HidKey.arrowUp, '↑'),
    (HidKey.arrowDown, '↓'),
    (HidKey.arrowRight, '→'),
    (HidKey.f1, 'F1'),
    (HidKey.f2, 'F2'),
    (HidKey.f3, 'F3'),
    (HidKey.f4, 'F4'),
    (HidKey.f5, 'F5'),
    (HidKey.f11, 'F11'),
    (HidKey.f12, 'F12'),
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
