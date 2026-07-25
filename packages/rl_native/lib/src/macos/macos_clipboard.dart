import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';

import '../input_backend.dart';

/// Objective-C runtime handles.
typedef _Id = Pointer<Void>;
typedef _Sel = Pointer<Void>;

typedef _ObjcGetClassNative = _Id Function(Pointer<Utf8> name);
typedef _ObjcGetClassDart = _Id Function(Pointer<Utf8> name);

typedef _SelRegisterNameNative = _Sel Function(Pointer<Utf8> name);
typedef _SelRegisterNameDart = _Sel Function(Pointer<Utf8> name);

typedef _ObjcRetainNative = _Id Function(_Id object);
typedef _ObjcRetainDart = _Id Function(_Id object);

typedef _ObjcReleaseNative = Void Function(_Id object);
typedef _ObjcReleaseDart = void Function(_Id object);

// `objc_msgSend` has no single signature — it is dispatched by the compiler
// against the selector's actual type. Each call site below therefore looks the
// symbol up again under the signature it needs. This is the standard and only
// way to reach Objective-C from `dart:ffi` without a generated wrapper.
typedef _MsgSend0Native = _Id Function(_Id target, _Sel selector);
typedef _MsgSend0Dart = _Id Function(_Id target, _Sel selector);

typedef _MsgSend0IntNative = Int64 Function(_Id target, _Sel selector);
typedef _MsgSend0IntDart = int Function(_Id target, _Sel selector);

typedef _MsgSend1Native = _Id Function(_Id target, _Sel selector, _Id argument);
typedef _MsgSend1Dart = _Id Function(_Id target, _Sel selector, _Id argument);

typedef _MsgSend1CStrNative = _Id Function(
    _Id target, _Sel selector, Pointer<Utf8> argument);
typedef _MsgSend1CStrDart = _Id Function(
    _Id target, _Sel selector, Pointer<Utf8> argument);

typedef _MsgSend1BoolNative = Bool Function(
    _Id target, _Sel selector, _Id argument);
typedef _MsgSend1BoolDart = bool Function(
    _Id target, _Sel selector, _Id argument);

typedef _MsgSend2BoolNative = Bool Function(
    _Id target, _Sel selector, _Id first, _Id second);
typedef _MsgSend2BoolDart = bool Function(
    _Id target, _Sel selector, _Id first, _Id second);

typedef _MsgSend0CStrNative = Pointer<Utf8> Function(_Id target, _Sel selector);
typedef _MsgSend0CStrDart = Pointer<Utf8> Function(_Id target, _Sel selector);

/// macOS clipboard access through `NSPasteboard`.
///
/// `NSPasteboard` is Objective-C with no C-level API, so this goes through
/// `objc_msgSend` directly. The alternative — shelling out to `pbpaste` and
/// `pbcopy` — was rejected on latency: spawning a process costs 20 to 40 ms,
/// which alone would consume most of the sub-100 ms clipboard sync budget, and
/// it would do so on every poll.
///
/// As on Windows, change detection is a counter poll rather than a
/// notification. `NSPasteboard.changeCount` increments on every clipboard
/// change from any application, and reading it is a cheap message send, so a
/// 50 ms poll is negligible. AppKit has no clipboard-changed notification at
/// all, so this is not merely the simpler option — it is the only one.
final class MacosClipboardBackend implements ClipboardBackend {
  MacosClipboardBackend()
      : _objc = DynamicLibrary.open(
          '/usr/lib/libobjc.A.dylib',
        ),
        _appKit = DynamicLibrary.open(
          '/System/Library/Frameworks/AppKit.framework/AppKit',
        ) {
    _getClass = _objc
        .lookupFunction<_ObjcGetClassNative, _ObjcGetClassDart>(
            'objc_getClass');
    _registerSelector =
        _objc.lookupFunction<_SelRegisterNameNative, _SelRegisterNameDart>(
            'sel_registerName');
    _retain = _objc
        .lookupFunction<_ObjcRetainNative, _ObjcRetainDart>('objc_retain');
    _release = _objc
        .lookupFunction<_ObjcReleaseNative, _ObjcReleaseDart>('objc_release');

    _send0 = _objc.lookupFunction<_MsgSend0Native, _MsgSend0Dart>(
      'objc_msgSend',
    );
    _send0Int = _objc.lookupFunction<_MsgSend0IntNative, _MsgSend0IntDart>(
      'objc_msgSend',
    );
    _send1 = _objc.lookupFunction<_MsgSend1Native, _MsgSend1Dart>(
      'objc_msgSend',
    );
    _send1CStr = _objc.lookupFunction<_MsgSend1CStrNative, _MsgSend1CStrDart>(
      'objc_msgSend',
    );
    _send1Bool = _objc.lookupFunction<_MsgSend1BoolNative, _MsgSend1BoolDart>(
      'objc_msgSend',
    );
    _send2Bool = _objc.lookupFunction<_MsgSend2BoolNative, _MsgSend2BoolDart>(
      'objc_msgSend',
    );
    _send0CStr = _objc.lookupFunction<_MsgSend0CStrNative, _MsgSend0CStrDart>(
      'objc_msgSend',
    );

    _nsPasteboard = _classNamed('NSPasteboard');
    _nsString = _classNamed('NSString');

    _selGeneralPasteboard = _selector('generalPasteboard');
    _selChangeCount = _selector('changeCount');
    _selStringForType = _selector('stringForType:');
    _selSetStringForType = _selector('setString:forType:');
    _selClearContents = _selector('clearContents');
    _selUtf8String = _selector('UTF8String');
    _selStringWithUtf8 = _selector('stringWithUTF8String:');
    _selTypes = _selector('types');
    _selContainsObject = _selector('containsObject:');

    // `NSPasteboardTypeString` is an exported `NSString *` constant, so the
    // symbol holds a pointer to the object rather than being the object.
    final typeSymbol = _appKit.lookup<Pointer<Void>>('NSPasteboardTypeString');
    _typeString = typeSymbol.value;

    // ── Ownership: this is the part that must not be got wrong ──────────────
    //
    // Calling Objective-C through FFI means there is no ARC. `+generalPasteboard`
    // and `+stringWithUTF8String:` both return *autoreleased* references, and
    // the main thread's runloop drains its autorelease pool on every iteration.
    // Storing them in fields without retaining leaves dangling pointers the
    // moment control returns to the event loop — the next message send reads a
    // freed object's `isa`, and ARM64 pointer authentication turns that into an
    // immediate EXC_BREAKPOINT rather than silent corruption.
    //
    // These two live for the lifetime of the backend, so they are retained here
    // and released in `dispose`. `_typeString` is exempt: it is read from an
    // exported framework symbol and is a constant that outlives the process.
    _pasteboard = _retain(_send0(_nsPasteboard, _selGeneralPasteboard));
    _concealedType = _retain(_makeString('org.nspasteboard.ConcealedType'));
  }

  final DynamicLibrary _objc;
  final DynamicLibrary _appKit;
  final Log _log = Log.scoped('native.clipboard.macos');

  late final _ObjcGetClassDart _getClass;
  late final _SelRegisterNameDart _registerSelector;
  late final _ObjcRetainDart _retain;
  late final _ObjcReleaseDart _release;
  late final _MsgSend0Dart _send0;
  late final _MsgSend0IntDart _send0Int;
  late final _MsgSend1Dart _send1;
  late final _MsgSend1CStrDart _send1CStr;
  late final _MsgSend1BoolDart _send1Bool;
  late final _MsgSend2BoolDart _send2Bool;
  late final _MsgSend0CStrDart _send0CStr;

  late final _Id _nsPasteboard;
  late final _Id _nsString;
  late final _Id _pasteboard;
  late final _Id _typeString;
  late final _Id _concealedType;

  late final _Sel _selGeneralPasteboard;
  late final _Sel _selChangeCount;
  late final _Sel _selStringForType;
  late final _Sel _selSetStringForType;
  late final _Sel _selClearContents;
  late final _Sel _selUtf8String;
  late final _Sel _selStringWithUtf8;
  late final _Sel _selTypes;
  late final _Sel _selContainsObject;

  bool _disposed = false;

  _Id _classNamed(String name) {
    final native = name.toNativeUtf8();
    try {
      return _getClass(native);
    } finally {
      calloc.free(native);
    }
  }

  _Sel _selector(String name) {
    final native = name.toNativeUtf8();
    try {
      return _registerSelector(native);
    } finally {
      calloc.free(native);
    }
  }

  /// Builds an autoreleased `NSString` from Dart text.
  _Id _makeString(String value) {
    final native = value.toNativeUtf8();
    try {
      return _send1CStr(_nsString, _selStringWithUtf8, native);
    } finally {
      calloc.free(native);
    }
  }

  @override
  bool get isAvailable => !_disposed && _pasteboard != nullptr;

  @override
  int get changeCount =>
      _pasteboard == nullptr ? 0 : _send0Int(_pasteboard, _selChangeCount);

  @override
  bool get isConcealed {
    if (!isAvailable) return false;
    final types = _send0(_pasteboard, _selTypes);
    if (types == nullptr) return false;
    return _send1Bool(types, _selContainsObject, _concealedType);
  }

  @override
  String? readText() {
    if (!isAvailable) return null;

    final value = _send1(_pasteboard, _selStringForType, _typeString);
    if (value == nullptr) return null;

    final utf8Pointer = _send0CStr(value, _selUtf8String);
    if (utf8Pointer == nullptr) return null;

    try {
      return utf8Pointer.toDartString();
    } on FormatException catch (e) {
      _log.debug(() => 'clipboard text was not valid UTF-8: $e');
      return null;
    }
  }

  @override
  void writeText(String text) {
    if (!isAvailable) return;

    // clearContents must precede setString:forType:, and it also bumps
    // changeCount — which the clipboard watcher relies on to notice its own
    // write and suppress the echo back to the phone.
    _send0(_pasteboard, _selClearContents);

    final value = _makeString(text);
    if (value == nullptr) return;

    _send2Bool(_pasteboard, _selSetStringForType, value, _typeString);
  }

  @override
  List<int>? readImagePng() {
    // Requires NSPasteboardTypePNG plus NSImage round-tripping. Deferred to the
    // clipboard-image milestone rather than shipping a lossy conversion.
    return null;
  }

  @override
  void writeImagePng(List<int> pngBytes) {
    // Symmetrically deferred.
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    // Balances the retains in the constructor. Skipping this leaks two objects
    // per backend — trivial in practice, but an unbalanced retain is the kind
    // of thing that makes the next person distrust the whole file.
    _release(_pasteboard);
    _release(_concealedType);
  }
}
