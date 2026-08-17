import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';

/// Power-state transitions a remote may request.
enum PowerAction {
  shutdown(1),
  restart(2),
  sleep(3),
  hibernate(4),
  lock(5),
  logOut(6),

  /// Turn the displays off without sleeping the machine.
  displayOff(7);

  const PowerAction(this.wireValue);

  final int wireValue;

  static PowerAction fromWire(int value) => values.firstWhere(
        (action) => action.wireValue == value,
        orElse: () => PowerAction.lock,
      );

  /// Whether losing unsaved work is a plausible outcome.
  ///
  /// Actions flagged here require an explicit on-desktop confirmation unless
  /// the user has disabled the guard. A misplaced tap on a phone in a pocket
  /// should not be able to shut down a machine mid-render.
  bool get isDestructive => switch (this) {
        PowerAction.shutdown ||
        PowerAction.restart ||
        PowerAction.logOut =>
          true,
        _ => false,
      };
}

/// Requests a power-state change.
@immutable
final class PowerCommand extends Message {
  const PowerCommand({
    required this.action,
    this.delaySeconds = 0,
    this.force = false,
  });

  final PowerAction action;

  /// Grace period before the action runs, giving the desktop time to show a
  /// cancellable countdown.
  final int delaySeconds;

  /// Skip the "an application is preventing shutdown" prompt.
  ///
  /// Honoured only for sessions holding the admin permission tier, since it can
  /// discard unsaved work without asking.
  final bool force;

  @override
  MessageType get type => MessageType.powerCommand;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(action.wireValue)
      ..writeVarUint(delaySeconds)
      ..writeBool(force);
  }

  static PowerCommand readFrom(ByteReader reader) => PowerCommand(
        action: PowerAction.fromWire(reader.readUint8()),
        delaySeconds: reader.readVarUint(),
        force: reader.readBool(),
      );
}

/// Launches an application.
///
/// [identifier] is resolved by the desktop against its installed-application
/// index, which it builds from the Start Menu on Windows and `/Applications`
/// plus Launch Services on macOS. Sending an identifier rather than a path
/// means the phone's shortcut for "Chrome" works on both platforms and survives
/// the app moving.
@immutable
final class LaunchApplication extends Message {
  const LaunchApplication({
    required this.identifier,
    this.arguments = const <String>[],
  });

  /// Bundle identifier, executable name, or indexed display name.
  final String identifier;

  /// Extra arguments. Ignored unless the session holds the admin tier, because
  /// arbitrary arguments to an arbitrary binary is arbitrary code execution.
  final List<String> arguments;

  @override
  MessageType get type => MessageType.launchApplication;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(identifier)
      ..writeVarUint(arguments.length);
    for (final argument in arguments) {
      writer.writeString(argument);
    }
  }

  static LaunchApplication readFrom(ByteReader reader) {
    final identifier = reader.readString(maxLength: 1024);
    final count = reader.readVarUint();
    if (count > 64) {
      throw ProtocolError(
        'argument_limit',
        'launch declared $count arguments, cap is 64',
      );
    }
    return LaunchApplication(
      identifier: identifier,
      arguments: <String>[
        for (var i = 0; i < count; i++) reader.readString(maxLength: 4096),
      ],
    );
  }
}

/// Opens a URL in the default handler.
///
/// The desktop validates the scheme against an allow-list (`http`, `https`,
/// `mailto`, plus anything the user opts into) before handing it to the OS.
/// Without that check this message would be a general-purpose launcher, since
/// `file:` and custom schemes can start arbitrary applications.
@immutable
final class OpenUrl extends Message {
  const OpenUrl(this.url);

  final String url;

  @override
  MessageType get type => MessageType.openUrl;

  @override
  void writeTo(ByteWriter writer) => writer.writeString(url);

  static OpenUrl readFrom(ByteReader reader) =>
      OpenUrl(reader.readString(maxLength: 8192));
}

/// Runs a command the user pre-registered on the desktop.
///
/// [commandId] refers to an entry in the desktop's own configuration; the
/// command text never travels over the wire. This is the difference between a
/// remote control and a remote shell: a compromised phone can trigger the
/// commands its owner already approved and nothing else.
@immutable
final class RunCommand extends Message {
  const RunCommand(
      {required this.commandId, this.parameters = const <String>[]});

  final String commandId;

  /// Values substituted into the registered command's declared placeholders.
  /// Positional and never concatenated into a shell string by the desktop.
  final List<String> parameters;

  @override
  MessageType get type => MessageType.runCommand;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(commandId)
      ..writeVarUint(parameters.length);
    for (final parameter in parameters) {
      writer.writeString(parameter);
    }
  }

  static RunCommand readFrom(ByteReader reader) {
    final commandId = reader.readString(maxLength: 256);
    final count = reader.readVarUint();
    if (count > 32) {
      throw ProtocolError(
        'parameter_limit',
        'command declared $count parameters, cap is 32',
      );
    }
    return RunCommand(
      commandId: commandId,
      parameters: <String>[
        for (var i = 0; i < count; i++) reader.readString(maxLength: 4096),
      ],
    );
  }
}

/// Desktop → phone. Host telemetry, pushed on change.
@immutable
final class SystemStatus extends Message {
  const SystemStatus({
    required this.volume,
    required this.isMuted,
    required this.uptimeSeconds,
    this.batteryPercent,
    this.isCharging,
    this.cpuPercent,
    this.memoryPercent,
  });

  final double volume;
  final bool isMuted;
  final int uptimeSeconds;

  /// Absent on desktops without a battery.
  final int? batteryPercent;
  final bool? isCharging;

  final double? cpuPercent;
  final double? memoryPercent;

  @override
  MessageType get type => MessageType.systemStatus;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeFloat32(volume)
      ..writeBool(isMuted)
      ..writeVarUint(uptimeSeconds);

    final battery = batteryPercent;
    writer.writeBool(battery != null);
    if (battery != null) {
      writer
        ..writeUint8(battery)
        ..writeBool(isCharging ?? false);
    }

    final cpu = cpuPercent;
    writer.writeBool(cpu != null);
    if (cpu != null) writer.writeFloat32(cpu);

    final memory = memoryPercent;
    writer.writeBool(memory != null);
    if (memory != null) writer.writeFloat32(memory);
  }

  static SystemStatus readFrom(ByteReader reader) {
    final volume = reader.readFloat32();
    final isMuted = reader.readBool();
    final uptimeSeconds = reader.readVarUint();

    int? batteryPercent;
    bool? isCharging;
    if (reader.readBool()) {
      batteryPercent = reader.readUint8();
      isCharging = reader.readBool();
    }

    final cpuPercent = reader.readBool() ? reader.readFloat32() : null;
    final memoryPercent = reader.readBool() ? reader.readFloat32() : null;

    return SystemStatus(
      volume: volume,
      isMuted: isMuted,
      uptimeSeconds: uptimeSeconds,
      batteryPercent: batteryPercent,
      isCharging: isCharging,
      cpuPercent: cpuPercent,
      memoryPercent: memoryPercent,
    );
  }
}

/// Full peer description, exchanged once the channel is encrypted.
///
/// The field order here is the wire order and is append-only. `macAddress` was
/// added after v1 shipped and is written *last* for that reason: a build that
/// predates it decodes the fields it knows and stops, leaving the trailing
/// bytes unread, which `PROTOCOL.md` §5 rule 2 guarantees is not an error.
/// Inserting it anywhere earlier would have shifted every following field and
/// silently corrupted the app version and model on every deployed device.
@immutable
final class DeviceInfoMessage extends Message {
  const DeviceInfoMessage(this.info);

  final DeviceInfo info;

  @override
  MessageType get type => MessageType.deviceInfo;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(info.id.value)
      ..writeString(info.name)
      ..writeUint8(info.platform.wireValue)
      ..writeUint8(info.role == PeerRole.server ? 1 : 2)
      ..writeString(info.appVersion)
      ..writeOptionalString(info.model)
      // Appended field — see the class comment. Sent as text rather than six
      // raw bytes so a capture stays readable and so a peer that reports a
      // malformed address is rejected by one parser, here, instead of every
      // consumer having to decide what a nonsense address means.
      ..writeOptionalString(info.macAddress?.canonical);
  }

  static DeviceInfoMessage readFrom(ByteReader reader) {
    final rawId = reader.readString(maxLength: 64);
    final id = DeviceId.tryParse(rawId);
    if (id == null) {
      throw const ProtocolError('bad_device_id', 'malformed device id');
    }
    final name = reader.readString(maxLength: 128);
    final platform = PlatformKind.fromWire(reader.readUint8());
    final role = reader.readUint8() == 1 ? PeerRole.server : PeerRole.client;
    final appVersion = reader.readString(maxLength: 32);
    final model = reader.readOptionalString(maxLength: 128);

    // The other half of the append-only guarantee: an *older* peer stops
    // writing here, so the field is read only if there is anything left. A bare
    // `readOptionalString` would turn every v1 device into a `short_read` and
    // drop the session.
    //
    // A malformed address degrades to null rather than throwing. It is a
    // convenience field — the worst outcome of ignoring it is that the Wake
    // button does not appear — and killing an otherwise healthy session over a
    // cosmetic field would be a much worse trade.
    final macAddress = reader.isAtEnd
        ? null
        : MacAddress.tryParse(reader.readOptionalString(maxLength: 32) ?? '');

    return DeviceInfoMessage(
      DeviceInfo(
        id: id,
        name: name,
        platform: platform,
        role: role,
        appVersion: appVersion,
        model: model,
        macAddress: macAddress,
      ),
    );
  }
}

/// Renames the peer in the other side's device list.
@immutable
final class DeviceRename extends Message {
  const DeviceRename(this.name);

  final String name;

  @override
  MessageType get type => MessageType.deviceRename;

  @override
  void writeTo(ByteWriter writer) => writer.writeString(name);

  static DeviceRename readFrom(ByteReader reader) =>
      DeviceRename(reader.readString(maxLength: 128));
}

/// What a session is permitted to do.
///
/// Tiers are cumulative and checked on the desktop for every inbound command.
/// Enforcing on the receiving side rather than hiding buttons on the phone is
/// the whole point: the phone is untrusted input, not a security boundary.
enum PermissionTier {
  /// May observe only: media state, system status, screen stream.
  readOnly(1),

  /// Input, clipboard, and media. The default for a newly paired device.
  standard(2),

  /// Adds file transfer, application launching, and registered commands.
  extended(3),

  /// Adds power control and the ability to manage other paired devices.
  admin(4);

  const PermissionTier(this.wireValue);

  final int wireValue;

  static PermissionTier fromWire(int value) => values.firstWhere(
        (tier) => tier.wireValue == value,
        orElse: () => PermissionTier.readOnly,
      );

  bool get canSendInput => wireValue >= standard.wireValue;
  bool get canSyncClipboard => wireValue >= standard.wireValue;
  bool get canTransferFiles => wireValue >= extended.wireValue;
  bool get canLaunchApplications => wireValue >= extended.wireValue;
  bool get canRunCommands => wireValue >= extended.wireValue;
  bool get canControlPower => wireValue >= admin.wireValue;
  bool get canManageDevices => wireValue >= admin.wireValue;

  /// Whether a message of [type] is permitted at this tier.
  ///
  /// Central rather than scattered through the dispatcher so that adding a
  /// message forces an explicit decision here — the default branch denies.
  bool allows(MessageType type) => switch (type.subsystem) {
        0x00 || 0x01 || 0x09 => true,
        0x02 || 0x03 || 0x0B => canSendInput,
        0x04 => canSyncClipboard,
        0x05 || 0x06 || 0x0A => wireValue >= readOnly.wireValue,
        0x07 => canTransferFiles,
        0x08 => switch (type) {
            MessageType.powerCommand => canControlPower,
            MessageType.launchApplication => canLaunchApplications,
            MessageType.openUrl => canLaunchApplications,
            MessageType.runCommand => canRunCommands,
            _ => true,
          },
        _ => false,
      };
}

/// Desktop → phone. Announces the tier granted to this session.
@immutable
final class PermissionGrant extends Message {
  const PermissionGrant({required this.tier, this.expiresInSeconds});

  final PermissionTier tier;

  /// Set for temporary guest access, after which the tier drops to
  /// [PermissionTier.readOnly].
  final int? expiresInSeconds;

  @override
  MessageType get type => MessageType.permissionGrant;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(tier.wireValue)
      ..writeVarUint(expiresInSeconds ?? 0);
  }

  static PermissionGrant readFrom(ByteReader reader) {
    final tier = PermissionTier.fromWire(reader.readUint8());
    final expires = reader.readVarUint();
    return PermissionGrant(
      tier: tier,
      expiresInSeconds: expires == 0 ? null : expires,
    );
  }
}

/// Phone → desktop. Asks for a higher tier; the desktop prompts the user.
@immutable
final class PermissionRequest extends Message {
  const PermissionRequest({required this.tier, this.justification});

  final PermissionTier tier;

  /// Shown in the desktop's prompt, e.g. "to send you files".
  final String? justification;

  @override
  MessageType get type => MessageType.permissionRequest;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(tier.wireValue)
      ..writeOptionalString(justification);
  }

  static PermissionRequest readFrom(ByteReader reader) => PermissionRequest(
        tier: PermissionTier.fromWire(reader.readUint8()),
        justification: reader.readOptionalString(maxLength: 512),
      );
}
