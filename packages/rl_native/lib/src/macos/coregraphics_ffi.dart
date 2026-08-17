// Core Graphics symbols keep Apple's spelling so this reads alongside the
// framework headers. No lint exemption is needed here: Apple's `kFoo` constant
// convention already satisfies `constant_identifier_names`, and `CGPoint` and
// friends already satisfy `camel_case_types`. Win32's SCREAMING_CAPS does not,
// which is why only the Windows binding carries an ignore directive.

import 'dart:ffi';

/// Opaque Core Foundation and Core Graphics handles.
typedef CGEventRef = Pointer<Void>;
typedef CGEventSourceRef = Pointer<Void>;
typedef CFStringRef = Pointer<Void>;

/// `CGEventType` values used here.
const int kCGEventLeftMouseDown = 1;
const int kCGEventLeftMouseUp = 2;
const int kCGEventRightMouseDown = 3;
const int kCGEventRightMouseUp = 4;
const int kCGEventMouseMoved = 5;
const int kCGEventLeftMouseDragged = 6;
const int kCGEventRightMouseDragged = 7;
const int kCGEventOtherMouseDown = 25;
const int kCGEventOtherMouseUp = 26;
const int kCGEventOtherMouseDragged = 27;

/// `CGEventType` gesture values.
const int kCGEventTypeRotate = 18;
const int kCGEventTypeMagnify = 30;
const int kCGEventTypeSwipe = 31;

/// `CGMouseButton`.
const int kCGMouseButtonLeft = 0;
const int kCGMouseButtonRight = 1;
const int kCGMouseButtonCenter = 2;

/// `CGEventField.kCGMouseEventClickState` — how many clicks this is part of.
///
/// macOS derives double-click from this field, not from timing, which is why
/// the protocol carries an explicit click count: network jitter can stretch two
/// taps past any timing threshold, and a double-tap that fails to select a word
/// is very visible.
const int kCGMouseEventClickState = 1;

/// `kCGMouseEventButtonNumber`.
const int kCGMouseEventButtonNumber = 3;

/// `kCGMouseEventDeltaX` / `kCGMouseEventDeltaY`.
///
/// Games and drawing applications read these rather than tracking absolute
/// position, so leaving them at zero makes a synthetic move invisible to them.
const int kCGMouseEventDeltaX = 4;
const int kCGMouseEventDeltaY = 5;

/// `CGScrollEventUnit`.
const int kCGScrollEventUnitPixel = 0;
const int kCGScrollEventUnitLine = 1;

/// `CGEventTapLocation.kCGHIDEventTap`.
///
/// Posting at the HID level makes events behave like real hardware: they pass
/// through the window server's own processing, respect the active keyboard
/// layout, and reach every application including the login window. Posting at
/// the session or annotated-session level would skip parts of that pipeline.
const int kCGHIDEventTap = 0;

/// `CGEventSourceStateID.kCGEventSourceStateHIDSystemState`.
///
/// Ties synthetic events to the same state the physical keyboard uses, so a
/// modifier held by RemoteLink combines correctly with a key pressed on the
/// desktop's own keyboard.
const int kCGEventSourceStateHIDSystemState = 1;

/// `CGPoint`. Two doubles; Core Graphics uses floating-point screen space.
final class CGPoint extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;
}

/// `CGSize`.
final class CGSize extends Struct {
  @Double()
  external double width;

  @Double()
  external double height;
}

/// `CGRect`.
final class CGRect extends Struct {
  external CGPoint origin;
  external CGSize size;
}

typedef _CGEventSourceCreateNative = CGEventSourceRef Function(Int32 stateID);
typedef CGEventSourceCreateDart = CGEventSourceRef Function(int stateID);

typedef _CGEventCreateMouseEventNative = CGEventRef Function(
  CGEventSourceRef source,
  Int32 mouseType,
  CGPoint mouseCursorPosition,
  Int32 mouseButton,
);
typedef CGEventCreateMouseEventDart = CGEventRef Function(
  CGEventSourceRef source,
  int mouseType,
  CGPoint mouseCursorPosition,
  int mouseButton,
);

typedef _CGEventCreateKeyboardEventNative = CGEventRef Function(
  CGEventSourceRef source,
  Uint16 virtualKey,
  Bool keyDown,
);
typedef CGEventCreateKeyboardEventDart = CGEventRef Function(
  CGEventSourceRef source,
  int virtualKey,
  bool keyDown,
);

typedef _CGEventCreateScrollWheelEventNative = CGEventRef Function(
  CGEventSourceRef source,
  Int32 units,
  Uint32 wheelCount,
  Int32 wheel1,
  Int32 wheel2,
);
typedef CGEventCreateScrollWheelEventDart = CGEventRef Function(
  CGEventSourceRef source,
  int units,
  int wheelCount,
  int wheel1,
  int wheel2,
);

typedef _CGEventPostNative = Void Function(Int32 tap, CGEventRef event);
typedef CGEventPostDart = void Function(int tap, CGEventRef event);

typedef _CGEventSetFlagsNative = Void Function(CGEventRef event, Uint64 flags);
typedef CGEventSetFlagsDart = void Function(CGEventRef event, int flags);

typedef _CGEventSetTypeNative = Void Function(CGEventRef event, Int32 type);
typedef CGEventSetTypeDart = void Function(CGEventRef event, int type);

typedef _CGEventSetDoubleValueFieldNative = Void Function(
    CGEventRef event, Int32 field, Double value);
typedef CGEventSetDoubleValueFieldDart = void Function(
    CGEventRef event, int field, double value);

typedef _CGEventSetLocationNative = Void Function(
    CGEventRef event, CGPoint location);
typedef CGEventSetLocationDart = void Function(
    CGEventRef event, CGPoint location);

typedef _CGEventSetIntegerValueFieldNative = Void Function(
    CGEventRef event, Int32 field, Int64 value);
typedef CGEventSetIntegerValueFieldDart = void Function(
    CGEventRef event, int field, int value);

typedef _CGEventKeyboardSetUnicodeStringNative = Void Function(
  CGEventRef event,
  IntPtr stringLength,
  Pointer<Uint16> unicodeString,
);
typedef CGEventKeyboardSetUnicodeStringDart = void Function(
  CGEventRef event,
  int stringLength,
  Pointer<Uint16> unicodeString,
);

typedef _CGEventGetLocationNative = CGPoint Function(CGEventRef event);
typedef CGEventGetLocationDart = CGPoint Function(CGEventRef event);

typedef _CGEventCreateNative = CGEventRef Function(CGEventSourceRef source);
typedef CGEventCreateDart = CGEventRef Function(CGEventSourceRef source);

typedef _CFReleaseNative = Void Function(Pointer<Void> ref);
typedef CFReleaseDart = void Function(Pointer<Void> ref);

typedef _CGMainDisplayIDNative = Uint32 Function();
typedef CGMainDisplayIDDart = int Function();

typedef _CGDisplayBoundsNative = CGRect Function(Uint32 display);
typedef CGDisplayBoundsDart = CGRect Function(int display);

typedef _CGDisplayPixelsWideNative = IntPtr Function(Uint32 display);
typedef CGDisplayPixelsWideDart = int Function(int display);

/// `CGGetActiveDisplayList(maxDisplays, displays, displayCount)`.
///
/// "Active" rather than "online" is the right list: it excludes displays that
/// are mirroring another one, which would otherwise appear as a second monitor
/// occupying the same rectangle — a screen picker with two entries the user
/// cannot tell apart, one of which does nothing distinguishable.
typedef _CGGetActiveDisplayListNative = Int32 Function(
  Uint32 maxDisplays,
  Pointer<Uint32> activeDisplays,
  Pointer<Uint32> displayCount,
);
typedef CGGetActiveDisplayListDart = int Function(
  int maxDisplays,
  Pointer<Uint32> activeDisplays,
  Pointer<Uint32> displayCount,
);

typedef _CGDisplayIsBuiltinNative = Uint32 Function(Uint32 display);
typedef CGDisplayIsBuiltinDart = int Function(int display);

typedef _CGDisplayIsMainNative = Uint32 Function(Uint32 display);
typedef CGDisplayIsMainDart = int Function(int display);

typedef _AXIsProcessTrustedNative = Bool Function();
typedef AXIsProcessTrustedDart = bool Function();

/// Resolved Core Graphics entry points.
final class CoreGraphicsBindings {
  CoreGraphicsBindings()
      : _coreGraphics = DynamicLibrary.open(
          '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
        ),
        _coreFoundation = DynamicLibrary.open(
          '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
        ),
        _applicationServices = DynamicLibrary.open(
          '/System/Library/Frameworks/ApplicationServices.framework/'
          'ApplicationServices',
        ) {
    eventSourceCreate = _coreGraphics.lookupFunction<_CGEventSourceCreateNative,
        CGEventSourceCreateDart>('CGEventSourceCreate');
    createMouseEvent = _coreGraphics.lookupFunction<
        _CGEventCreateMouseEventNative,
        CGEventCreateMouseEventDart>('CGEventCreateMouseEvent');
    createKeyboardEvent = _coreGraphics.lookupFunction<
        _CGEventCreateKeyboardEventNative,
        CGEventCreateKeyboardEventDart>('CGEventCreateKeyboardEvent');
    createScrollEvent = _coreGraphics.lookupFunction<
        _CGEventCreateScrollWheelEventNative,
        CGEventCreateScrollWheelEventDart>('CGEventCreateScrollWheelEvent');
    post = _coreGraphics
        .lookupFunction<_CGEventPostNative, CGEventPostDart>('CGEventPost');
    setFlags = _coreGraphics.lookupFunction<_CGEventSetFlagsNative,
        CGEventSetFlagsDart>('CGEventSetFlags');
    setType =
        _coreGraphics.lookupFunction<_CGEventSetTypeNative, CGEventSetTypeDart>(
            'CGEventSetType');
    setDoubleValueField = _coreGraphics.lookupFunction<
        _CGEventSetDoubleValueFieldNative,
        CGEventSetDoubleValueFieldDart>('CGEventSetDoubleValueField');
    setLocation = _coreGraphics.lookupFunction<_CGEventSetLocationNative,
        CGEventSetLocationDart>('CGEventSetLocation');
    setIntegerValueField = _coreGraphics.lookupFunction<
        _CGEventSetIntegerValueFieldNative,
        CGEventSetIntegerValueFieldDart>('CGEventSetIntegerValueField');
    setUnicodeString = _coreGraphics.lookupFunction<
        _CGEventKeyboardSetUnicodeStringNative,
        CGEventKeyboardSetUnicodeStringDart>('CGEventKeyboardSetUnicodeString');
    getLocation = _coreGraphics.lookupFunction<_CGEventGetLocationNative,
        CGEventGetLocationDart>('CGEventGetLocation');
    createEvent =
        _coreGraphics.lookupFunction<_CGEventCreateNative, CGEventCreateDart>(
            'CGEventCreate');
    mainDisplayId = _coreGraphics.lookupFunction<_CGMainDisplayIDNative,
        CGMainDisplayIDDart>('CGMainDisplayID');
    displayBounds = _coreGraphics.lookupFunction<_CGDisplayBoundsNative,
        CGDisplayBoundsDart>('CGDisplayBounds');
    displayPixelsWide = _coreGraphics.lookupFunction<_CGDisplayPixelsWideNative,
        CGDisplayPixelsWideDart>('CGDisplayPixelsWide');
    getActiveDisplayList = _coreGraphics.lookupFunction<
        _CGGetActiveDisplayListNative,
        CGGetActiveDisplayListDart>('CGGetActiveDisplayList');
    displayIsBuiltin = _coreGraphics.lookupFunction<_CGDisplayIsBuiltinNative,
        CGDisplayIsBuiltinDart>('CGDisplayIsBuiltin');
    displayIsMain = _coreGraphics.lookupFunction<_CGDisplayIsMainNative,
        CGDisplayIsMainDart>('CGDisplayIsMain');

    release = _coreFoundation
        .lookupFunction<_CFReleaseNative, CFReleaseDart>('CFRelease');

    isProcessTrusted = _applicationServices.lookupFunction<
        _AXIsProcessTrustedNative,
        AXIsProcessTrustedDart>('AXIsProcessTrusted');
  }

  final DynamicLibrary _coreGraphics;
  final DynamicLibrary _coreFoundation;
  final DynamicLibrary _applicationServices;

  late final CGEventSourceCreateDart eventSourceCreate;
  late final CGEventCreateMouseEventDart createMouseEvent;
  late final CGEventCreateKeyboardEventDart createKeyboardEvent;
  late final CGEventCreateScrollWheelEventDart createScrollEvent;
  late final CGEventPostDart post;
  late final CGEventSetFlagsDart setFlags;
  late final CGEventSetTypeDart setType;
  late final CGEventSetDoubleValueFieldDart setDoubleValueField;
  late final CGEventSetLocationDart setLocation;
  late final CGEventSetIntegerValueFieldDart setIntegerValueField;
  late final CGEventKeyboardSetUnicodeStringDart setUnicodeString;
  late final CGEventGetLocationDart getLocation;
  late final CGEventCreateDart createEvent;
  late final CGMainDisplayIDDart mainDisplayId;
  late final CGDisplayBoundsDart displayBounds;
  late final CGDisplayPixelsWideDart displayPixelsWide;
  late final CGGetActiveDisplayListDart getActiveDisplayList;
  late final CGDisplayIsBuiltinDart displayIsBuiltin;
  late final CGDisplayIsMainDart displayIsMain;
  late final CFReleaseDart release;

  /// Whether the process holds Accessibility permission.
  ///
  /// Without it every `CGEventPost` silently does nothing — no error, no
  /// exception, just a cursor that will not move. Checking up front is the only
  /// way to tell the user what is wrong instead of leaving them with a remote
  /// that appears connected and does not work.
  late final AXIsProcessTrustedDart isProcessTrusted;
}
