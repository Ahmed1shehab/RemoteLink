import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';

/// Screen frames pushed from the desktop.
final screenFrameProvider =
    StreamProvider.autoDispose<ScreenFrame?>((ref) async* {
  final client = await ref.watch(clientProvider.future);
  yield null;
  await for (final message in client.messages) {
    if (message is ScreenFrame) yield message;
  }
});

/// Live screen viewer screen showing desktop frames and controls.
class ScreenViewerScreen extends ConsumerStatefulWidget {
  const ScreenViewerScreen({super.key});

  @override
  ConsumerState<ScreenViewerScreen> createState() => _ScreenViewerScreenState();
}

class _ScreenViewerScreenState extends ConsumerState<ScreenViewerScreen> {
  RemoteLinkClient? _client;
  bool _isStreaming = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startStream();
    });
  }

  Future<void> _startStream() async {
    final client = ref.read(clientProvider).valueOrNull;
    if (client == null || !client.isConnected) return;
    _client = client;
    final capabilities = client.session?.capabilities;
    if (capabilities == null || !capabilities.has(Capabilities.screenCapture)) {
      return;
    }

    setState(() => _isStreaming = true);
    await client.send(
      const ScreenStreamStart(
        targetFps: 30,
        codec: ScreenCodec.jpeg,
        maxWidth: 1920,
        maxHeight: 1080,
      ),
    );
  }

  Future<void> _stopStream({bool pop = false}) async {
    final client = _client ?? ref.read(clientProvider).valueOrNull;
    if (client != null && client.isConnected) {
      await client.send(
        const ScreenStreamStop(reason: ScreenStopReason.userClosed),
      );
    }
    if (mounted) {
      setState(() => _isStreaming = false);
      if (pop) {
        await Navigator.of(context).maybePop();
      }
    }
  }

  @override
  void dispose() {
    if (_isStreaming && _client != null && _client!.isConnected) {
      unawaited(
        _client!.send(
          const ScreenStreamStop(reason: ScreenStopReason.userClosed),
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        ref.watch(clientStateProvider).valueOrNull == ClientState.connected;
    final capabilities =
        ref.watch(clientProvider).valueOrNull?.session?.capabilities;
    final supported = capabilities?.has(Capabilities.screenCapture) ?? false;

    if (!connected || !supported) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Screen Stream'),
        ),
        body: const _UnsupportedScreenViewer(),
      );
    }

    final frameAsync = ref.watch(screenFrameProvider);
    final frame = frameAsync.valueOrNull;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Screen Stream'),
        actions: <Widget>[
          if (frame != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  '${frame.width}×${frame.height}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(_isStreaming
                ? Icons.stop_circle_outlined
                : Icons.play_circle_outlined),
            tooltip: _isStreaming ? 'Stop Streaming' : 'Start Streaming',
            onPressed: () {
              if (_isStreaming) {
                _stopStream();
              } else {
                _startStream();
              }
            },
          ),
        ],
      ),
      body: Center(
        child: frame != null
            ? Image.memory(
                frame.data,
                gaplessPlayback: true,
                fit: BoxFit.contain,
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ExcludeSemantics(
                    child: Icon(
                      Icons.screen_share_outlined,
                      size: 48,
                      color: Colors.white54,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Waiting for screen frames...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
      ),
      floatingActionButton: _isStreaming
          ? FloatingActionButton.extended(
              onPressed: () => _stopStream(pop: true),
              icon: const Icon(Icons.stop),
              label: const Text('Stop Sharing'),
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            )
          : FloatingActionButton.extended(
              onPressed: _startStream,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Stream'),
            ),
    );
  }
}

class _UnsupportedScreenViewer extends StatelessWidget {
  const _UnsupportedScreenViewer();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ExcludeSemantics(
                child: Icon(Icons.screen_share_outlined, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                'Screen sharing isn’t available',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'This computer cannot share its screen. Screen capture is '
                'supported on macOS when Screen Recording permission is granted.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}
