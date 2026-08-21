import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';

import '../clipboard/clipboard_controller.dart';
import '../transfer/transfer_controller.dart';

/// Something another app handed to Remote Link through the share sheet.
sealed class SharedPayload {
  const SharedPayload();
}

/// Text or a link, which goes to the computer's clipboard.
final class SharedText extends SharedPayload {
  const SharedText(this.text);

  final String text;
}

/// One or more files, already staged on this phone's disk by the platform side.
final class SharedFiles extends SharedPayload {
  const SharedFiles(this.files);

  final List<({File file, String name})> files;
}

/// Receives shares from the operating system.
///
/// This is the one route past Android's clipboard restriction. An app without
/// window focus cannot read the clipboard — that is the platform's rule and no
/// service, permission or entitlement lifts it — so "copy in another app and
/// have it arrive on the computer" cannot be built. Sharing inverts the
/// direction: the user picks Remote Link, the system hands the content over,
/// and there is no focus rule about a gift.
///
/// The manifest has advertised this app as a share target since it was written.
/// Until now nothing read the intent, so sharing to Remote Link opened the app
/// and silently dropped what was shared.
abstract interface class ShareIntake {
  /// Shares as they arrive.
  Stream<SharedPayload> get shares;

  /// Collects a share that arrived before anything was listening.
  ///
  /// A cold start delivers the intent long before this isolate exists, so the
  /// platform holds the payload and this asks for it once.
  Future<SharedPayload?> takePending();
}

/// The real one, backed by the intent handling in the Android runner.
final class PlatformShareIntake implements ShareIntake {
  PlatformShareIntake() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'shared') return;
      final payload = _decode(call.arguments);
      if (payload != null) _shares.add(payload);
    });
  }

  static const MethodChannel _channel =
      MethodChannel('com.remotelink.app/share');

  static final Log _log = Log.scoped('mobile.share');

  final StreamController<SharedPayload> _shares =
      StreamController<SharedPayload>.broadcast();

  @override
  Stream<SharedPayload> get shares => _shares.stream;

  @override
  Future<SharedPayload?> takePending() async {
    try {
      return _decode(await _channel.invokeMethod<Object?>('takePending'));
    } on PlatformException catch (e) {
      _log.debug(() => 'could not collect a pending share: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Turns the platform's map into a payload, or null if it is not one.
  ///
  /// Everything here crossed a channel from another application's content, so
  /// nothing about its shape is assumed — a malformed share is dropped rather
  /// than crashing the app it was shared into.
  static SharedPayload? _decode(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['type']) {
      case 'text':
        final text = raw['text'];
        if (text is! String || text.trim().isEmpty) return null;
        return SharedText(text);
      case 'files':
        final entries = raw['files'];
        if (entries is! List) return null;
        final files = <({File file, String name})>[];
        for (final entry in entries) {
          if (entry is! Map) continue;
          final path = entry['path'];
          final name = entry['name'];
          if (path is! String || name is! String) continue;
          files.add((file: File(path), name: name));
        }
        return files.isEmpty ? null : SharedFiles(files);
      default:
        return null;
    }
  }
}

/// An intake that never receives anything, for platforms with no share target.
///
/// iOS needs a share extension — a second binary in the app bundle, with its
/// own lifecycle and its own copy of the connection — which is a larger piece
/// of work than the Android intent handling and is not part of this.
final class InertShareIntake implements ShareIntake {
  const InertShareIntake();

  @override
  Stream<SharedPayload> get shares => const Stream<SharedPayload>.empty();

  @override
  Future<SharedPayload?> takePending() async => null;
}

/// The intake for this platform.
final shareIntakeProvider = Provider<ShareIntake>((ref) {
  if (!Platform.isAndroid) return const InertShareIntake();
  return PlatformShareIntake();
});

/// What happened to the last share, for the UI to report.
sealed class ShareOutcome {
  const ShareOutcome();
}

/// Nothing has been shared yet this run.
final class ShareIdle extends ShareOutcome {
  const ShareIdle();
}

/// It reached the computer.
final class ShareSent extends ShareOutcome {
  const ShareSent({required this.description, required this.peerName});

  final String description;
  final String peerName;
}

/// It is waiting for a connection, and will go when one arrives.
final class ShareWaiting extends ShareOutcome {
  const ShareWaiting(this.description);

  final String description;
}

/// It could not be sent, and will not be retried.
final class ShareFailed extends ShareOutcome {
  const ShareFailed(this.reason);

  final String reason;
}

/// Sends what the user shared, once there is somewhere to send it.
///
/// Text goes to the computer's clipboard rather than arriving as a file. That
/// is the whole point of sharing a link from a browser: the user wants to paste
/// it over there, and a `snippet_20260821.txt` in the Downloads folder is not
/// that. Files go through the ordinary transfer path, offer and acceptance
/// included — a share is consent to send, not consent to write on the other
/// machine unasked.
final class ShareController extends StateNotifier<ShareOutcome> {
  ShareController(this._ref) : super(const ShareIdle()) {
    _listen();
  }

  final Ref _ref;
  final Log _log = Log.scoped('mobile.share');

  StreamSubscription<SharedPayload>? _subscription;

  /// A share that arrived with nowhere to send it.
  ///
  /// Held rather than refused. Sharing to a remote-control app is a clear
  /// instruction, and the connection coming up a second later is the ordinary
  /// case — the phone is usually reconnecting when the user shares into it.
  SharedPayload? _waiting;

  void _listen() {
    final intake = _ref.read(shareIntakeProvider);
    _subscription = intake.shares.listen(
      (payload) => unawaited(_handle(payload)),
      cancelOnError: false,
    );
    unawaited(_collectPending(intake));

    // The target, not the connection state, and watched rather than read.
    //
    // Both matter. A target appearing is the only signal that means "there is
    // now somewhere to send this", where a connection can be up while the
    // target is still resolving — which is a real gap, not a theoretical one:
    // a share at cold start arrives while every provider under it is still
    // warming, and a version of this keyed on `ClientState.connected` left it
    // held for ever because the transition had already happened.
    //
    // Watching also keeps the provider alive. Reading it once would evaluate
    // it while the state stream was still loading and cache "no target".
    _ref.listen<TransferTarget?>(
      transferTargetProvider,
      (previous, next) {
        if (next != null) _flush();
      },
      fireImmediately: true,
    );
  }

  Future<void> _collectPending(ShareIntake intake) async {
    final pending = await intake.takePending();
    if (pending != null) await _handle(pending);
  }

  Future<void> _handle(SharedPayload payload) async {
    final target = _ref.read(transferTargetProvider);
    if (target == null) {
      _waiting = payload;
      state = ShareWaiting(_describe(payload));
      _log.info('holding a share until there is a computer to send it to');
      return;
    }

    try {
      switch (payload) {
        case SharedText(:final text):
          final sent = await _ref
              .read(clipboardControllerProvider.notifier)
              .sendText(text);
          state = sent
              ? ShareSent(
                  description: _describe(payload),
                  peerName: target.name,
                )
              : const ShareFailed('The computer would not take it.');
        case SharedFiles(:final files):
          await _ref.read(transferControllerProvider.notifier).sendFiles(
                targetPeerId: target.id,
                targetPeerName: target.name,
                files: <File>[for (final f in files) f.file],
                fileNames: <String>[for (final f in files) f.name],
              );
          state = ShareSent(
            description: _describe(payload),
            peerName: target.name,
          );
      }
    } on Object catch (error) {
      _log.warn('could not send a share', error: error);
      state = ShareFailed('$error');
    }
  }

  void _flush() {
    final waiting = _waiting;
    if (waiting == null) return;
    _waiting = null;
    unawaited(_handle(waiting));
  }

  static String _describe(SharedPayload payload) => switch (payload) {
        SharedText() => 'the text you shared',
        SharedFiles(:final files) when files.length == 1 => files.single.name,
        SharedFiles(:final files) => '${files.length} files',
      };

  /// Clears the last outcome, once the UI has shown it.
  void acknowledge() => state = const ShareIdle();

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

final shareControllerProvider =
    StateNotifierProvider<ShareController, ShareOutcome>(ShareController.new);
