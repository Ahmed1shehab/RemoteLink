import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';

/// `MouseMoveAbsolute.monitorId` and `ScreenStreamStart.monitorId` value
/// meaning "the whole virtual desktop".
///
/// Zero rather than a dedicated flag because that is what a peer built before
/// the field existed already sends: the field is absent from its payload, and
/// absence decodes as zero. Reserving the value here is what lets the
/// appended field be non-breaking in behaviour as well as in bytes, and is why
/// no real monitor may carry this id.
const int kWholeVirtualDesktopMonitorId = 0;

/// Most monitors one [ScreenTopology] may describe.
///
/// Checked *before* the decode loop allocates anything. A varint count field
/// can ask for four billion entries in five bytes, and a decoder that trusts it
/// hands a peer an out-of-memory kill for the price of a malformed packet.
/// Thirty-two is well past any real desk.
const int kMaxMonitors = 32;

/// Widest or tallest a monitor may claim to be, in host coordinate units.
///
/// Not a security bound — the count check above is what protects the
/// allocation — but a nonsense filter. A peer reporting a 2-billion-pixel-wide
/// screen would make every normalised coordinate resolve to the same place, and
/// clamping is a better answer than propagating the nonsense.
const int kMaxMonitorExtent = 100000;

/// Minimum allowed target frame rate in frames per second.
///
/// Nonsense filter: 0 or negative FPS would produce division-by-zero errors in
/// frame interval timers.
const int kMinFps = 1;

/// Maximum allowed target frame rate in frames per second.
///
/// Nonsense filter: prevents a peer from requesting an unbounded frame rate
/// that would overwhelm capture and encoding pipelines. 240 Hz exceeds high-end
/// gaming monitors.
const int kMaxFps = 240;

/// Minimum allowed target bitrate in kilobits per second.
///
/// Nonsense filter: a bitrate of 0 would produce unusable video streams.
const int kMinBitrateKbps = 64;

/// Maximum allowed target bitrate in kilobits per second (100 Mbps).
///
/// Nonsense filter: caps requested bandwidth to a realistic LAN ceiling and
/// prevents memory exhaustion in buffer queues.
const int kMaxBitrateKbps = 100000;

/// Maximum bytes carried by one [ScreenFrame].
///
/// Checked *before* allocating frame payload memory. A varint length field
/// can ask for four gigabytes in five bytes; capping at 16 MiB (matching
/// the maximum frame payload limit in PROTOCOL.md §3) rejects hostile allocations
/// immediately.
const int kMaxScreenFrameBytes = 16 * 1024 * 1024;

/// Video codec used for screen streaming.
///
/// An unknown codec on the wire decodes to [unknown] rather than throwing,
/// allowing a newer peer to advertise or negotiate newer codecs with older peers
/// cleanly.
enum ScreenCodec {
  unknown(0),
  h264(1),
  jpeg(2),
  rawRgba(3),
  h265(4),
  av1(5),
  vp8(6),
  vp9(7);

  const ScreenCodec(this.wireValue);

  final int wireValue;

  static final Map<int, ScreenCodec> _byWire = <int, ScreenCodec>{
    for (final codec in ScreenCodec.values)
      if (codec != ScreenCodec.unknown) codec.wireValue: codec,
  };

  /// Resolves a wire byte to a [ScreenCodec], returning [unknown] for any
  /// unrecognized value. Never throws.
  static ScreenCodec fromWire(int value) =>
      _byWire[value] ?? ScreenCodec.unknown;
}

/// Why a screen stream was stopped.
///
/// Carrying a reason code lets the desktop distinguish between a normal user
/// departure (e.g. closing the viewer) and a decoder crash, allowing diagnostic
/// logging and cleanup without tearing down the entire transport session.
enum ScreenStopReason {
  unknown(0),
  userClosed(1),
  decoderError(2),
  networkError(3),
  unsupportedCodec(4),
  switchingDisplay(5);

  const ScreenStopReason(this.wireValue);

  final int wireValue;

  static final Map<int, ScreenStopReason> _byWire = <int, ScreenStopReason>{
    for (final reason in ScreenStopReason.values)
      if (reason != ScreenStopReason.unknown) reason.wireValue: reason,
  };

  /// Resolves a wire byte to a [ScreenStopReason], returning [unknown] for any
  /// unrecognized value. Never throws.
  static ScreenStopReason fromWire(int value) =>
      _byWire[value] ?? ScreenStopReason.unknown;
}

/// One display in a [ScreenTopology].
///
/// Geometry only, deliberately. This is the *wire* view of a monitor and it is
/// a separate type from `rl_native`'s `MonitorInfo` on purpose: `rl_protocol`
/// sits beneath `rl_native` in the dependency order, so a message type cannot
/// reference a host-enumeration type, and it should not want to — everything
/// here arrived over a network and has been clamped and sanitised, which is not
/// true of what the host reported.
@immutable
final class MonitorDescriptor {
  const MonitorDescriptor({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.name,
    this.scaleFactor = 1.0,
    this.isPrimary = false,
  });

  /// Opaque handle the phone quotes back in `MouseMoveAbsolute.monitorId` or
  /// `ScreenStreamStart.monitorId`.
  ///
  /// Never zero for a real monitor: zero means "the whole virtual desktop"
  /// there, and a monitor claiming it would be unaddressable.
  final int id;

  /// Position of this monitor's top-left corner in the desktop's coordinate
  /// space. Negative on any monitor placed above or to the left of the primary,
  /// which is the normal arrangement for a screen on the left.
  final int x;
  final int y;

  final int width;
  final int height;

  /// DPI scale — `2.0` on a Retina panel, `1.5` at Windows 150%.
  ///
  /// Carried so the phone can size a preview, not so it can position: the
  /// desktop resolves coordinates in its own space and the scale never enters
  /// that calculation.
  final double scaleFactor;

  final bool isPrimary;

  /// Label for a picker, e.g. `Built-in Display`.
  final String name;

  @override
  String toString() =>
      'MonitorDescriptor($id, "$name", ${width}x$height @ $x,$y)';
}

/// Desktop → phone. The desk's monitor layout.
///
/// Sent on connect and whenever the layout changes. Without it the phone knows
/// only that *a* desktop exists and has to treat every screen as one rectangle,
/// which is why a touchpad tap on a two-monitor setup lands between the
/// screens rather than on one.
@immutable
final class ScreenTopology extends Message {
  const ScreenTopology(this.monitors);

  final List<MonitorDescriptor> monitors;

  @override
  MessageType get type => MessageType.screenTopology;

  @override
  void writeTo(ByteWriter writer) {
    final count =
        monitors.length > kMaxMonitors ? kMaxMonitors : monitors.length;
    writer.writeVarUint(count);
    for (var i = 0; i < count; i++) {
      final monitor = monitors[i];
      writer
        ..writeVarUint(monitor.id)
        ..writeVarInt(monitor.x)
        ..writeVarInt(monitor.y)
        ..writeVarUint(monitor.width)
        ..writeVarUint(monitor.height)
        ..writeFloat32(monitor.scaleFactor)
        ..writeUint8(monitor.isPrimary ? 1 : 0)
        ..writeString(monitor.name);
    }
  }

  static ScreenTopology readFrom(ByteReader reader) {
    final count = reader.readVarUint();
    if (count > kMaxMonitors) {
      throw ProtocolError(
        'length_limit',
        'topology declares $count monitors, cap is $kMaxMonitors',
      );
    }

    final monitors = <MonitorDescriptor>[];
    for (var i = 0; i < count; i++) {
      final id = reader.readVarUint();
      final x = reader.readVarInt();
      final y = reader.readVarInt();
      final width = reader.readVarUint();
      final height = reader.readVarUint();
      final scale = reader.readFloat32();
      final flags = reader.readUint8();
      // 256 bytes, not 256 characters: the cap here is on the allocation, and
      // `sanitiseDeviceName` applies the real 64-grapheme limit below.
      final rawName = reader.readString(maxLength: 256);

      // A monitor that claims id 0 is unaddressable, because 0 means "the
      // whole virtual desktop" in `MouseMoveAbsolute`. Dropping the entry is
      // better than keeping one the user can select and never reach.
      if (id == 0) continue;

      // The one validator, not a third one: a monitor name is rendered in the
      // phone's UI and written to logs exactly like a device name, so it faces
      // the same terminal-injection and bidi-spoofing problems. A rejected
      // name loses the label and keeps the monitor — the geometry is what makes
      // the screen addressable, and dropping a real display because its label
      // was hostile would be the peer choosing what the user can control.
      final name = sanitiseDeviceName(rawName) ?? 'Display ${i + 1}';

      monitors.add(
        MonitorDescriptor(
          id: id,
          x: x.clamp(-kMaxMonitorExtent, kMaxMonitorExtent),
          y: y.clamp(-kMaxMonitorExtent, kMaxMonitorExtent),
          width: width.clamp(0, kMaxMonitorExtent),
          height: height.clamp(0, kMaxMonitorExtent),
          // float32 from a peer: NaN and infinity cost nothing to send and
          // would propagate into every preview calculation on the phone.
          scaleFactor: scale.isFinite ? scale.clamp(0.1, 16.0) : 1.0,
          isPrimary: flags & 1 != 0,
          name: name,
        ),
      );
    }

    return ScreenTopology(monitors);
  }

  @override
  String toString() => 'ScreenTopology(${monitors.length} monitors)';
}

/// Client → server. Requests to begin screen streaming for a display.
///
/// Sent by the phone when opening the remote desktop view. Specifies the
/// target display, preferred codec, target frame rate, target bitrate, and
/// optional maximum dimensions so the host does not encode and transmit frames
/// larger than the client can display.
@immutable
final class ScreenStreamStart extends Message {
  const ScreenStreamStart({
    this.monitorId = kWholeVirtualDesktopMonitorId,
    required this.codec,
    this.targetFps = 60,
    this.targetBitrateKbps = 5000,
    this.maxWidth = 0,
    this.maxHeight = 0,
  });

  /// Monitor to stream, matching a [MonitorDescriptor.id] from [ScreenTopology].
  ///
  /// Defaults to [kWholeVirtualDesktopMonitorId] (0), which captures the
  /// entire virtual desktop across all displays.
  final int monitorId;

  /// Video codec the client requests.
  final ScreenCodec codec;

  /// Target frame rate in frames per second.
  final int targetFps;

  /// Target bitrate in kilobits per second.
  final int targetBitrateKbps;

  /// Maximum frame width in pixels. 0 means native / unconstrained.
  final int maxWidth;

  /// Maximum frame height in pixels. 0 means native / unconstrained.
  final int maxHeight;

  @override
  MessageType get type => MessageType.screenStreamStart;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeVarUint(monitorId)
      ..writeUint8(codec.wireValue)
      ..writeVarUint(targetFps)
      ..writeVarUint(targetBitrateKbps)
      ..writeVarUint(maxWidth)
      ..writeVarUint(maxHeight);
  }

  static ScreenStreamStart readFrom(ByteReader reader) {
    final monitorId = reader.readVarUint();
    final codec = ScreenCodec.fromWire(reader.readUint8());
    final targetFps = reader.readVarUint().clamp(kMinFps, kMaxFps);
    final targetBitrateKbps =
        reader.readVarUint().clamp(kMinBitrateKbps, kMaxBitrateKbps);
    final maxWidth = reader.readVarUint().clamp(0, kMaxMonitorExtent);
    final maxHeight = reader.readVarUint().clamp(0, kMaxMonitorExtent);

    return ScreenStreamStart(
      monitorId: monitorId,
      codec: codec,
      targetFps: targetFps,
      targetBitrateKbps: targetBitrateKbps,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  @override
  String toString() =>
      'ScreenStreamStart(monitorId: $monitorId, codec: ${codec.name}, '
      'fps: $targetFps, bitrate: ${targetBitrateKbps}kbps, '
      'max: ${maxWidth}x$maxHeight)';
}

/// Client → server. Requests to stop an active screen stream.
///
/// Carries a [reason] so the host can distinguish normal user exit from
/// decoder faults or network distress.
@immutable
final class ScreenStreamStop extends Message {
  const ScreenStreamStop({this.reason = ScreenStopReason.userClosed});

  final ScreenStopReason reason;

  @override
  MessageType get type => MessageType.screenStreamStop;

  @override
  void writeTo(ByteWriter writer) {
    writer.writeUint8(reason.wireValue);
  }

  static ScreenStreamStop readFrom(ByteReader reader) {
    final reason = ScreenStopReason.fromWire(reader.readUint8());
    return ScreenStreamStop(reason: reason);
  }

  @override
  String toString() => 'ScreenStreamStop(reason: ${reason.name})';
}

/// Server → client. One encoded video frame in an active screen stream.
///
/// Dimensions belong on the frame itself rather than only on the stream:
/// a monitor can be resized, rotated, or windows rearranged mid-stream,
/// and a decoder that trusts the initial dimensions from [ScreenStreamStart]
/// would corrupt memory or crash when the underlying resolution changes.
@immutable
final class ScreenFrame extends Message {
  ScreenFrame({
    required this.sequence,
    required this.ptsMicros,
    required this.isKeyframe,
    required this.width,
    required this.height,
    required Uint8List data,
  }) : data = Uint8List.fromList(data);

  /// Monotonically increasing frame sequence number on this stream.
  final int sequence;

  /// Presentation timestamp in microseconds on the server's monotonic clock.
  final int ptsMicros;

  /// Whether this frame is an independent keyframe (IDR/I-frame) or delta frame.
  final bool isKeyframe;

  /// Decoded width in pixels.
  final int width;

  /// Decoded height in pixels.
  final int height;

  /// Encoded frame payload (e.g. H.264 NALUs or JPEG bytes).
  final Uint8List data;

  @override
  MessageType get type => MessageType.screenFrame;

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

  static ScreenFrame readFrom(ByteReader reader) {
    final sequence = reader.readVarUint();
    final ptsMicros = reader.readUint64();
    final isKeyframe = reader.readBool();
    final width = reader.readVarUint().clamp(0, kMaxMonitorExtent);
    final height = reader.readVarUint().clamp(0, kMaxMonitorExtent);
    final data = reader.readLengthPrefixedBytes(
      maxLength: kMaxScreenFrameBytes,
    );

    return ScreenFrame(
      sequence: sequence,
      ptsMicros: ptsMicros,
      isKeyframe: isKeyframe,
      width: width,
      height: height,
      data: data,
    );
  }

  @override
  String toString() => 'ScreenFrame(#$sequence, pts: $ptsMicros, '
      '${isKeyframe ? "keyframe" : "delta"}, '
      '${width}x$height, ${data.length} bytes)';
}

/// Client → server. Adjusts stream parameters mid-stream.
///
/// Every field is optional: a client wishing to lower bitrate due to congestion
/// can adjust [targetBitrateKbps] while leaving [targetFps] and dimensions untouched.
/// Follows the presence-bool pattern used across the protocol.
@immutable
final class ScreenConfigure extends Message {
  const ScreenConfigure({
    this.targetFps,
    this.targetBitrateKbps,
    this.maxWidth,
    this.maxHeight,
    this.monitorId,
  });

  /// Updated target frame rate in frames per second, if changing.
  final int? targetFps;

  /// Updated target bitrate in kilobits per second, if changing.
  final int? targetBitrateKbps;

  /// Updated maximum frame width in pixels, if changing.
  final int? maxWidth;

  /// Updated maximum frame height in pixels, if changing.
  final int? maxHeight;

  /// Updated monitor ID to switch displays mid-stream, if changing.
  final int? monitorId;

  @override
  MessageType get type => MessageType.screenConfigure;

  @override
  void writeTo(ByteWriter writer) {
    final fps = targetFps;
    writer.writeBool(fps != null);
    if (fps != null) writer.writeVarUint(fps);

    final bitrate = targetBitrateKbps;
    writer.writeBool(bitrate != null);
    if (bitrate != null) writer.writeVarUint(bitrate);

    final width = maxWidth;
    writer.writeBool(width != null);
    if (width != null) writer.writeVarUint(width);

    final height = maxHeight;
    writer.writeBool(height != null);
    if (height != null) writer.writeVarUint(height);

    final monitor = monitorId;
    writer.writeBool(monitor != null);
    if (monitor != null) writer.writeVarUint(monitor);
  }

  static ScreenConfigure readFrom(ByteReader reader) {
    final targetFps =
        reader.readBool() ? reader.readVarUint().clamp(kMinFps, kMaxFps) : null;
    final targetBitrateKbps = reader.readBool()
        ? reader.readVarUint().clamp(kMinBitrateKbps, kMaxBitrateKbps)
        : null;
    final maxWidth = reader.readBool()
        ? reader.readVarUint().clamp(0, kMaxMonitorExtent)
        : null;
    final maxHeight = reader.readBool()
        ? reader.readVarUint().clamp(0, kMaxMonitorExtent)
        : null;
    final monitorId = reader.readBool() ? reader.readVarUint() : null;

    return ScreenConfigure(
      targetFps: targetFps,
      targetBitrateKbps: targetBitrateKbps,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      monitorId: monitorId,
    );
  }

  @override
  String toString() =>
      'ScreenConfigure(fps: $targetFps, bitrate: $targetBitrateKbps, '
      'max: ${maxWidth}x$maxHeight, monitorId: $monitorId)';
}
