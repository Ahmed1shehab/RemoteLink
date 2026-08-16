import 'dart:ffi';
import 'dart:typed_data';

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

typedef _MsgSend0PtrNative = Pointer<Void> Function(_Id target, _Sel selector);
typedef _MsgSend0PtrDart = Pointer<Void> Function(_Id target, _Sel selector);

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

typedef _MsgSend2IntNative = _Id Function(
    _Id target, _Sel selector, Uint64 first, _Id second);
typedef _MsgSend2IntDart = _Id Function(
    _Id target, _Sel selector, int first, _Id second);

typedef _MsgSend2PtrIntNative = _Id Function(
    _Id target, _Sel selector, Pointer<Void> bytes, IntPtr length);
typedef _MsgSend2PtrIntDart = _Id Function(
    _Id target, _Sel selector, Pointer<Void> bytes, int length);

typedef _MsgSend3PtrNative = _Id Function(
    _Id target, _Sel selector, Pointer<Void> p1, _Id p2, _Id p3);
typedef _MsgSend3PtrDart = _Id Function(
    _Id target, _Sel selector, Pointer<Void> p1, _Id p2, _Id p3);

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
    _getClass = _objc.lookupFunction<_ObjcGetClassNative, _ObjcGetClassDart>(
        'objc_getClass');
    _registerSelector =
        _objc.lookupFunction<_SelRegisterNameNative, _SelRegisterNameDart>(
            'sel_registerName');
    _retain =
        _objc.lookupFunction<_ObjcRetainNative, _ObjcRetainDart>('objc_retain');
    _release = _objc
        .lookupFunction<_ObjcReleaseNative, _ObjcReleaseDart>('objc_release');

    _send0 = _objc.lookupFunction<_MsgSend0Native, _MsgSend0Dart>(
      'objc_msgSend',
    );
    _send0Int = _objc.lookupFunction<_MsgSend0IntNative, _MsgSend0IntDart>(
      'objc_msgSend',
    );
    _send0Ptr = _objc.lookupFunction<_MsgSend0PtrNative, _MsgSend0PtrDart>(
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
    _send2Int = _objc.lookupFunction<_MsgSend2IntNative, _MsgSend2IntDart>(
      'objc_msgSend',
    );
    _send2PtrInt =
        _objc.lookupFunction<_MsgSend2PtrIntNative, _MsgSend2PtrIntDart>(
      'objc_msgSend',
    );
    _send3Ptr = _objc.lookupFunction<_MsgSend3PtrNative, _MsgSend3PtrDart>(
      'objc_msgSend',
    );
    _send0CStr = _objc.lookupFunction<_MsgSend0CStrNative, _MsgSend0CStrDart>(
      'objc_msgSend',
    );

    _nsPasteboard = _classNamed('NSPasteboard');
    _nsString = _classNamed('NSString');
    _nsImage = _classNamed('NSImage');
    _nsBitmapImageRep = _classNamed('NSBitmapImageRep');
    _nsDictionary = _classNamed('NSDictionary');
    _nsData = _classNamed('NSData');

    _selGeneralPasteboard = _selector('generalPasteboard');
    _selChangeCount = _selector('changeCount');
    _selStringForType = _selector('stringForType:');
    _selSetStringForType = _selector('setString:forType:');
    _selClearContents = _selector('clearContents');
    _selUtf8String = _selector('UTF8String');
    _selStringWithUtf8 = _selector('stringWithUTF8String:');
    _selTypes = _selector('types');
    _selContainsObject = _selector('containsObject:');
    _selDataForType = _selector('dataForType:');
    _selSetDataForType = _selector('setData:forType:');
    _selCanInitWithPasteboard = _selector('canInitWithPasteboard:');
    _selAlloc = _selector('alloc');
    _selInitWithPasteboard = _selector('initWithPasteboard:');
    _selTIFFRepresentation = _selector('TIFFRepresentation');
    _selImageRepWithData = _selector('imageRepWithData:');
    _selCGImageForProposedRect =
        _selector('CGImageForProposedRect:context:hints:');
    _selInitWithCGImage = _selector('initWithCGImage:');
    _selRepresentationUsingTypeProperties =
        _selector('representationUsingType:properties:');
    _selDictionary = _selector('dictionary');
    _selDataWithBytesLength = _selector('dataWithBytes:length:');
    _selLength = _selector('length');
    _selBytes = _selector('bytes');

    // `NSPasteboardTypeString` and `NSPasteboardTypePNG` are exported `NSString *`
    // constants, so the symbols hold pointers to the objects rather than being
    // the objects.
    final typeSymbol = _appKit.lookup<Pointer<Void>>('NSPasteboardTypeString');
    _typeString = typeSymbol.value;

    final typePngSymbol = _appKit.lookup<Pointer<Void>>('NSPasteboardTypePNG');
    _typePng = typePngSymbol.value;

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
    // and released in `dispose`. `_typeString` and `_typePng` are exempt: they
    // are read from exported framework symbols and are constants that outlive
    // the process.
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
  late final _MsgSend0PtrDart _send0Ptr;
  late final _MsgSend1Dart _send1;
  late final _MsgSend1CStrDart _send1CStr;
  late final _MsgSend1BoolDart _send1Bool;
  late final _MsgSend2BoolDart _send2Bool;
  late final _MsgSend2IntDart _send2Int;
  late final _MsgSend2PtrIntDart _send2PtrInt;
  late final _MsgSend3PtrDart _send3Ptr;
  late final _MsgSend0CStrDart _send0CStr;

  late final _Id _nsPasteboard;
  late final _Id _nsString;
  late final _Id _nsImage;
  late final _Id _nsBitmapImageRep;
  late final _Id _nsDictionary;
  late final _Id _nsData;
  late final _Id _pasteboard;
  late final _Id _typeString;
  late final _Id _typePng;
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
  late final _Sel _selDataForType;
  late final _Sel _selSetDataForType;
  late final _Sel _selCanInitWithPasteboard;
  late final _Sel _selAlloc;
  late final _Sel _selInitWithPasteboard;
  late final _Sel _selTIFFRepresentation;
  late final _Sel _selImageRepWithData;
  late final _Sel _selCGImageForProposedRect;
  late final _Sel _selInitWithCGImage;
  late final _Sel _selRepresentationUsingTypeProperties;
  late final _Sel _selDictionary;
  late final _Sel _selDataWithBytesLength;
  late final _Sel _selLength;
  late final _Sel _selBytes;

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
    if (!isAvailable) return null;

    // 1. Direct read when pasteboard carries NSPasteboardTypePNG
    final data = _send1(_pasteboard, _selDataForType, _typePng);
    if (data != nullptr) {
      final length = _send0Int(data, _selLength);
      if (length > 0) {
        final bytesPtr = _send0Ptr(data, _selBytes);
        if (bytesPtr != nullptr) {
          return Uint8List.fromList(bytesPtr.cast<Uint8>().asTypedList(length));
        }
      }
    }

    // 2. Fallback: NSImage -> NSBitmapImageRep -> representationUsingType:NSBitmapImageFileTypePNG
    final canInit =
        _send1Bool(_nsImage, _selCanInitWithPasteboard, _pasteboard);
    if (!canInit) return null;

    final allocImage = _send0(_nsImage, _selAlloc);
    if (allocImage == nullptr) return null;
    final image = _send1(allocImage, _selInitWithPasteboard, _pasteboard);
    if (image == nullptr) return null;

    try {
      final tiffData = _send0(image, _selTIFFRepresentation);
      if (tiffData != nullptr) {
        final rep = _send1(_nsBitmapImageRep, _selImageRepWithData, tiffData);
        if (rep != nullptr) {
          final dict = _send0(_nsDictionary, _selDictionary);
          // NSBitmapImageFileTypePNG = 4
          final pngData = _send2Int(
            rep,
            _selRepresentationUsingTypeProperties,
            4,
            dict,
          );
          if (pngData != nullptr) {
            final length = _send0Int(pngData, _selLength);
            if (length > 0) {
              final bytesPtr = _send0Ptr(pngData, _selBytes);
              if (bytesPtr != nullptr) {
                return Uint8List.fromList(
                  bytesPtr.cast<Uint8>().asTypedList(length),
                );
              }
            }
          }
        }
      }

      // If TIFF representation is unavailable, attempt via CGImageForProposedRect
      final cgImage = _send3Ptr(
        image,
        _selCGImageForProposedRect,
        nullptr,
        nullptr,
        nullptr,
      );
      if (cgImage != nullptr) {
        final allocRep = _send0(_nsBitmapImageRep, _selAlloc);
        if (allocRep != nullptr) {
          final rep = _send1(allocRep, _selInitWithCGImage, cgImage);
          if (rep != nullptr) {
            try {
              final dict = _send0(_nsDictionary, _selDictionary);
              final pngData = _send2Int(
                rep,
                _selRepresentationUsingTypeProperties,
                4,
                dict,
              );
              if (pngData != nullptr) {
                final length = _send0Int(pngData, _selLength);
                if (length > 0) {
                  final bytesPtr = _send0Ptr(pngData, _selBytes);
                  if (bytesPtr != nullptr) {
                    return Uint8List.fromList(
                      bytesPtr.cast<Uint8>().asTypedList(length),
                    );
                  }
                }
              }
            } finally {
              _release(rep);
            }
          }
        }
      }

      return null;
    } finally {
      _release(image);
    }
  }

  @override
  void writeImagePng(List<int> pngBytes) {
    if (!isAvailable) return;

    _send0(_pasteboard, _selClearContents);

    final nativeBytes = calloc<Uint8>(pngBytes.length);
    try {
      nativeBytes.asTypedList(pngBytes.length).setAll(0, pngBytes);
      final nsData = _send2PtrInt(
        _nsData,
        _selDataWithBytesLength,
        nativeBytes.cast<Void>(),
        pngBytes.length,
      );
      if (nsData == nullptr) return;

      _send2Bool(_pasteboard, _selSetDataForType, nsData, _typePng);
    } finally {
      calloc.free(nativeBytes);
    }
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
