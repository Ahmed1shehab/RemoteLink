// ignore_for_file: non_constant_identifier_names
// Win32 symbols keep their documented spelling so this file can be read
// side by side with the Microsoft reference.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Raw FFI bindings to the Win32 APIs RemoteLink needs.
///
/// Hand-written rather than generated with `ffigen` for one reason: the six
/// structs and eleven functions below are the entire surface, and a hand-written
/// binding can carry the "why" comments that a generated one would erase on
/// every regeneration. If this grows past a couple of dozen symbols, generate it.
///
/// Everything here is `dart:ffi`, not a platform channel. A `MethodChannel`
/// round trip costs roughly 50 to 150 microseconds because it hops to the
/// platform thread and back through a message codec. At 240 Hz that is up to
/// 3.6% of a core spent on marshalling, and — more importantly — it adds
/// scheduling jitter to the one path where jitter is visible as a stuttering
/// cursor. An FFI call into `SendInput` is a direct call: tens of nanoseconds.

// ── Constants ────────────────────────────────────────────────────────────────

const int INPUT_MOUSE = 0;
const int INPUT_KEYBOARD = 1;

const int MOUSEEVENTF_MOVE = 0x0001;
const int MOUSEEVENTF_LEFTDOWN = 0x0002;
const int MOUSEEVENTF_LEFTUP = 0x0004;
const int MOUSEEVENTF_RIGHTDOWN = 0x0008;
const int MOUSEEVENTF_RIGHTUP = 0x0010;
const int MOUSEEVENTF_MIDDLEDOWN = 0x0020;
const int MOUSEEVENTF_MIDDLEUP = 0x0040;
const int MOUSEEVENTF_XDOWN = 0x0080;
const int MOUSEEVENTF_XUP = 0x0100;
const int MOUSEEVENTF_WHEEL = 0x0800;
const int MOUSEEVENTF_HWHEEL = 0x1000;
const int MOUSEEVENTF_VIRTUALDESK = 0x4000;
const int MOUSEEVENTF_ABSOLUTE = 0x8000;

const int XBUTTON1 = 0x0001;
const int XBUTTON2 = 0x0002;

/// One wheel notch. Scroll amounts are expressed as multiples of this.
const int WHEEL_DELTA = 120;

const int KEYEVENTF_EXTENDEDKEY = 0x0001;
const int KEYEVENTF_KEYUP = 0x0002;
const int KEYEVENTF_UNICODE = 0x0004;

const int SM_XVIRTUALSCREEN = 76;
const int SM_YVIRTUALSCREEN = 77;
const int SM_CXVIRTUALSCREEN = 78;
const int SM_CYVIRTUALSCREEN = 79;
const int SM_CXSCREEN = 0;
const int SM_CYSCREEN = 1;

const int CF_UNICODETEXT = 13;

/// `GMEM_MOVEABLE`. Clipboard buffers must be moveable global memory; the
/// clipboard takes ownership of the handle once `SetClipboardData` succeeds.
const int GMEM_MOVEABLE = 0x0002;

/// Marks the clipboard entry as not for history or cloud sync. Password
/// managers set it, and RemoteLink honours it on the way out as well as in.
const String kExcludeFromMonitoring =
    'ExcludeClipboardContentFromMonitorProcessing';

// ── Structs ──────────────────────────────────────────────────────────────────

/// `MOUSEINPUT`. On x64 this is 32 bytes: the `ULONG_PTR` forces 8-byte
/// alignment, so four bytes of padding appear after `time`. Dart FFI computes
/// that layout from the field types, matching the C ABI exactly.
final class MOUSEINPUT extends Struct {
  @Int32()
  external int dx;

  @Int32()
  external int dy;

  /// Wheel delta for `MOUSEEVENTF_WHEEL`, or the X button for `XDOWN`/`XUP`.
  @Uint32()
  external int mouseData;

  @Uint32()
  external int dwFlags;

  @Uint32()
  external int time;

  @IntPtr()
  external int dwExtraInfo;
}

/// `KEYBDINPUT`.
final class KEYBDINPUT extends Struct {
  @Uint16()
  external int wVk;

  /// UTF-16 code unit when `KEYEVENTF_UNICODE` is set, otherwise a scan code.
  @Uint16()
  external int wScan;

  @Uint32()
  external int dwFlags;

  @Uint32()
  external int time;

  @IntPtr()
  external int dwExtraInfo;
}

/// The anonymous union inside `INPUT`.
final class INPUT_UNION extends Union {
  external MOUSEINPUT mi;
  external KEYBDINPUT ki;
}

/// `INPUT`. 40 bytes on x64.
final class INPUT extends Struct {
  @Uint32()
  external int type;

  external INPUT_UNION u;
}

/// `POINT`.
final class POINT extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

// ── Function typedefs ────────────────────────────────────────────────────────

typedef _SendInputNative = Uint32 Function(
    Uint32 cInputs, Pointer<INPUT> pInputs, Int32 cbSize);
typedef _SendInputDart = int Function(
    int cInputs, Pointer<INPUT> pInputs, int cbSize);

typedef _SetCursorPosNative = Int32 Function(Int32 x, Int32 y);
typedef _SetCursorPosDart = int Function(int x, int y);

typedef _GetCursorPosNative = Int32 Function(Pointer<POINT> point);
typedef _GetCursorPosDart = int Function(Pointer<POINT> point);

typedef _GetSystemMetricsNative = Int32 Function(Int32 index);
typedef _GetSystemMetricsDart = int Function(int index);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

typedef _OpenClipboardNative = Int32 Function(IntPtr hWndNewOwner);
typedef _OpenClipboardDart = int Function(int hWndNewOwner);

typedef _CloseClipboardNative = Int32 Function();
typedef _CloseClipboardDart = int Function();

typedef _EmptyClipboardNative = Int32 Function();
typedef _EmptyClipboardDart = int Function();

typedef _GetClipboardDataNative = IntPtr Function(Uint32 format);
typedef _GetClipboardDataDart = int Function(int format);

typedef _SetClipboardDataNative = IntPtr Function(Uint32 format, IntPtr hMem);
typedef _SetClipboardDataDart = int Function(int format, int hMem);

typedef _IsClipboardFormatAvailableNative = Int32 Function(Uint32 format);
typedef _IsClipboardFormatAvailableDart = int Function(int format);

typedef _GetClipboardSequenceNumberNative = Uint32 Function();
typedef _GetClipboardSequenceNumberDart = int Function();

typedef _RegisterClipboardFormatNative = Uint32 Function(
    Pointer<Utf16> formatName);
typedef _RegisterClipboardFormatDart = int Function(Pointer<Utf16> formatName);

typedef _GlobalAllocNative = IntPtr Function(Uint32 flags, IntPtr bytes);
typedef _GlobalAllocDart = int Function(int flags, int bytes);

typedef _GlobalLockNative = Pointer<Void> Function(IntPtr hMem);
typedef _GlobalLockDart = Pointer<Void> Function(int hMem);

typedef _GlobalUnlockNative = Int32 Function(IntPtr hMem);
typedef _GlobalUnlockDart = int Function(int hMem);

typedef _GlobalFreeNative = IntPtr Function(IntPtr hMem);
typedef _GlobalFreeDart = int Function(int hMem);

typedef _GlobalSizeNative = IntPtr Function(IntPtr hMem);
typedef _GlobalSizeDart = int Function(int hMem);

/// Resolved Win32 entry points.
///
/// Looked up once at construction. Repeating `lookupFunction` per call would
/// cost a hash lookup and a trampoline allocation on the input hot path.
final class Win32Bindings {
  Win32Bindings()
      : _user32 = DynamicLibrary.open('user32.dll'),
        _kernel32 = DynamicLibrary.open('kernel32.dll') {
    sendInput =
        _user32.lookupFunction<_SendInputNative, _SendInputDart>('SendInput');
    setCursorPos = _user32
        .lookupFunction<_SetCursorPosNative, _SetCursorPosDart>('SetCursorPos');
    getCursorPos = _user32
        .lookupFunction<_GetCursorPosNative, _GetCursorPosDart>('GetCursorPos');
    getSystemMetrics =
        _user32.lookupFunction<_GetSystemMetricsNative, _GetSystemMetricsDart>(
            'GetSystemMetrics');
    getLastError =
        _kernel32.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
            'GetLastError');

    openClipboard =
        _user32.lookupFunction<_OpenClipboardNative, _OpenClipboardDart>(
            'OpenClipboard');
    closeClipboard =
        _user32.lookupFunction<_CloseClipboardNative, _CloseClipboardDart>(
            'CloseClipboard');
    emptyClipboard =
        _user32.lookupFunction<_EmptyClipboardNative, _EmptyClipboardDart>(
            'EmptyClipboard');
    getClipboardData =
        _user32.lookupFunction<_GetClipboardDataNative, _GetClipboardDataDart>(
            'GetClipboardData');
    setClipboardData =
        _user32.lookupFunction<_SetClipboardDataNative, _SetClipboardDataDart>(
            'SetClipboardData');
    isClipboardFormatAvailable = _user32.lookupFunction<
        _IsClipboardFormatAvailableNative,
        _IsClipboardFormatAvailableDart>('IsClipboardFormatAvailable');
    getClipboardSequenceNumber = _user32.lookupFunction<
        _GetClipboardSequenceNumberNative,
        _GetClipboardSequenceNumberDart>('GetClipboardSequenceNumber');
    registerClipboardFormat = _user32.lookupFunction<
        _RegisterClipboardFormatNative,
        _RegisterClipboardFormatDart>('RegisterClipboardFormatW');

    globalAlloc =
        _kernel32.lookupFunction<_GlobalAllocNative, _GlobalAllocDart>(
            'GlobalAlloc');
    globalLock = _kernel32
        .lookupFunction<_GlobalLockNative, _GlobalLockDart>('GlobalLock');
    globalUnlock = _kernel32
        .lookupFunction<_GlobalUnlockNative, _GlobalUnlockDart>('GlobalUnlock');
    globalFree = _kernel32
        .lookupFunction<_GlobalFreeNative, _GlobalFreeDart>('GlobalFree');
    globalSize = _kernel32
        .lookupFunction<_GlobalSizeNative, _GlobalSizeDart>('GlobalSize');
  }

  final DynamicLibrary _user32;
  final DynamicLibrary _kernel32;

  late final _SendInputDart sendInput;
  late final _SetCursorPosDart setCursorPos;
  late final _GetCursorPosDart getCursorPos;
  late final _GetSystemMetricsDart getSystemMetrics;
  late final _GetLastErrorDart getLastError;

  late final _OpenClipboardDart openClipboard;
  late final _CloseClipboardDart closeClipboard;
  late final _EmptyClipboardDart emptyClipboard;
  late final _GetClipboardDataDart getClipboardData;
  late final _SetClipboardDataDart setClipboardData;
  late final _IsClipboardFormatAvailableDart isClipboardFormatAvailable;
  late final _GetClipboardSequenceNumberDart getClipboardSequenceNumber;
  late final _RegisterClipboardFormatDart registerClipboardFormat;

  late final _GlobalAllocDart globalAlloc;
  late final _GlobalLockDart globalLock;
  late final _GlobalUnlockDart globalUnlock;
  late final _GlobalFreeDart globalFree;
  late final _GlobalSizeDart globalSize;
}
