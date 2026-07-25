import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';

/// Transport actions understood by every media backend.
enum MediaAction {
  playPause(1),
  play(2),
  pause(3),
  stop(4),
  next(5),
  previous(6),
  seekForward(7),
  seekBackward(8),
  fastForward(9),
  rewind(10),
  shuffleToggle(11),
  repeatToggle(12);

  const MediaAction(this.wireValue);

  final int wireValue;

  static MediaAction fromWire(int value) => values.firstWhere(
        (action) => action.wireValue == value,
        orElse: () => MediaAction.playPause,
      );
}

/// A transport control command.
///
/// Delivery is deliberately layered on the desktop side. The first choice is
/// the OS media-session API — `GlobalSystemMediaTransportControls` on Windows,
/// `MPRemoteCommandCenter`/`MediaRemote` on macOS — because that routes to
/// whichever app the user last played from, and works when the app is in the
/// background or on another desktop.
///
/// The fallback is to synthesise the corresponding media key
/// (`VK_MEDIA_PLAY_PAUSE`, `NX_KEYTYPE_PLAY`). It reaches browser-based players
/// that never registered a media session, at the cost of being routed by the OS
/// rather than targeted.
///
/// [preferKeySimulation] lets the phone force the fallback when the user has a
/// player that misbehaves with session routing.
@immutable
final class MediaCommand extends Message {
  const MediaCommand({
    required this.action,
    this.seekSeconds = 10,
    this.preferKeySimulation = false,
  });

  final MediaAction action;

  /// Step size for [MediaAction.seekForward] and [MediaAction.seekBackward].
  final int seekSeconds;

  final bool preferKeySimulation;

  @override
  MessageType get type => MessageType.mediaCommand;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(action.wireValue)
      ..writeVarUint(seekSeconds)
      ..writeBool(preferKeySimulation);
  }

  static MediaCommand readFrom(ByteReader reader) => MediaCommand(
        action: MediaAction.fromWire(reader.readUint8()),
        seekSeconds: reader.readVarUint(),
        preferKeySimulation: reader.readBool(),
      );
}

/// How a volume change should be interpreted.
enum VolumeMode {
  /// [VolumeCommand.value] is the target level, `0.0`–`1.0`.
  absolute(1),

  /// [VolumeCommand.value] is added to the current level.
  relative(2),

  /// Toggle mute; the value is ignored.
  toggleMute(3),

  /// Force mute on or off from the sign of the value.
  setMute(4);

  const VolumeMode(this.wireValue);

  final int wireValue;

  static VolumeMode fromWire(int value) => values.firstWhere(
        (mode) => mode.wireValue == value,
        orElse: () => VolumeMode.relative,
      );
}

/// System volume adjustment.
@immutable
final class VolumeCommand extends Message {
  const VolumeCommand({required this.mode, required this.value});

  final VolumeMode mode;
  final double value;

  @override
  MessageType get type => MessageType.volumeCommand;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8(mode.wireValue)
      ..writeFloat32(value);
  }

  static VolumeCommand readFrom(ByteReader reader) => VolumeCommand(
        mode: VolumeMode.fromWire(reader.readUint8()),
        value: reader.readFloat32(),
      );
}

/// Desktop → phone. Now-playing metadata for the remote's display.
///
/// Pushed on change rather than polled, so the phone's media view updates the
/// moment the track does. Album art is sent once per track and cached by hash
/// on the phone, because re-sending 200 KB of JPEG every state tick would
/// dominate the session's bandwidth.
@immutable
final class MediaState extends Message {
  const MediaState({
    required this.isPlaying,
    required this.title,
    required this.artist,
    required this.album,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.volume,
    required this.isMuted,
    this.sourceApplication,
    this.artworkHash,
    this.artworkPng,
  });

  final bool isPlaying;
  final String title;
  final String artist;
  final String album;
  final double positionSeconds;
  final double durationSeconds;
  final double volume;
  final bool isMuted;

  /// The application the session belongs to, e.g. `Spotify`.
  final String? sourceApplication;

  /// Hash identifying the current artwork. The phone compares it against its
  /// cache and only the mismatch case carries [artworkPng].
  final Uint8List? artworkHash;

  final Uint8List? artworkPng;

  @override
  MessageType get type => MessageType.mediaState;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeUint8((isPlaying ? 1 : 0) | (isMuted ? 2 : 0))
      ..writeString(title)
      ..writeString(artist)
      ..writeString(album)
      ..writeFloat32(positionSeconds)
      ..writeFloat32(durationSeconds)
      ..writeFloat32(volume)
      ..writeOptionalString(sourceApplication);

    final hash = artworkHash;
    writer.writeBool(hash != null);
    if (hash != null) writer.writeLengthPrefixedBytes(hash);

    final artwork = artworkPng;
    writer.writeBool(artwork != null);
    if (artwork != null) writer.writeLengthPrefixedBytes(artwork);
  }

  static MediaState readFrom(ByteReader reader) {
    final flags = reader.readUint8();
    final title = reader.readString(maxLength: 1024);
    final artist = reader.readString(maxLength: 1024);
    final album = reader.readString(maxLength: 1024);
    final positionSeconds = reader.readFloat32();
    final durationSeconds = reader.readFloat32();
    final volume = reader.readFloat32();
    final sourceApplication = reader.readOptionalString(maxLength: 256);
    final artworkHash = reader.readBool()
        ? reader.readLengthPrefixedBytes(maxLength: 64)
        : null;
    final artworkPng = reader.readBool()
        ? reader.readLengthPrefixedBytes(maxLength: 4 * 1024 * 1024)
        : null;
    return MediaState(
      isPlaying: flags & 1 != 0,
      isMuted: flags & 2 != 0,
      title: title,
      artist: artist,
      album: album,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      volume: volume,
      sourceApplication: sourceApplication,
      artworkHash: artworkHash,
      artworkPng: artworkPng,
    );
  }
}

/// Display brightness adjustment, where the platform exposes one.
@immutable
final class BrightnessCommand extends Message {
  const BrightnessCommand({required this.relative, required this.value});

  /// True when [value] is a delta rather than an absolute `0.0`–`1.0` level.
  final bool relative;
  final double value;

  @override
  MessageType get type => MessageType.brightnessCommand;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeBool(relative)
      ..writeFloat32(value);
  }

  static BrightnessCommand readFrom(ByteReader reader) => BrightnessCommand(
        relative: reader.readBool(),
        value: reader.readFloat32(),
      );
}
