import 'package:meta/meta.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';

/// Physical mouse buttons.
enum MouseButton {
  left(1),
  right(2),
  middle(3),

  /// Browser "back" on most mice.
  back(4),

  /// Browser "forward" on most mice.
  forward(5);

  const MouseButton(this.wireValue);

  final int wireValue;

  static MouseButton fromWire(int value) => values.firstWhere(
        (button) => button.wireValue == value,
        orElse: () => MouseButton.left,
      );
}

/// Relative cursor movement.
///
/// The single highest-frequency message in the protocol, so its encoding is
/// tuned hard: two zig-zag varints put a typical `(±3, ±5)` delta into two
/// bytes. With the 20-byte frame header a movement event is 22 bytes on the
/// wire, small enough that a 240 Hz stream costs about 42 kbit/s.
///
/// Deltas are integers in *device* units. All smoothing, acceleration, and
/// sensitivity scaling happen on the phone before encoding, for two reasons:
/// the phone knows its own DPI and gesture velocity, and keeping the desktop
/// side a dumb executor means tuning ships in a mobile update rather than
/// requiring both sides to move in lockstep.
@immutable
final class MouseMove extends Message {
  const MouseMove({required this.deltaX, required this.deltaY});

  final int deltaX;
  final int deltaY;

  @override
  MessageType get type => MessageType.mouseMove;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeVarInt(deltaX)
      ..writeVarInt(deltaY);
  }

  static MouseMove readFrom(ByteReader reader) => MouseMove(
        deltaX: reader.readVarInt(),
        deltaY: reader.readVarInt(),
      );

  /// Sums two consecutive moves.
  ///
  /// Used for coalescing: when the send queue backs up, several pending moves
  /// collapse into one. Because movement is relative, this is exactly
  /// equivalent to delivering them all, and it keeps the cursor from lagging
  /// behind the finger during a network hiccup.
  MouseMove merge(MouseMove next) =>
      MouseMove(deltaX: deltaX + next.deltaX, deltaY: deltaY + next.deltaY);

  @override
  String toString() => 'MouseMove($deltaX, $deltaY)';
}

/// Absolute cursor position in normalised screen coordinates.
///
/// Coordinates are `[0.0, 1.0]` rather than pixels, so a phone driving a 4K
/// monitor and a 1080p one sends identical bytes and the desktop resolves
/// against its own current topology. This also survives the user changing
/// resolution mid-session.
///
/// [monitorId] says *what* they are normalised against. Without it, `(0.5,
/// 0.5)` means the centre of the whole virtual desktop — which on a
/// two-monitor desk is the seam between the screens, so a tap aimed at the
/// middle of the left monitor lands nowhere near it. Naming a monitor makes the
/// pair unambiguous again.
@immutable
final class MouseMoveAbsolute extends Message {
  const MouseMoveAbsolute({
    required this.x,
    required this.y,
    this.displayIndex = 0,
    this.monitorId = 0,
  });

  final double x;
  final double y;

  /// Superseded by [monitorId]; still written because it has shipped.
  ///
  /// Nothing has ever read it. Giving it a meaning now would be the silent kind
  /// of breaking change the append-only rule exists to prevent — every deployed
  /// phone sends `0` here and expects virtual-desktop coordinates, so
  /// re-interpreting `0` as "the primary monitor" would move where their taps
  /// land without a single byte changing. It stays on the wire, unread, and the
  /// stable id below carries the real meaning.
  final int displayIndex;

  /// Id of the monitor these coordinates address, from the most recent
  /// `screenTopology`; `0` for the whole virtual desktop.
  ///
  /// Appended after [displayIndex], per PROTOCOL.md §5 — a peer that predates
  /// this field simply omits it, and its absence decodes as `0`, which is
  /// exactly the behaviour it already had.
  ///
  /// An id rather than an index because indices renumber: unplug the first of
  /// three monitors and a phone still holding "display 1" starts driving a
  /// different screen with no error anywhere.
  final int monitorId;

  @override
  MessageType get type => MessageType.mouseMoveAbsolute;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeFloat32(x)
      ..writeFloat32(y)
      ..writeVarUint(displayIndex)
      ..writeVarUint(monitorId);
  }

  static MouseMoveAbsolute readFrom(ByteReader reader) {
    final x = reader.readFloat32();
    final y = reader.readFloat32();
    final displayIndex = reader.readVarUint();
    // Conditional, and that is the whole point of appending: reading it
    // unconditionally would turn every payload from an older phone into a
    // short_read, and a short_read on a known type closes the session.
    final monitorId = reader.remaining > 0 ? reader.readVarUint() : 0;
    return MouseMoveAbsolute(
      x: x,
      y: y,
      displayIndex: displayIndex,
      monitorId: monitorId,
    );
  }
}

/// Button press or release.
///
/// Press and release are separate events rather than a single "click" so that
/// drag, click-and-hold, and text selection all work without special cases. The
/// desktop tracks which buttons are down and releases them on disconnect —
/// otherwise a dropped connection mid-drag would leave the button stuck.
@immutable
final class MouseButtonEvent extends Message {
  const MouseButtonEvent({
    required this.button,
    required this.pressed,
    this.clickCount = 1,
  });

  final MouseButton button;
  final bool pressed;

  /// 2 for a double click, 3 for a triple.
  ///
  /// Sent explicitly instead of relying on the OS to infer it from timing:
  /// network jitter can stretch two taps past the double-click threshold, and a
  /// double-tap that fails to select a word is a very visible bug.
  final int clickCount;

  @override
  MessageType get type => MessageType.mouseButton;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(button.wireValue)
      ..writeBool(pressed)
      ..writeUint8(clickCount);
  }

  static MouseButtonEvent readFrom(ByteReader reader) => MouseButtonEvent(
        button: MouseButton.fromWire(reader.readUint8()),
        pressed: reader.readBool(),
        clickCount: reader.readUint8().clamp(1, 3),
      );
}

/// Wheel or trackpad scroll.
///
/// Carries both a line count and a pixel delta. Windows applications generally
/// want discrete `WHEEL_DELTA` notches while macOS expects continuous pixel
/// scrolling with momentum; sending both lets each backend use whichever is
/// native and avoids a lossy conversion in the middle.
@immutable
final class MouseScroll extends Message {
  const MouseScroll({
    required this.linesX,
    required this.linesY,
    required this.pixelsX,
    required this.pixelsY,
    this.isMomentum = false,
    this.isPrecise = true,
  });

  final int linesX;
  final int linesY;
  final int pixelsX;
  final int pixelsY;

  /// True for inertial frames after the finger has lifted. macOS renders these
  /// differently, and rubber-banding looks wrong without the distinction.
  final bool isMomentum;

  /// True when the source was a touch surface rather than a notched wheel.
  final bool isPrecise;

  @override
  MessageType get type => MessageType.mouseScroll;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeVarInt(linesX)
      ..writeVarInt(linesY)
      ..writeVarInt(pixelsX)
      ..writeVarInt(pixelsY)
      ..writeUint8((isMomentum ? 1 : 0) | (isPrecise ? 2 : 0));
  }

  static MouseScroll readFrom(ByteReader reader) {
    final linesX = reader.readVarInt();
    final linesY = reader.readVarInt();
    final pixelsX = reader.readVarInt();
    final pixelsY = reader.readVarInt();
    final flags = reader.readUint8();
    return MouseScroll(
      linesX: linesX,
      linesY: linesY,
      pixelsX: pixelsX,
      pixelsY: pixelsY,
      isMomentum: flags & 1 != 0,
      isPrecise: flags & 2 != 0,
    );
  }

  MouseScroll merge(MouseScroll next) => MouseScroll(
        linesX: linesX + next.linesX,
        linesY: linesY + next.linesY,
        pixelsX: pixelsX + next.pixelsX,
        pixelsY: pixelsY + next.pixelsY,
        isMomentum: next.isMomentum,
        isPrecise: isPrecise && next.isPrecise,
      );
}

/// Lifecycle phase of a continuous gesture.
enum GesturePhase {
  began(1),
  changed(2),
  ended(3),
  cancelled(4);

  const GesturePhase(this.wireValue);

  final int wireValue;

  static GesturePhase fromWire(int value) => values.firstWhere(
        (phase) => phase.wireValue == value,
        orElse: () => GesturePhase.cancelled,
      );
}

/// Pinch-to-zoom magnification delta.
@immutable
final class GestureZoom extends Message {
  const GestureZoom({required this.magnificationDelta, required this.phase});

  /// Change in magnification since the previous event, matching macOS's
  /// `NSEvent.magnification` convention: `0.1` means "10% larger".
  final double magnificationDelta;

  final GesturePhase phase;

  @override
  MessageType get type => MessageType.gestureZoom;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeFloat32(magnificationDelta)
      ..writeUint8(phase.wireValue);
  }

  static GestureZoom readFrom(ByteReader reader) => GestureZoom(
        magnificationDelta: reader.readFloat32(),
        phase: GesturePhase.fromWire(reader.readUint8()),
      );
}

/// Two-finger rotation.
@immutable
final class GestureRotate extends Message {
  const GestureRotate({required this.degreesDelta, required this.phase});

  final double degreesDelta;
  final GesturePhase phase;

  @override
  MessageType get type => MessageType.gestureRotate;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeFloat32(degreesDelta)
      ..writeUint8(phase.wireValue);
  }

  static GestureRotate readFrom(ByteReader reader) => GestureRotate(
        degreesDelta: reader.readFloat32(),
        phase: GesturePhase.fromWire(reader.readUint8()),
      );
}

/// Direction of a multi-finger swipe.
enum SwipeDirection {
  up(1),
  down(2),
  left(3),
  right(4);

  const SwipeDirection(this.wireValue);

  final int wireValue;

  static SwipeDirection fromWire(int value) => values.firstWhere(
        (direction) => direction.wireValue == value,
        orElse: () => SwipeDirection.up,
      );
}

/// Multi-finger swipe, mapped by the desktop to an OS gesture.
///
/// The mapping lives on the desktop because it is platform-specific: a
/// three-finger swipe up is Mission Control on macOS and Task View on Windows.
/// The phone reports the physical gesture and stays out of it.
@immutable
final class GestureSwipe extends Message {
  const GestureSwipe({required this.fingerCount, required this.direction});

  final int fingerCount;
  final SwipeDirection direction;

  @override
  MessageType get type => MessageType.gestureSwipe;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(fingerCount)
      ..writeUint8(direction.wireValue);
  }

  static GestureSwipe readFrom(ByteReader reader) => GestureSwipe(
        fingerCount: reader.readUint8(),
        direction: SwipeDirection.fromWire(reader.readUint8()),
      );
}

/// Stylus input with pressure and tilt.
@immutable
final class PenInput extends Message {
  const PenInput({
    required this.x,
    required this.y,
    required this.pressure,
    required this.tiltX,
    required this.tiltY,
    required this.inContact,
    this.isEraser = false,
  });

  /// Normalised `[0,1]` position across the virtual desktop.
  final double x;
  final double y;

  /// Normalised `[0,1]` tip pressure.
  final double pressure;

  /// Tilt from vertical in degrees, `[-90, 90]`.
  final double tiltX;
  final double tiltY;

  /// True while the tip touches the surface; false while hovering.
  final bool inContact;

  final bool isEraser;

  @override
  MessageType get type => MessageType.penInput;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeFloat32(x)
      ..writeFloat32(y)
      ..writeFloat32(pressure)
      ..writeFloat32(tiltX)
      ..writeFloat32(tiltY)
      ..writeUint8((inContact ? 1 : 0) | (isEraser ? 2 : 0));
  }

  static PenInput readFrom(ByteReader reader) {
    final x = reader.readFloat32();
    final y = reader.readFloat32();
    final pressure = reader.readFloat32();
    final tiltX = reader.readFloat32();
    final tiltY = reader.readFloat32();
    final flags = reader.readUint8();
    return PenInput(
      x: x,
      y: y,
      pressure: pressure,
      tiltX: tiltX,
      tiltY: tiltY,
      inContact: flags & 1 != 0,
      isEraser: flags & 2 != 0,
    );
  }
}
