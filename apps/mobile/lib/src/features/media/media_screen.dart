import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';

/// The computer's current playback state, pushed from the desktop.
final mediaStateProvider = StreamProvider<MediaState?>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  yield null;
  await for (final message in client.messages) {
    if (message is MediaState) yield message;
  }
});

/// Capability bit for display brightness adjustment (RL-202).
/// Transport controls, volume, and now playing.
class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key});

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  /// Volume being dragged, before the finger lifts.
  ///
  /// The slider follows the finger from this while a drag is in progress, and
  /// from the desktop's reported value otherwise. Without it, every state push
  /// from the computer would yank the slider back mid-gesture.
  double? _dragging;

  /// Brightness being dragged, before the finger lifts.
  double? _brightnessDragging;
  double _brightness = 0.5;

  Future<void> _send(Message message) async {
    final client = ref.read(clientProvider).valueOrNull;
    if (client == null) return;
    await client.send(message);
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        ref.watch(clientStateProvider).valueOrNull == ClientState.connected;
    final state = ref.watch(mediaStateProvider).valueOrNull;
    final capabilities =
        ref.watch(clientProvider).valueOrNull?.session?.capabilities;

    // The desktop only advertises media control when it has a working backend,
    // so this is not defensive noise — a Windows build genuinely cannot do this
    // yet, and showing dead buttons would be worse than saying so.
    final supported = capabilities?.has(Capabilities.mediaControl) ?? connected;
    final brightnessSupported =
        capabilities?.has(Capabilities.brightness) ?? false;

    if (connected && !supported) {
      return const _Unsupported();
    }

    final volume = _dragging ?? state?.volume ?? 0;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        _NowPlaying(state: state),
        const SizedBox(height: 32),
        _TransportRow(
          isPlaying: state?.isPlaying ?? false,
          enabled: connected,
          onPrevious: () => _send(
            const MediaCommand(action: MediaAction.previous),
          ),
          onPlayPause: () => _send(
            const MediaCommand(action: MediaAction.playPause),
          ),
          onNext: () => _send(const MediaCommand(action: MediaAction.next)),
        ),
        const SizedBox(height: 32),
        Row(
          children: <Widget>[
            IconButton(
              // The icon alone says nothing, and which way it toggles is not
              // guessable from a speaker glyph — so the label states the
              // action, not the state.
              tooltip: (state?.isMuted ?? false) ? 'Unmute' : 'Mute',
              icon: Icon(
                (state?.isMuted ?? false)
                    ? Icons.volume_off
                    : Icons.volume_mute,
              ),
              onPressed: connected
                  ? () => _send(
                        const VolumeCommand(
                          mode: VolumeMode.toggleMute,
                          value: 0,
                        ),
                      )
                  : null,
            ),
            Expanded(
              child: Slider(
                value: volume.clamp(0.0, 1.0),
                label: '${(volume * 100).round()}%',
                // Without this a screen reader reads the raw 0–1 double: "zero
                // point four two". Volume is a percentage everywhere else in
                // the app and on the computer being controlled.
                semanticFormatterCallback: (value) =>
                    'Volume ${(value * 100).round()} percent',
                onChanged: connected
                    ? (value) => setState(() => _dragging = value)
                    : null,
                // Sent on release, not on every frame. A slider emits dozens of
                // values per second and each one here is an AppleScript
                // round trip on the desktop.
                onChangeEnd: (value) {
                  setState(() => _dragging = null);
                  unawaited(
                    _send(
                      VolumeCommand(mode: VolumeMode.absolute, value: value),
                    ),
                  );
                },
              ),
            ),
            // A scale marker at the end of the slider, not a control.
            const ExcludeSemantics(child: Icon(Icons.volume_up)),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          // Excluded because the slider already announces this number. Left
          // visible because a sighted user cannot read a slider to the percent.
          child: ExcludeSemantics(
            child: Text(
              '${(volume * 100).round()}%',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        if (brightnessSupported) ...<Widget>[
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              const ExcludeSemantics(
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Icon(Icons.brightness_low),
                ),
              ),
              Expanded(
                child: Slider(
                  value: (_brightnessDragging ?? _brightness).clamp(0.0, 1.0),
                  label:
                      '${((_brightnessDragging ?? _brightness) * 100).round()}%',
                  semanticFormatterCallback: (value) =>
                      'Screen brightness ${(value * 100).round()} percent',
                  onChanged: connected
                      ? (value) => setState(() => _brightnessDragging = value)
                      : null,
                  onChangeEnd: (value) {
                    setState(() {
                      _brightness = value;
                      _brightnessDragging = null;
                    });
                    unawaited(
                      _send(
                        BrightnessCommand(relative: false, value: value),
                      ),
                    );
                  },
                ),
              ),
              const ExcludeSemantics(
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Icon(Icons.brightness_high),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: ExcludeSemantics(
              child: Text(
                '${((_brightnessDragging ?? _brightness) * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.state});

  final MediaState? state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = state?.title ?? '';
    final hasTrack = title.isNotEmpty;

    return Column(
      children: <Widget>[
        Container(
          height: 180,
          width: 180,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          // A placeholder where artwork would go. Announcing "music note"
          // before the track title tells a screen-reader user nothing the
          // title will not.
          child: ExcludeSemantics(
            child: Icon(
              Icons.music_note,
              size: 64,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          hasTrack ? title : 'Nothing playing',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasTrack) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            <String>[
              if (state!.artist.isNotEmpty) state!.artist,
              if (state!.album.isNotEmpty) state!.album,
            ].join(' — '),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (state?.sourceApplication != null) ...<Widget>[
          const SizedBox(height: 8),
          Chip(
            label: Text(state!.sourceApplication!),
            visualDensity: VisualDensity.compact,
          ),
        ],
        if (!hasTrack) ...<Widget>[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              // Only shown when genuinely nothing is detected, which now means
              // no audio is playing at all — not merely that the source was
              // unrecognised.
              'Play something and it will appear here. Controls work with '
              'any app, including browsers.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.isPlaying,
    required this.enabled,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });

  final bool isPlaying;
  final bool enabled;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          IconButton.filledTonal(
            iconSize: 32,
            tooltip: 'Previous track',
            onPressed: enabled ? onPrevious : null,
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton.filled(
            iconSize: 44,
            // Names what pressing it does, which is the opposite of the state
            // it reports. "Pause" while paused is a lie a sighted user can see
            // past and a screen-reader user cannot.
            tooltip: isPlaying ? 'Pause' : 'Play',
            onPressed: enabled ? onPlayPause : null,
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          ),
          IconButton.filledTonal(
            iconSize: 32,
            tooltip: 'Next track',
            onPressed: enabled ? onNext : null,
            icon: const Icon(Icons.skip_next),
          ),
        ],
      );
}

class _Unsupported extends StatelessWidget {
  const _Unsupported();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ExcludeSemantics(
                child: Icon(Icons.music_off_outlined, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                'Media control isn’t available',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'This computer didn’t offer media control. It is implemented '
                'on macOS; Windows support is still to come.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}
