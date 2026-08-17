import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';

/// `MouseMoveAbsolute.monitorId` value meaning "the whole virtual desktop".
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

  /// Opaque handle the phone quotes back in `MouseMoveAbsolute.monitorId`.
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
///
/// This is the first `0x06xx` code with a real payload. The rest of the
/// screen-streaming range — `screenStreamStart`, `screenStreamStop`,
/// `screenFrame`, `screenConfigure` — is still declared-but-opaque and lands
/// with the streaming feature itself.
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
