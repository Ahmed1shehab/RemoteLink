import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../input_backend.dart';
import '../keymap.dart';
import 'coregraphics_ffi.dart';

/// macOS input injection via Quartz Event Services.
///
/// `CGEventPost` is used rather than the higher-level Accessibility API because
/// it is the only route that reaches every application uniformly. `AXUIElement`
/// actions depend on each app exposing accessibility metadata, which games,
/// Electron apps, and anything drawing its own UI generally do not.
///
/// ## Accessibility permission
///
/// Every call here silently does nothing until the user grants Accessibility
/// permission in System Settings. There is no error and no exception — the
/// cursor simply does not move. [isAvailable] checks `AXIsProcessTrusted` up
/// front so the desktop can show a real explanation instead of leaving the user
/// with a remote that looks connected and does nothing.
///
/// ## Event ownership
///
/// Core Foundation is manually reference counted and Dart's GC does not know
/// about it. Every `CGEventCreate*` returns an object this code owns, and every
/// one is released in a `finally`. Missing a release leaks a few hundred bytes
/// per event, which at 120 Hz is roughly 3 MB per minute of use — the kind of
/// leak that only shows up after an hour and is miserable to track down later.
final class MacosInputBackend implements InputBackend {
  MacosInputBackend() : _bindings = CoreGraphicsBindings() {
    _source = _bindings.eventSourceCreate(kCGEventSourceStateHIDSystemState);
    _point = calloc<CGPoint>();
    _unicodeBuffer = calloc<Uint16>(_unicodeBatch);
  }

  /// UTF-16 units injected per event. Core Graphics accepts a string per
  /// keyboard event, so a whole paste can go out in a handful of calls.
  static const int _unicodeBatch = 256;

  final CoreGraphicsBindings _bindings;
  final Log _log = Log.scoped('native.input.macos');

  late final CGEventSourceRef _source;
  late final Pointer<CGPoint> _point;
  late final Pointer<Uint16> _unicodeBuffer;

  final Set<int> _heldKeyCodes = <int>{};
  final Set<MouseButton> _heldButtons = <MouseButton>{};
  Modifiers _modifiers = Modifiers.none;

  bool _disposed = false;

  @override
  bool get isAvailable => !_disposed && _bindings.isProcessTrusted();

  @override
  String? get unavailableReason {
    if (_disposed) return 'backend disposed';
    if (!_bindings.isProcessTrusted()) {
      return 'RemoteLink needs Accessibility permission. Open System Settings '
          '› Privacy & Security › Accessibility and enable RemoteLink.';
    }
    return null;
  }

  /// Posts [event] and releases it.
  void _postAndRelease(CGEventRef event) {
    if (event == nullptr) return;
    try {
      _bindings.post(kCGHIDEventTap, event);
    } finally {
      _bindings.release(event);
    }
  }

  @override
  (int, int) get cursorPosition {
    final probe = _bindings.createEvent(nullptr);
    if (probe == nullptr) return (0, 0);
    try {
      final location = _bindings.getLocation(probe);
      return (location.x.round(), location.y.round());
    } finally {
      _bindings.release(probe);
    }
  }

  @override
  void moveCursorBy(int deltaX, int deltaY) {
    if (deltaX == 0 && deltaY == 0) return;
    final (x, y) = cursorPosition;
    _moveTo(
      x + deltaX,
      y + deltaY,
      deltaX: deltaX,
      deltaY: deltaY,
    );
  }

  @override
  void moveCursorTo(int x, int y) => _moveTo(x, y, deltaX: 0, deltaY: 0);

  void _moveTo(int x, int y, {required int deltaX, required int deltaY}) {
    final bounds = virtualBounds;
    _point.ref
      // Clamping is not cosmetic: Core Graphics accepts off-screen coordinates
      // and the cursor genuinely disappears, with no way to recover it from the
      // phone because subsequent relative moves start from the lost position.
      ..x = x.clamp(bounds.x, bounds.right - 1).toDouble()
      ..y = y.clamp(bounds.y, bounds.bottom - 1).toDouble();

    // A move while a button is held must be a *drag* event, not a move. Sending
    // a plain move mid-drag makes text selection and window dragging stop
    // tracking the cursor.
    final held = _heldButtons.isEmpty ? null : _heldButtons.first;
    final type = switch (held) {
      null => kCGEventMouseMoved,
      MouseButton.left => kCGEventLeftMouseDragged,
      MouseButton.right => kCGEventRightMouseDragged,
      _ => kCGEventOtherMouseDragged,
    };

    final event = _bindings.createMouseEvent(
      _source,
      type,
      _point.ref,
      _cgButton(held ?? MouseButton.left),
    );
    if (event == nullptr) return;

    try {
      // Games and drawing apps read the delta fields rather than tracking
      // absolute position, so leaving them zero makes synthetic movement
      // invisible to exactly the applications people most want to control.
      _bindings
        ..setIntegerValueField(event, kCGMouseEventDeltaX, deltaX)
        ..setIntegerValueField(event, kCGMouseEventDeltaY, deltaY)
        ..setFlags(event, KeyMap.macFlagsFor(_modifiers))
        ..post(kCGHIDEventTap, event);
    } finally {
      _bindings.release(event);
    }
  }

  int _cgButton(MouseButton button) => switch (button) {
        MouseButton.left => kCGMouseButtonLeft,
        MouseButton.right => kCGMouseButtonRight,
        MouseButton.middle => kCGMouseButtonCenter,
        MouseButton.back => 3,
        MouseButton.forward => 4,
      };

  @override
  void mouseDown(MouseButton button) =>
      _mouseButton(button, pressed: true, clickCount: 1);

  @override
  void mouseUp(MouseButton button) =>
      _mouseButton(button, pressed: false, clickCount: 1);

  /// Presses or releases [button], reporting [clickCount] to the window server.
  ///
  /// Exposed beyond the interface because macOS derives double-click from this
  /// field rather than from timing. The dispatcher passes the count the phone
  /// measured, so a double-tap selects a word even when the two events crossed
  /// the network 200 ms apart.
  void mouseButtonWithCount(
    MouseButton button, {
    required bool pressed,
    required int clickCount,
  }) =>
      _mouseButton(button, pressed: pressed, clickCount: clickCount);

  void _mouseButton(
    MouseButton button, {
    required bool pressed,
    required int clickCount,
  }) {
    if (pressed) {
      _heldButtons.add(button);
    } else {
      _heldButtons.remove(button);
    }

    final (x, y) = cursorPosition;
    _point.ref
      ..x = x.toDouble()
      ..y = y.toDouble();

    final type = switch ((button, pressed)) {
      (MouseButton.left, true) => kCGEventLeftMouseDown,
      (MouseButton.left, false) => kCGEventLeftMouseUp,
      (MouseButton.right, true) => kCGEventRightMouseDown,
      (MouseButton.right, false) => kCGEventRightMouseUp,
      (_, true) => kCGEventOtherMouseDown,
      (_, false) => kCGEventOtherMouseUp,
    };

    final event = _bindings.createMouseEvent(
      _source,
      type,
      _point.ref,
      _cgButton(button),
    );
    if (event == nullptr) return;

    try {
      _bindings
        ..setIntegerValueField(event, kCGMouseEventClickState, clickCount)
        ..setIntegerValueField(
          event,
          kCGMouseEventButtonNumber,
          _cgButton(button),
        )
        ..setFlags(event, KeyMap.macFlagsFor(_modifiers))
        ..post(kCGHIDEventTap, event);
    } finally {
      _bindings.release(event);
    }
  }

  @override
  void scroll({
    required int linesX,
    required int linesY,
    required int pixelsX,
    required int pixelsY,
    bool isMomentum = false,
  }) {
    // macOS prefers pixel units: that is what gives smooth, rubber-banding
    // trackpad scrolling. Line units exist for a notched wheel and look jerky
    // when a finger drove the gesture, so pixels win whenever they are present.
    final usePixels = pixelsX != 0 || pixelsY != 0;
    final unit = usePixels ? kCGScrollEventUnitPixel : kCGScrollEventUnitLine;
    final vertical = usePixels ? pixelsY : linesY;
    final horizontal = usePixels ? pixelsX : linesX;

    if (vertical == 0 && horizontal == 0) return;

    final event = _bindings.createScrollEvent(
      _source,
      unit,
      2,
      vertical,
      horizontal,
    );
    _postAndRelease(event);
  }

  @override
  void keyEvent({required int hidUsage, required bool pressed}) {
    final keyCode = KeyMap.hidToMacKeyCode[hidUsage];
    if (keyCode == null) {
      _log.debug(() => 'no CGKeyCode mapping for HID usage 0x'
          '${hidUsage.toRadixString(16)}');
      return;
    }

    if (pressed) {
      _heldKeyCodes.add(keyCode);
    } else {
      _heldKeyCodes.remove(keyCode);
    }
    if (HidKey.isModifier(hidUsage)) {
      final bit = HidKey.modifierBit(hidUsage);
      _modifiers = pressed ? _modifiers.plus(bit) : _modifiers.minus(bit);
    }

    final event = _bindings.createKeyboardEvent(_source, keyCode, pressed);
    if (event == nullptr) return;

    try {
      // Flags must be set explicitly. Unlike Windows, macOS does not infer
      // modifier state from previously posted modifier key events — a Cmd+C
      // sent as three separate events arrives as a bare C without this.
      _bindings
        ..setFlags(event, KeyMap.macFlagsFor(_modifiers))
        ..post(kCGHIDEventTap, event);
    } finally {
      _bindings.release(event);
    }
  }

  @override
  void typeText(String text) {
    if (text.isEmpty) return;

    final units = text.codeUnits;
    var index = 0;

    while (index < units.length) {
      final chunk = (units.length - index).clamp(0, _unicodeBatch);
      for (var i = 0; i < chunk; i++) {
        _unicodeBuffer[i] = units[index + i];
      }
      index += chunk;

      // Key code 0 with an attached Unicode string is the documented way to
      // inject text: the window server delivers the string and ignores the
      // key code entirely, so the current layout never comes into it.
      for (final pressed in <bool>[true, false]) {
        final event = _bindings.createKeyboardEvent(_source, 0, pressed);
        if (event == nullptr) continue;
        try {
          _bindings
            ..setUnicodeString(event, chunk, _unicodeBuffer)
            ..post(kCGHIDEventTap, event);
        } finally {
          _bindings.release(event);
        }
      }
    }
  }

  @override
  void setModifiers(Modifiers modifiers) {
    if (modifiers.bits == _modifiers.bits) return;

    for (final usage in <int>[
      HidKey.controlLeft,
      HidKey.shiftLeft,
      HidKey.altLeft,
      HidKey.metaLeft,
      HidKey.controlRight,
      HidKey.shiftRight,
      HidKey.altRight,
      HidKey.metaRight,
    ]) {
      final bit = HidKey.modifierBit(usage);
      final shouldBeDown = modifiers.has(bit);
      if (shouldBeDown == _modifiers.has(bit)) continue;

      final keyCode = KeyMap.hidToMacKeyCode[usage];
      if (keyCode == null) continue;

      _modifiers =
          shouldBeDown ? _modifiers.plus(bit) : _modifiers.minus(bit);

      final event =
          _bindings.createKeyboardEvent(_source, keyCode, shouldBeDown);
      if (event == nullptr) continue;
      try {
        _bindings
          ..setFlags(event, KeyMap.macFlagsFor(_modifiers))
          ..post(kCGHIDEventTap, event);
      } finally {
        _bindings.release(event);
      }
    }

    _modifiers = modifiers;
  }

  @override
  void releaseAll() {
    for (final keyCode in _heldKeyCodes.toList()) {
      final event = _bindings.createKeyboardEvent(_source, keyCode, false);
      _postAndRelease(event);
    }
    _heldKeyCodes.clear();

    for (final button in _heldButtons.toList()) {
      mouseUp(button);
    }
    _heldButtons.clear();

    _modifiers = Modifiers.none;
  }

  @override
  List<ScreenBounds> get displays {
    final displayId = _bindings.mainDisplayId();
    final bounds = _bindings.displayBounds(displayId);

    // CGDisplayBounds reports points; CGDisplayPixelsWide reports backing
    // pixels. Their ratio is the Retina scale factor, which the phone needs to
    // map a touch on a scaled screen preview back to real coordinates.
    final pixelWidth = _bindings.displayPixelsWide(displayId);
    final scale = bounds.size.width > 0 ? pixelWidth / bounds.size.width : 1.0;

    return <ScreenBounds>[
      ScreenBounds(
        x: bounds.origin.x.round(),
        y: bounds.origin.y.round(),
        width: bounds.size.width.round(),
        height: bounds.size.height.round(),
        scaleFactor: scale,
      ),
    ];
  }

  @override
  ScreenBounds get virtualBounds {
    // Enumerating every display needs CGGetActiveDisplayList and an array
    // marshal, which milestone 1 does not require. The main display bounds
    // cover clamping and absolute positioning on the overwhelmingly common
    // single-display setup; multi-display lands with screen sharing.
    final all = displays;
    return all.isEmpty
        ? const ScreenBounds(x: 0, y: 0, width: 0, height: 0)
        : all.first;
  }

  @override
  void dispose() {
    if (_disposed) return;
    releaseAll();
    _disposed = true;

    if (_source != nullptr) _bindings.release(_source);
    calloc
      ..free(_point)
      ..free(_unicodeBuffer);
  }
}
