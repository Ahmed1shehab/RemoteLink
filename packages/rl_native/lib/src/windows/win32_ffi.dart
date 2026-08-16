// ignore_for_file: constant_identifier_names
//
// Win32 constants keep Microsoft's SCREAMING_CAPS spelling so this file can be
// read side by side with the reference documentation, and so a value can be
// pasted from MSDN and grepped for here. Renaming `MOUSEEVENTF_LEFTDOWN` to
// `mouseeventfLeftdown` would make it harder to verify against the source of
// truth, which is the only thing that matters for a binding file.
//
// The struct names are Microsoft's too, but they need no exemption: the lint
// objects to underscores, not to capitals. The one union below is *not* a real
// Win32 name — it models an anonymous union — so it uses Dart casing.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Raw FFI bindings to the Win32 APIs RemoteLink needs.
///
/// Hand-written rather than generated with `ffigen` for one reason: the five
/// structs and eighteen functions below are the entire surface, and a
/// hand-written binding can carry the "why" comments that a generated one would
/// erase on every regeneration. If this grows much past thirty symbols, the
/// balance tips and it should be generated.
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
const int CF_DIB = 8;
const int CF_DIBV5 = 17;

const int BI_RGB = 0;
const int BI_BITFIELDS = 3;

const int LCS_sRGB = 0x73524742;
const int LCS_GM_IMAGES = 4;

const int COINIT_APARTMENTTHREADED = 0x2;
const int COINIT_MULTITHREADED = 0x0;
const int CLSCTX_INPROC_SERVER = 0x1;

const int WICBitmapEncoderNoCache = 0x2;
const int WICDecodeMetadataCacheOnDemand = 0x0;

/// `GMEM_MOVEABLE`. Clipboard buffers must be moveable global memory; the
/// clipboard takes ownership of the handle once `SetClipboardData` succeeds.
const int GMEM_MOVEABLE = 0x0002;

/// Marks the clipboard entry as not for history or cloud sync. Password
/// managers set it, and RemoteLink honours it on the way out as well as in.
const String kExcludeFromMonitoring =
    'ExcludeClipboardContentFromMonitorProcessing';

// ── Structs ──────────────────────────────────────────────────────────────────

/// Standard COM `GUID` layout (16 bytes).
final class GUID extends Struct {
  @Uint32()
  external int Data1;

  @Uint16()
  external int Data2;

  @Uint16()
  external int Data3;

  @Array(8)
  external Array<Uint8> Data4;
}

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
final class InputUnion extends Union {
  external MOUSEINPUT mi;
  external KEYBDINPUT ki;
}

/// `INPUT`. 40 bytes on x64.
final class INPUT extends Struct {
  @Uint32()
  external int type;

  external InputUnion u;
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
typedef SendInputDart = int Function(
    int cInputs, Pointer<INPUT> pInputs, int cbSize);

typedef _SetCursorPosNative = Int32 Function(Int32 x, Int32 y);
typedef SetCursorPosDart = int Function(int x, int y);

typedef _GetCursorPosNative = Int32 Function(Pointer<POINT> point);
typedef GetCursorPosDart = int Function(Pointer<POINT> point);

typedef _GetSystemMetricsNative = Int32 Function(Int32 index);
typedef GetSystemMetricsDart = int Function(int index);

typedef _GetLastErrorNative = Uint32 Function();
typedef GetLastErrorDart = int Function();

typedef _OpenClipboardNative = Int32 Function(IntPtr hWndNewOwner);
typedef OpenClipboardDart = int Function(int hWndNewOwner);

typedef _CloseClipboardNative = Int32 Function();
typedef CloseClipboardDart = int Function();

typedef _EmptyClipboardNative = Int32 Function();
typedef EmptyClipboardDart = int Function();

typedef _GetClipboardDataNative = IntPtr Function(Uint32 format);
typedef GetClipboardDataDart = int Function(int format);

typedef _SetClipboardDataNative = IntPtr Function(Uint32 format, IntPtr hMem);
typedef SetClipboardDataDart = int Function(int format, int hMem);

typedef _IsClipboardFormatAvailableNative = Int32 Function(Uint32 format);
typedef IsClipboardFormatAvailableDart = int Function(int format);

typedef _GetClipboardSequenceNumberNative = Uint32 Function();
typedef GetClipboardSequenceNumberDart = int Function();

typedef _RegisterClipboardFormatNative = Uint32 Function(
    Pointer<Utf16> formatName);
typedef RegisterClipboardFormatDart = int Function(Pointer<Utf16> formatName);

typedef _GlobalAllocNative = IntPtr Function(Uint32 flags, IntPtr bytes);
typedef GlobalAllocDart = int Function(int flags, int bytes);

typedef _GlobalLockNative = Pointer<Void> Function(IntPtr hMem);
typedef GlobalLockDart = Pointer<Void> Function(int hMem);

typedef _GlobalUnlockNative = Int32 Function(IntPtr hMem);
typedef GlobalUnlockDart = int Function(int hMem);

typedef _GlobalFreeNative = IntPtr Function(IntPtr hMem);
typedef GlobalFreeDart = int Function(int hMem);

typedef _GlobalSizeNative = IntPtr Function(IntPtr hMem);
typedef GlobalSizeDart = int Function(int hMem);

typedef _CoInitializeExNative = Int32 Function(
    Pointer<Void> pvReserved, Uint32 dwCoInit);
typedef CoInitializeExDart = int Function(
    Pointer<Void> pvReserved, int dwCoInit);

typedef _CoCreateInstanceNative = Int32 Function(
    Pointer<GUID> rclsid,
    Pointer<Void> pUnkOuter,
    Uint32 dwClsContext,
    Pointer<GUID> riid,
    Pointer<Pointer<Void>> ppv);
typedef CoCreateInstanceDart = int Function(
    Pointer<GUID> rclsid,
    Pointer<Void> pUnkOuter,
    int dwClsContext,
    Pointer<GUID> riid,
    Pointer<Pointer<Void>> ppv);

typedef _CreateStreamOnHGlobalNative = Int32 Function(
    IntPtr hGlobal, Int32 fDeleteOnRelease, Pointer<Pointer<Void>> ppstm);
typedef CreateStreamOnHGlobalDart = int Function(
    int hGlobal, int fDeleteOnRelease, Pointer<Pointer<Void>> ppstm);

typedef _GetHGlobalFromStreamNative = Int32 Function(
    Pointer<Void> pstm, Pointer<IntPtr> phglobal);
typedef GetHGlobalFromStreamDart = int Function(
    Pointer<Void> pstm, Pointer<IntPtr> phglobal);

/// Resolved Win32 entry points.
///
/// Looked up once at construction. Repeating `lookupFunction` per call would
/// cost a hash lookup and a trampoline allocation on the input hot path.
final class Win32Bindings {
  Win32Bindings()
      : _user32 = DynamicLibrary.open('user32.dll'),
        _kernel32 = DynamicLibrary.open('kernel32.dll'),
        _ole32 = DynamicLibrary.open('ole32.dll') {
    sendInput =
        _user32.lookupFunction<_SendInputNative, SendInputDart>('SendInput');
    setCursorPos = _user32
        .lookupFunction<_SetCursorPosNative, SetCursorPosDart>('SetCursorPos');
    getCursorPos = _user32
        .lookupFunction<_GetCursorPosNative, GetCursorPosDart>('GetCursorPos');
    getSystemMetrics =
        _user32.lookupFunction<_GetSystemMetricsNative, GetSystemMetricsDart>(
            'GetSystemMetrics');
    getLastError = _kernel32
        .lookupFunction<_GetLastErrorNative, GetLastErrorDart>('GetLastError');

    openClipboard =
        _user32.lookupFunction<_OpenClipboardNative, OpenClipboardDart>(
            'OpenClipboard');
    closeClipboard =
        _user32.lookupFunction<_CloseClipboardNative, CloseClipboardDart>(
            'CloseClipboard');
    emptyClipboard =
        _user32.lookupFunction<_EmptyClipboardNative, EmptyClipboardDart>(
            'EmptyClipboard');
    getClipboardData =
        _user32.lookupFunction<_GetClipboardDataNative, GetClipboardDataDart>(
            'GetClipboardData');
    setClipboardData =
        _user32.lookupFunction<_SetClipboardDataNative, SetClipboardDataDart>(
            'SetClipboardData');
    isClipboardFormatAvailable = _user32.lookupFunction<
        _IsClipboardFormatAvailableNative,
        IsClipboardFormatAvailableDart>('IsClipboardFormatAvailable');
    getClipboardSequenceNumber = _user32.lookupFunction<
        _GetClipboardSequenceNumberNative,
        GetClipboardSequenceNumberDart>('GetClipboardSequenceNumber');
    registerClipboardFormat = _user32.lookupFunction<
        _RegisterClipboardFormatNative,
        RegisterClipboardFormatDart>('RegisterClipboardFormatW');

    globalAlloc = _kernel32
        .lookupFunction<_GlobalAllocNative, GlobalAllocDart>('GlobalAlloc');
    globalLock = _kernel32
        .lookupFunction<_GlobalLockNative, GlobalLockDart>('GlobalLock');
    globalUnlock = _kernel32
        .lookupFunction<_GlobalUnlockNative, GlobalUnlockDart>('GlobalUnlock');
    globalFree = _kernel32
        .lookupFunction<_GlobalFreeNative, GlobalFreeDart>('GlobalFree');
    globalSize = _kernel32
        .lookupFunction<_GlobalSizeNative, GlobalSizeDart>('GlobalSize');

    coInitializeEx =
        _ole32.lookupFunction<_CoInitializeExNative, CoInitializeExDart>(
            'CoInitializeEx');
    coCreateInstance =
        _ole32.lookupFunction<_CoCreateInstanceNative, CoCreateInstanceDart>(
            'CoCreateInstance');
    createStreamOnHGlobal = _ole32.lookupFunction<_CreateStreamOnHGlobalNative,
        CreateStreamOnHGlobalDart>('CreateStreamOnHGlobal');
    getHGlobalFromStream = _ole32.lookupFunction<_GetHGlobalFromStreamNative,
        GetHGlobalFromStreamDart>('GetHGlobalFromStream');
  }

  final DynamicLibrary _user32;
  final DynamicLibrary _kernel32;
  final DynamicLibrary _ole32;

  late final SendInputDart sendInput;
  late final SetCursorPosDart setCursorPos;
  late final GetCursorPosDart getCursorPos;
  late final GetSystemMetricsDart getSystemMetrics;
  late final GetLastErrorDart getLastError;

  late final OpenClipboardDart openClipboard;
  late final CloseClipboardDart closeClipboard;
  late final EmptyClipboardDart emptyClipboard;
  late final GetClipboardDataDart getClipboardData;
  late final SetClipboardDataDart setClipboardData;
  late final IsClipboardFormatAvailableDart isClipboardFormatAvailable;
  late final GetClipboardSequenceNumberDart getClipboardSequenceNumber;
  late final RegisterClipboardFormatDart registerClipboardFormat;

  late final GlobalAllocDart globalAlloc;
  late final GlobalLockDart globalLock;
  late final GlobalUnlockDart globalUnlock;
  late final GlobalFreeDart globalFree;
  late final GlobalSizeDart globalSize;

  late final CoInitializeExDart coInitializeEx;
  late final CoCreateInstanceDart coCreateInstance;
  late final CreateStreamOnHGlobalDart createStreamOnHGlobal;
  late final GetHGlobalFromStreamDart getHGlobalFromStream;
}
