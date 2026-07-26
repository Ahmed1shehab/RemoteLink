import 'package:rl_protocol/rl_protocol.dart';

/// What the host is currently playing.
class NowPlaying {
  const NowPlaying({
    required this.isPlaying,
    required this.title,
    required this.artist,
    required this.album,
    this.source,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
  });

  final bool isPlaying;
  final String title;
  final String artist;
  final String album;

  /// The application the metadata came from, e.g. `Spotify`.
  final String? source;

  final double positionSeconds;
  final double durationSeconds;

  bool get isEmpty => title.isEmpty && artist.isEmpty;
}

/// Current output volume state.
class VolumeState {
  const VolumeState({required this.level, required this.muted});

  /// `0.0`–`1.0`.
  final double level;
  final bool muted;
}

/// Controls playback and volume on the host.
///
/// Separate from [InputBackend] because the mechanisms have nothing in common:
/// input is synthesised HID events on a microsecond budget, while media control
/// goes through system services and tolerates tens of milliseconds. Sharing an
/// interface would force one of them into the wrong shape.
abstract interface class MediaBackend {
  bool get isAvailable;

  /// Sends a transport command.
  Future<void> command(MediaAction action, {int seekSeconds = 10});

  /// Reads the current output volume.
  Future<VolumeState> volume();

  /// Sets the output volume, `0.0`–`1.0`.
  Future<void> setVolume(double level);

  Future<void> setMuted({required bool muted});

  /// Reads now-playing metadata, or `null` when nothing is known.
  Future<NowPlaying?> nowPlaying();

  void dispose();
}

/// Null implementation for platforms without a media backend.
final class UnsupportedMediaBackend implements MediaBackend {
  const UnsupportedMediaBackend();

  @override
  bool get isAvailable => false;

  @override
  Future<void> command(MediaAction action, {int seekSeconds = 10}) async {}

  @override
  Future<VolumeState> volume() async =>
      const VolumeState(level: 0, muted: false);

  @override
  Future<void> setVolume(double level) async {}

  @override
  Future<void> setMuted({required bool muted}) async {}

  @override
  Future<NowPlaying?> nowPlaying() async => null;

  @override
  void dispose() {}
}
