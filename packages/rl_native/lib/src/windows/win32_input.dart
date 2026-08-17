import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../input_backend.dart';
import '../keymap.dart';
import '../monitor_topology.dart';
import 'win32_ffi.dart';

/// Windows input injection via `SendInput`.
///
/// `SendInput` is used rather than the older `mouse_event`/`keybd_event` pair
/// because it is the only API that submits several events atomically. That
/// matters more than it sounds: sending Ctrl-down and C-down as two separate
/// calls lets a context switch land between them, and the application sees a
/// bare `C` before the modifier arrives. Batching a whole chord into one
/// `SendInput` call makes that impossible.
///
/// ## What this cannot do
///
/// User Interface Privilege Isolation blocks synthetic input from a
/// medium-integrity process into a high-integrity one. A RemoteLink desktop
/// running unelevated therefore cannot type into an elevated Task Manager, an
/// elevated terminal, or the UAC prompt. This is a Windows security boundary
/// working correctly, not a bug to route around, and the app surfaces it as a
/// clear message rather than silently dropping the keystrokes.
final class Win32InputBackend implements InputBackend {
  Win32InputBackend() : _bindings = Win32Bindings() {
    // One reusable batch, allocated once. A chord never needs more than eight
    // events (four modifiers down, key down, key up, four modifiers up is the
    // worst realistic case, and that is split across two calls anyway).
    _batch = calloc<INPUT>(_batchCapacity);
    _point = calloc<POINT>();
    _monitorInfo = calloc<MONITORINFOEXW>();
  }

  static const int _batchCapacity = 16;

  /// Ceiling on monitors collected in one enumeration pass.
  static const int _maxMonitors = 32;

  final Win32Bindings _bindings;
  final Log _log = Log.scoped('native.input.win32');

  late final Pointer<INPUT> _batch;
  late final Pointer<POINT> _point;
  late final Pointer<MONITORINFOEXW> _monitorInfo;

  final Set<int> _heldKeys = <int>{};
  final Set<MouseButton> _heldButtons = <MouseButton>{};
  Modifiers _modifiers = Modifiers.none;

  bool _disposed = false;

  @override
  bool get isAvailable => !_disposed;

  @override
  String? get unavailableReason => _disposed ? 'backend disposed' : null;

  int get _inputSize => sizeOf<INPUT>();

  /// Submits the first [count] entries of the batch.
  void _flush(int count) {
    if (count == 0) return;
    final sent = _bindings.sendInput(count, _batch, _inputSize);
    if (sent == count) return;

    // A partial or zero return is almost always UIPI blocking us. Log once per
    // occurrence rather than throwing: the input stream must keep flowing even
    // if one event was refused.
    _log.debug(
      () => 'SendInput accepted $sent of $count events',
      fields: <String, Object?>{'lastError': _bindings.getLastError()},
    );
  }

  void _writeMouse(
    int index, {
    int dx = 0,
    int dy = 0,
    int mouseData = 0,
    required int flags,
  }) {
    final input = _batch[index];
    input.type = INPUT_MOUSE;
    input.u.mi
      ..dx = dx
      ..dy = dy
      ..mouseData = mouseData
      ..dwFlags = flags
      ..time = 0
      ..dwExtraInfo = 0;
  }

  void _writeKey(
    int index, {
    required int virtualKey,
    required bool pressed,
    int unicodeUnit = 0,
  }) {
    var flags = pressed ? 0 : KEYEVENTF_KEYUP;
    if (unicodeUnit != 0) {
      flags |= KEYEVENTF_UNICODE;
    } else if (KeyMap.windowsExtendedKeys.contains(virtualKey)) {
      flags |= KEYEVENTF_EXTENDEDKEY;
    }

    final input = _batch[index];
    input.type = INPUT_KEYBOARD;
    input.u.ki
      ..wVk = unicodeUnit != 0 ? 0 : virtualKey
      ..wScan = unicodeUnit
      ..dwFlags = flags
      ..time = 0
      ..dwExtraInfo = 0;
  }

  @override
  void moveCursorBy(int deltaX, int deltaY) {
    if (deltaX == 0 && deltaY == 0) return;
    _writeMouse(0, dx: deltaX, dy: deltaY, flags: MOUSEEVENTF_MOVE);
    _flush(1);
  }

  @override
  void moveCursorTo(int x, int y) {
    // SetCursorPos rather than an absolute SendInput: it takes real pixel
    // coordinates instead of the 0..65535 normalised space, so there is no
    // rounding error, and it does not interact with pointer acceleration.
    _bindings.setCursorPos(x, y);
  }

  @override
  (int, int) get cursorPosition {
    if (_bindings.getCursorPos(_point) == 0) return (0, 0);
    return (_point.ref.x, _point.ref.y);
  }

  @override
  void mouseDown(MouseButton button) {
    _heldButtons.add(button);
    final (flags, data) = _buttonFlags(button, pressed: true);
    _writeMouse(0, mouseData: data, flags: flags);
    _flush(1);
  }

  @override
  void mouseUp(MouseButton button) {
    _heldButtons.remove(button);
    final (flags, data) = _buttonFlags(button, pressed: false);
    _writeMouse(0, mouseData: data, flags: flags);
    _flush(1);
  }

  (int flags, int data) _buttonFlags(MouseButton button,
          {required bool pressed}) =>
      switch (button) {
        MouseButton.left => (
            pressed ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP,
            0
          ),
        MouseButton.right => (
            pressed ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP,
            0
          ),
        MouseButton.middle => (
            pressed ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP,
            0
          ),
        MouseButton.back => (
            pressed ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP,
            XBUTTON1,
          ),
        MouseButton.forward => (
            pressed ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP,
            XBUTTON2,
          ),
      };

  @override
  void scroll({
    required int linesX,
    required int linesY,
    required int pixelsX,
    required int pixelsY,
    bool isMomentum = false,
  }) {
    // Windows expects notches, not pixels: one WHEEL_DELTA is "one click of the
    // wheel", and applications multiply it by the user's lines-per-notch
    // setting. Feeding pixels here would make scrolling either glacial or
    // uncontrollable depending on that setting.
    var count = 0;

    if (linesY != 0) {
      // Positive is away from the user on Windows, which matches the protocol's
      // convention, so no sign flip.
      _writeMouse(
        count++,
        mouseData: linesY * WHEEL_DELTA,
        flags: MOUSEEVENTF_WHEEL,
      );
    }
    if (linesX != 0) {
      _writeMouse(
        count++,
        mouseData: linesX * WHEEL_DELTA,
        flags: MOUSEEVENTF_HWHEEL,
      );
    }

    // Fall back to pixel deltas when the sender reported no whole notches —
    // a slow trackpad drag produces sub-notch movement that would otherwise be
    // dropped entirely and feel like the scroll had stopped working.
    if (count == 0 && (pixelsY != 0 || pixelsX != 0)) {
      if (pixelsY != 0) {
        _writeMouse(
          count++,
          mouseData: (pixelsY * WHEEL_DELTA / 100).round(),
          flags: MOUSEEVENTF_WHEEL,
        );
      }
      if (pixelsX != 0) {
        _writeMouse(
          count++,
          mouseData: (pixelsX * WHEEL_DELTA / 100).round(),
          flags: MOUSEEVENTF_HWHEEL,
        );
      }
    }

    _flush(count);
  }

  @override
  void magnify(double delta) {
    // DELIBERATE APPROXIMATION:
    // Windows has no synthetic pinch-to-zoom gesture API; SendInput cannot
    // inject raw multi-touch or trackpad pinch events. We approximate pinch
    // by injecting Ctrl + mouse wheel notches, which is the standard shortcut
    // a human user presses on Windows across browsers, image viewers, and
    // document editors to zoom in and out.
    if (delta == 0) return;

    final notches = (delta * 10).round();
    final wheelNotches = notches != 0 ? notches : (delta > 0 ? 1 : -1);

    final isCtrlDown = _modifiers.hasControl;
    var count = 0;

    // Press Ctrl if not already held down
    if (!isCtrlDown) {
      _writeKey(count++, virtualKey: 0xA2 /* VK_LCONTROL */, pressed: true);
    }

    _writeMouse(
      count++,
      mouseData: wheelNotches * WHEEL_DELTA,
      flags: MOUSEEVENTF_WHEEL,
    );

    // Release Ctrl if we pressed it
    if (!isCtrlDown) {
      _writeKey(count++, virtualKey: 0xA2 /* VK_LCONTROL */, pressed: false);
    }

    _flush(count);
  }

  @override
  void rotate(double degrees) {
    // Windows has no synthetic rotation gesture API and no standard universal
    // shortcut convention for rotating arbitrary content. Per the action safety
    // guidelines, this is left inert on Windows rather than synthesizing an
    // unexpected approximation that behaves differently from what was requested.
  }

  @override
  void swipe({required int fingerCount, required SwipeDirection direction}) {
    // DELIBERATE APPROXIMATION:
    // Windows SendInput cannot inject multi-touch swipe gestures into the OS
    // gesture engine. We map multi-finger swipes to the exact Windows keyboard
    // shortcuts a user would press for window and workspace navigation:
    //   - Swipe up: Task View (Win + Tab)
    //   - Swipe down: Show Desktop (Win + D)
    //   - Swipe left: Switch virtual desktop left (Win + Ctrl + Left Arrow)
    //   - Swipe right: Switch virtual desktop right (Win + Ctrl + Right Arrow)
    var count = 0;
    switch (direction) {
      case SwipeDirection.up:
        // Win + Tab (Task View)
        _writeKey(count++, virtualKey: 0x5B /* VK_LWIN */, pressed: true);
        _writeKey(count++, virtualKey: 0x09 /* VK_TAB */, pressed: true);
        _writeKey(count++, virtualKey: 0x09 /* VK_TAB */, pressed: false);
        _writeKey(count++, virtualKey: 0x5B /* VK_LWIN */, pressed: false);

      case SwipeDirection.down:
        // Win + D (Show Desktop)
        _writeKey(count++, virtualKey: 0x5B /* VK_LWIN */, pressed: true);
        _writeKey(count++, virtualKey: 0x44 /* 'D' */, pressed: true);
        _writeKey(count++, virtualKey: 0x44 /* 'D' */, pressed: false);
        _writeKey(count++, virtualKey: 0x5B /* VK_LWIN */, pressed: false);

      case SwipeDirection.left:
        // Win + Ctrl + Left Arrow (Virtual Desktop Left)
        _writeKey(count++, virtualKey: 0x5B /* VK_LWIN */, pressed: true);
        _writeKey(count++, virtualKey: 0xA2 /* VK_LCONTROL */, pressed: true);
        _writeKey(count++, virtualKey: 0x25 /* VK_LEFT */, pressed: true);
        _writeKey(count++, virtualKey: 0x25 /* VK_LEFT */, pressed: false);
        _writeKey(count++, virtualKey: 0xA2 /* VK_LCONTROL */, pressed: false);
        _writeKey(count++, virtualKey: 0x5B /* VK_LWIN */, pressed: false);

      case SwipeDirection.right:
        // Win + Ctrl + Right Arrow (Virtual Desktop Right)
        _writeKey(count++, virtualKey: 0x5B /* VK_LWIN */, pressed: true);
        _writeKey(count++, virtualKey: 0xA2 /* VK_LCONTROL */, pressed: true);
        _writeKey(count++, virtualKey: 0x27 /* VK_RIGHT */, pressed: true);
        _writeKey(count++, virtualKey: 0x27 /* VK_RIGHT */, pressed: false);
        _writeKey(count++, virtualKey: 0xA2 /* VK_LCONTROL */, pressed: false);
        _writeKey(count++, virtualKey: 0x5B /* VK_LWIN */, pressed: false);
    }

    _flush(count);
  }

  @override
  void keyEvent({required int hidUsage, required bool pressed}) {
    final virtualKey = KeyMap.hidToVirtualKey[hidUsage];
    if (virtualKey == null) {
      // Dropping an unmapped usage is deliberate. Guessing would inject a
      // keystroke the user never asked for, which is far worse than nothing.
      _log.debug(() => 'no VK mapping for HID usage 0x'
          '${hidUsage.toRadixString(16)}');
      return;
    }

    if (pressed) {
      _heldKeys.add(virtualKey);
    } else {
      _heldKeys.remove(virtualKey);
    }
    if (HidKey.isModifier(hidUsage)) {
      final bit = HidKey.modifierBit(hidUsage);
      _modifiers = pressed ? _modifiers.plus(bit) : _modifiers.minus(bit);
    }

    _writeKey(0, virtualKey: virtualKey, pressed: pressed);
    _flush(1);
  }

  @override
  void typeText(String text) {
    if (text.isEmpty) return;

    // KEYEVENTF_UNICODE takes UTF-16 code units, and surrogate pairs must be
    // sent as two consecutive events — which is exactly what iterating
    // `codeUnits` produces. This is how emoji reach the desktop.
    final units = text.codeUnits;
    var index = 0;

    while (index < units.length) {
      var count = 0;
      // Each character needs a down and an up event, so the batch holds half as
      // many characters as it has slots.
      while (index < units.length && count + 2 <= _batchCapacity) {
        final unit = units[index++];
        _writeKey(count++, virtualKey: 0, pressed: true, unicodeUnit: unit);
        _writeKey(count++, virtualKey: 0, pressed: false, unicodeUnit: unit);
      }
      _flush(count);
    }
  }

  @override
  void setModifiers(Modifiers modifiers) {
    if (modifiers.bits == _modifiers.bits) return;

    var count = 0;
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
      final isDown = _modifiers.has(bit);
      if (shouldBeDown == isDown) continue;

      final virtualKey = KeyMap.hidToVirtualKey[usage];
      if (virtualKey == null) continue;
      _writeKey(count++, virtualKey: virtualKey, pressed: shouldBeDown);
    }

    _flush(count);
    _modifiers = modifiers;
  }

  @override
  void releaseAll() {
    var count = 0;
    for (final virtualKey in _heldKeys) {
      if (count >= _batchCapacity) {
        _flush(count);
        count = 0;
      }
      _writeKey(count++, virtualKey: virtualKey, pressed: false);
    }
    _flush(count);
    _heldKeys.clear();
    _modifiers = Modifiers.none;

    for (final button in _heldButtons.toList()) {
      mouseUp(button);
    }
    _heldButtons.clear();
  }

  @override
  List<MonitorInfo> get monitors {
    // The callback cannot close over `this` — `Pointer.fromFunction` only
    // accepts a static target — so handles land in a static buffer and are
    // processed here. Safe because enumeration is synchronous and
    // single-isolate: nothing else can run between the clear and the read.
    _enumeratedMonitors.clear();
    final ok = _bindings.enumDisplayMonitors(
      0,
      nullptr,
      Pointer.fromFunction<MonitorEnumProcNative>(_collectMonitor, 0),
      0,
    );
    if (ok == 0 && _enumeratedMonitors.isEmpty) {
      _log.debug(
        () => 'EnumDisplayMonitors failed',
        fields: <String, Object?>{'lastError': _bindings.getLastError()},
      );
      return const <MonitorInfo>[];
    }

    final handles = List<int>.of(_enumeratedMonitors);
    _enumeratedMonitors.clear();

    final result = <MonitorInfo>[];
    for (var i = 0; i < handles.length; i++) {
      final monitor = _describe(handles[i], ordinal: i + 1);
      if (monitor != null) result.add(monitor);
    }

    result.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return 0;
    });
    return result;
  }

  /// Builds a [MonitorInfo] for one `HMONITOR`, or null if Windows refuses.
  MonitorInfo? _describe(int handle, {required int ordinal}) {
    _monitorInfo.ref.cbSize = sizeOf<MONITORINFOEXW>();
    if (_bindings.getMonitorInfo(handle, _monitorInfo) == 0) return null;

    final info = _monitorInfo.ref;
    final rect = info.rcMonitor;

    // `szDevice` is a fixed 32-unit array, NUL-padded rather than NUL-checked
    // by the caller. Reading all 32 units would append the padding to the name.
    final buffer = StringBuffer();
    for (var i = 0; i < CCHDEVICENAME; i++) {
      final unit = info.szDevice[i];
      if (unit == 0) break;
      buffer.writeCharCode(unit);
    }
    final device = buffer.toString();

    var scale = 1.0;
    final dpiFor = _bindings.getDpiForMonitor;
    if (dpiFor != null) {
      final dpiX = calloc<Uint32>();
      final dpiY = calloc<Uint32>();
      try {
        if (dpiFor(handle, MDT_EFFECTIVE_DPI, dpiX, dpiY) == 0) {
          scale = dpiX.value / USER_DEFAULT_SCREEN_DPI;
        }
      } finally {
        calloc
          ..free(dpiX)
          ..free(dpiY);
      }
    }

    return MonitorInfo(
      id: _stableId(device),
      bounds: ScreenBounds(
        x: rect.left,
        y: rect.top,
        width: rect.right - rect.left,
        height: rect.bottom - rect.top,
        scaleFactor: scale,
      ),
      // `\\.\DISPLAY1` is an adapter path, not something to show a user.
      name: _friendlyName(device, ordinal),
      isPrimary: info.dwFlags & MONITORINFOF_PRIMARY != 0,
    );
  }

  static String _friendlyName(String device, int ordinal) {
    const prefix = r'\\.\DISPLAY';
    if (device.startsWith(prefix) && device.length > prefix.length) {
      return 'Display ${device.substring(prefix.length)}';
    }
    return device.isEmpty ? 'Display $ordinal' : device;
  }

  /// A stable non-zero id derived from the adapter name.
  ///
  /// The obvious candidate — `HMONITOR` — is documented as not persistent, and
  /// in practice changes when a display is turned off and on again. A phone
  /// holding an id across that would address a monitor that no longer exists.
  /// `\\.\DISPLAYn` survives it, so its FNV-1a hash is used as the id: the
  /// value is opaque to both sides and only ever compared for equality.
  static int _stableId(String device) {
    var hash = 0x811c9dc5;
    for (final unit in device.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    // Zero is reserved on the wire for "the whole virtual desktop", so a
    // display must never claim it. Collapsing to 1 is fine — an id only has to
    // be distinct from the *other* monitors present.
    return hash == 0 ? 1 : hash;
  }

  @override
  ScreenBounds get virtualBounds => ScreenBounds(
        x: _bindings.getSystemMetrics(SM_XVIRTUALSCREEN),
        y: _bindings.getSystemMetrics(SM_YVIRTUALSCREEN),
        width: _bindings.getSystemMetrics(SM_CXVIRTUALSCREEN),
        height: _bindings.getSystemMetrics(SM_CYVIRTUALSCREEN),
      );

  @override
  void dispose() {
    if (_disposed) return;
    releaseAll();
    _disposed = true;
    calloc
      ..free(_batch)
      ..free(_point)
      ..free(_monitorInfo);
  }
}

/// Handles collected by [_collectMonitor] during one `EnumDisplayMonitors` call.
final List<int> _enumeratedMonitors = <int>[];

/// `MONITORENUMPROC`. Must be a static target: `Pointer.fromFunction` cannot
/// take a closure, which is why the results land in a library-private list
/// instead of being appended to an instance field.
int _collectMonitor(int hMonitor, int hdc, Pointer<RECT> clip, int data) {
  if (_enumeratedMonitors.length >= Win32InputBackend._maxMonitors) return 0;
  _enumeratedMonitors.add(hMonitor);
  return 1;
}
