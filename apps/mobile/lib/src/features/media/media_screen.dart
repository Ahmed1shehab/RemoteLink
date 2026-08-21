import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/modern_ui.dart';
import '../../app/motion.dart';
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

  /// What the user just asked playback to become, until the computer answers.
  ///
  /// The transport button used to be drawn purely from the computer's last
  /// reported state, so pressing it did nothing visible until a state push
  /// arrived — and when the computer's guess about a browser tab was stale, or
  /// the link had dropped, nothing arrived at all and the button sat on the
  /// pause glyph however often it was pressed. Showing the requested state
  /// immediately is what makes it feel like a button rather than a readout.
  bool? _requestedIsPlaying;

  /// Gives up on the request above and shows what the computer says.
  ///
  /// The computer has the last word — this is a remote control, and a control
  /// that keeps insisting on a state the machine is not in is worse than one
  /// that admits it.
  Timer? _requestTimeout;

  static const Duration _kRequestGrace = Duration(seconds: 4);

  void _requestPlaying({required bool isPlaying}) {
    _requestTimeout?.cancel();
    setState(() => _requestedIsPlaying = isPlaying);
    _requestTimeout = Timer(_kRequestGrace, () {
      if (mounted) setState(() => _requestedIsPlaying = null);
    });
  }

  @override
  void dispose() {
    _requestTimeout?.cancel();
    super.dispose();
  }

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

    // The moment the computer agrees, stop overriding it: anything after that
    // is the computer's own news — a track ending, someone pressing space on
    // the keyboard — and must not be held back by a stale request.
    ref.listen<AsyncValue<MediaState?>>(mediaStateProvider, (_, next) {
      final reported = next.valueOrNull;
      if (reported == null || _requestedIsPlaying == null) return;
      if (reported.isPlaying == _requestedIsPlaying) {
        _requestTimeout?.cancel();
        setState(() => _requestedIsPlaying = null);
      }
    });
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

    final brightness = _brightnessDragging ?? _brightness;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        _NowPlaying(state: state),
        const SizedBox(height: 24),
        _TransportRow(
          isPlaying: _requestedIsPlaying ?? state?.isPlaying ?? false,
          enabled: connected,
          onPrevious: () => _send(
            const MediaCommand(action: MediaAction.previous),
          ),
          onPlayPause: () {
            _requestPlaying(
              isPlaying: !(_requestedIsPlaying ?? state?.isPlaying ?? false),
            );
            unawaited(_send(const MediaCommand(action: MediaAction.playPause)));
          },
          onNext: () => _send(const MediaCommand(action: MediaAction.next)),
        ),
        const SizedBox(height: 26),
        AppSectionCard(
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: IconButton(
                      tooltip: (state?.isMuted ?? false) ? 'Unmute' : 'Mute',
                      icon: Icon(
                        (state?.isMuted ?? false)
                            ? Icons.volume_off
                            : Icons.volume_mute,
                        size: 21,
                      ),
                      color: scheme.primary,
                      onPressed: connected
                          ? () => _send(
                                const VolumeCommand(
                                  mode: VolumeMode.toggleMute,
                                  value: 0,
                                ),
                              )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Volume',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '${(volume * 100).round()}%',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                        ),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  const ExcludeSemantics(
                    child: Icon(Icons.volume_down_rounded, size: 19),
                  ),
                  Expanded(
                    child: Slider(
                      value: volume.clamp(0.0, 1.0),
                      label: '${(volume * 100).round()}%',
                      semanticFormatterCallback: (value) =>
                          'Volume ${(value * 100).round()} percent',
                      onChanged: connected
                          ? (value) => setState(() => _dragging = value)
                          : null,
                      onChangeEnd: (value) {
                        setState(() => _dragging = null);
                        unawaited(
                          _send(
                            VolumeCommand(
                              mode: VolumeMode.absolute,
                              value: value,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const ExcludeSemantics(child: Icon(Icons.volume_up)),
                ],
              ),
              if (brightnessSupported) ...<Widget>[
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: scheme.tertiary.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.brightness_6_rounded,
                        size: 21,
                        color: scheme.tertiary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Display',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      '${(brightness * 100).round()}%',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.tertiary,
                          ),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    const ExcludeSemantics(
                      child: Icon(Icons.brightness_low, size: 20),
                    ),
                    Expanded(
                      child: Slider(
                        value: brightness.clamp(0.0, 1.0),
                        label: '${(brightness * 100).round()}%',
                        semanticFormatterCallback: (value) =>
                            'Screen brightness ${(value * 100).round()} percent',
                        onChanged: connected
                            ? (value) =>
                                setState(() => _brightnessDragging = value)
                            : null,
                        onChangeEnd: (value) {
                          setState(() {
                            _brightness = value;
                            _brightnessDragging = null;
                          });
                          unawaited(
                            _send(
                              BrightnessCommand(
                                relative: false,
                                value: value,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const ExcludeSemantics(
                      child: Icon(Icons.brightness_high, size: 20),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
          height: 220,
          width: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                scheme.primary.withValues(alpha: 0.94),
                scheme.tertiary.withValues(alpha: 0.78),
              ],
            ),
            borderRadius: BorderRadius.circular(36),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.22),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Positioned(
                top: 20,
                right: 18,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.09),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Icon(
                  hasTrack
                      ? Icons.graphic_eq_rounded
                      : Icons.music_note_rounded,
                  size: 78,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
              if (state?.sourceApplication != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 15,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      state!.sourceApplication!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        AnimatedSwitcher(
          duration: context.motion(const Duration(milliseconds: 220)),
          child: Text(
            hasTrack ? title : 'Nothing playing',
            key: ValueKey<String>(title),
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hasTrack) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            <String>[
              if (state!.artist.isNotEmpty) state!.artist,
              if (state!.album.isNotEmpty) state!.album,
            ].join(' — '),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton.filledTonal(
          constraints: const BoxConstraints.tightFor(width: 56, height: 56),
          iconSize: 28,
          tooltip: 'Previous track',
          onPressed: enabled ? onPrevious : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 22),
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.24),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: IconButton.filled(
            constraints: const BoxConstraints.tightFor(width: 76, height: 76),
            iconSize: 40,
            tooltip: isPlaying ? 'Pause' : 'Play',
            onPressed: enabled ? onPlayPause : null,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
        ),
        const SizedBox(width: 22),
        IconButton.filledTonal(
          constraints: const BoxConstraints.tightFor(width: 56, height: 56),
          iconSize: 28,
          tooltip: 'Next track',
          onPressed: enabled ? onNext : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
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
