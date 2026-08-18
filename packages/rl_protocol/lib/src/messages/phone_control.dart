/// The reverse direction: the desktop watching and driving the phone.
///
/// Defined and tested, and deliberately not yet spoken by either side. Neither
/// end advertises `Capabilities.phoneControl` today, so the negotiated
/// intersection never contains it and none of these messages is ever sent.
///
/// The vocabulary exists first because wire codes are append-only and never
/// reused: agreeing them now costs nothing and means the two ends can be built
/// independently and in either order. What blocks the feature is not the
/// protocol.
///
/// On iOS it is blocked permanently. There is no public API for capturing the
/// screen of the device from outside a ReplayKit broadcast the user starts by
/// hand, and none at all for injecting touches into another app — this is a
/// deliberate platform boundary, not a permission that can be asked for.
///
/// On Android it is possible, through MediaProjection and an
/// AccessibilityService, and blocked here by ADR 0003: this repository ships no
/// compiled native shim, and an AccessibilityService is Kotlin by definition.
/// Building it means revisiting that decision first.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';
import 'screen.dart';

/// Desktop → phone. Requests to start streaming the phone's screen.
@immutable
final class PhoneControlStart extends Message {
  const PhoneControlStart({
    this.codec = ScreenCodec.h264,
    this.targetFps = 30,
    this.targetBitrateKbps = 2000,
  });

  final ScreenCodec codec;
  final int targetFps;
  final int targetBitrateKbps;

  @override
  MessageType get type => MessageType.phoneControlStart;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(codec.wireValue)
      ..writeVarUint(targetFps)
      ..writeVarUint(targetBitrateKbps);
  }

  static PhoneControlStart readFrom(ByteReader reader) {
    return PhoneControlStart(
      codec: ScreenCodec.fromWire(reader.readUint8()),
      targetFps: reader.readVarUint(),
      targetBitrateKbps: reader.readVarUint(),
    );
  }
}

/// Desktop → phone. Requests to stop an active screen stream.
@immutable
final class PhoneControlStop extends Message {
  const PhoneControlStop({this.reason = ScreenStopReason.userClosed});

  final ScreenStopReason reason;

  @override
  MessageType get type => MessageType.phoneControlStop;

  @override
  void writeTo(ByteWriter writer) {
    writer.writeUint8(reason.wireValue);
  }

  static PhoneControlStop readFrom(ByteReader reader) {
    return PhoneControlStop(
      reason: ScreenStopReason.fromWire(reader.readUint8()),
    );
  }
}

/// Phone → desktop. One encoded video frame from the phone's screen.
@immutable
final class PhoneControlFrame extends Message {
  PhoneControlFrame({
    required this.sequence,
    required this.ptsMicros,
    required this.isKeyframe,
    required this.width,
    required this.height,
    required Uint8List data,
  }) : data = Uint8List.fromList(data);

  final int sequence;
  final int ptsMicros;
  final bool isKeyframe;
  final int width;
  final int height;
  final Uint8List data;

  @override
  MessageType get type => MessageType.phoneControlFrame;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeVarUint(sequence)
      ..writeUint64(ptsMicros)
      ..writeBool(isKeyframe)
      ..writeVarUint(width)
      ..writeVarUint(height)
      ..writeLengthPrefixedBytes(data);
  }

  static PhoneControlFrame readFrom(ByteReader reader) {
    return PhoneControlFrame(
      sequence: reader.readVarUint(),
      ptsMicros: reader.readUint64(),
      isKeyframe: reader.readBool(),
      width: reader.readVarUint(),
      height: reader.readVarUint(),
      data: reader.readLengthPrefixedBytes(maxLength: kMaxScreenFrameBytes),
    );
  }
}

/// Desktop → phone. Tap/touch at normalised coordinates.
@immutable
final class PhoneControlPointer extends Message {
  const PhoneControlPointer({
    required this.x,
    required this.y,
    required this.pressed,
  });

  /// Normalised `[0.0, 1.0]` across the phone's screen.
  final double x;
  final double y;
  final bool pressed;

  @override
  MessageType get type => MessageType.phoneControlPointer;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeFloat32(x)
      ..writeFloat32(y)
      ..writeBool(pressed);
  }

  static PhoneControlPointer readFrom(ByteReader reader) {
    return PhoneControlPointer(
      x: reader.readFloat32(),
      y: reader.readFloat32(),
      pressed: reader.readBool(),
    );
  }
}

/// Desktop → phone. Swipe/scroll event.
@immutable
final class PhoneControlScroll extends Message {
  const PhoneControlScroll({
    required this.deltaX,
    required this.deltaY,
  });

  final double deltaX;
  final double deltaY;

  @override
  MessageType get type => MessageType.phoneControlScroll;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeFloat32(deltaX)
      ..writeFloat32(deltaY);
  }

  static PhoneControlScroll readFrom(ByteReader reader) {
    return PhoneControlScroll(
      deltaX: reader.readFloat32(),
      deltaY: reader.readFloat32(),
    );
  }
}

/// Types of system navigation on the phone.
enum PhoneNavigationAction {
  back(1),
  home(2),
  appSwitcher(3);

  const PhoneNavigationAction(this.wireValue);

  final int wireValue;

  static PhoneNavigationAction fromWire(int value) => values.firstWhere(
        (action) => action.wireValue == value,
        orElse: () => PhoneNavigationAction.back,
      );
}

/// Desktop → phone. Back/home navigation action.
@immutable
final class PhoneControlNavigation extends Message {
  const PhoneControlNavigation({required this.action});

  final PhoneNavigationAction action;

  @override
  MessageType get type => MessageType.phoneControlNavigation;

  @override
  void writeTo(ByteWriter writer) {
    writer.writeUint8(action.wireValue);
  }

  static PhoneControlNavigation readFrom(ByteReader reader) {
    return PhoneControlNavigation(
      action: PhoneNavigationAction.fromWire(reader.readUint8()),
    );
  }
}

/// Desktop → phone. Text input.
@immutable
final class PhoneControlTextInput extends Message {
  const PhoneControlTextInput({required this.text});

  final String text;

  @override
  MessageType get type => MessageType.phoneControlTextInput;

  @override
  void writeTo(ByteWriter writer) {
    writer.writeString(text);
  }

  static PhoneControlTextInput readFrom(ByteReader reader) {
    return PhoneControlTextInput(
      text: reader.readString(maxLength: 4096),
    );
  }
}
