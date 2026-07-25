import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../../app/providers.dart';

/// What the phone currently holds, for display.
final class ClipboardState {
  const ClipboardState({
    this.text,
    this.fromDesktop = false,
    this.updatedAt,
    this.sending = false,
  });

  final String? text;

  /// True when this arrived from the computer rather than being copied here.
  final bool fromDesktop;

  final DateTime? updatedAt;
  final bool sending;

  ClipboardState copyWith({
    String? text,
    bool? fromDesktop,
    DateTime? updatedAt,
    bool? sending,
  }) =>
      ClipboardState(
        text: text ?? this.text,
        fromDesktop: fromDesktop ?? this.fromDesktop,
        updatedAt: updatedAt ?? this.updatedAt,
        sending: sending ?? this.sending,
      );
}

/// Mirrors the clipboard between this phone and the connected computer.
///
/// ## Why this is not symmetric, and cannot be
///
/// The brief asks for clipboard sync with no buttons, like Apple's Universal
/// Clipboard. Half of that is achievable and half is not, and the asymmetry is
/// imposed by the platform rather than chosen:
///
/// * **Computer → phone is fully automatic.** An update arrives over the
///   session and is written with `Clipboard.setData`. Writing costs nothing and
///   is invisible.
/// * **Phone → computer cannot be.** Reading the clipboard is what would need
///   to be continuous, and since iOS 14 every programmatic read shows the user
///   a "pasted from" banner. Polling at the desktop's 50 ms would produce a
///   banner storm; even polling once a second would make the app unusable.
///   Android 12+ shows a toast for the same reason.
///
/// So the phone sends its clipboard at the two moments a read is justified:
/// when the app comes to the foreground — the user just switched to it, almost
/// always to use what they copied — and when they explicitly ask. That is one
/// banner per visit rather than one per second, and it covers the actual
/// workflow: copy on the phone, pick up the phone's remote, paste on the
/// computer.
///
/// Universal Clipboard avoids this because it is the operating system. A
/// third-party app is not, and pretending otherwise would just mean shipping
/// something users disable.
final class MobileClipboardController extends StateNotifier<ClipboardState>
    with WidgetsBindingObserver {
  MobileClipboardController(this._ref) : super(const ClipboardState()) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_listen());
  }

  final Ref _ref;
  final Log _log = Log.scoped('mobile.clipboard');

  StreamSubscription<Message>? _messages;

  /// Fingerprint of the content last seen, in either direction.
  ///
  /// The echo guard: without it, content received from the computer would be
  /// read back on the next foreground and sent straight home again.
  Uint8List _lastHash = Uint8List(0);

  int _sequence = 0;

  /// Subscribes to the client's own message stream rather than a provider.
  ///
  /// `RemoteLinkClient.messages` is already flattened across reconnects, so
  /// this survives the session dropping and coming back — which a per-session
  /// subscription would not.
  Future<void> _listen() async {
    final client = await _ref.read(clientProvider.future);
    _messages = client.messages.listen(
      (message) {
        if (message is ClipboardUpdate) unawaited(_applyRemote(message));
      },
      cancelOnError: false,
    );
  }

  /// Writes an update from the computer into the phone's clipboard.
  Future<void> _applyRemote(ClipboardUpdate update) async {
    if (update.isSensitive) {
      // The computer marked this confidential — a password manager, typically.
      // Mirroring it would put it in the phone's clipboard history, quietly
      // undoing the protection the manager was providing.
      _log.debug(() => 'ignoring a clipboard update marked sensitive');
      return;
    }

    final text = update.plainText;
    if (text == null || text.isEmpty) return;

    if (Primitives.constantTimeEquals(update.contentHash, _lastHash)) return;
    _lastHash = update.contentHash;

    await Clipboard.setData(ClipboardData(text: text));
    state = ClipboardState(
      text: text,
      fromDesktop: true,
      updatedAt: DateTime.now(),
    );
    _log.debug(() => 'applied ${text.length} clipboard characters');
  }

  /// Reads this phone's clipboard and sends it, if it has changed.
  ///
  /// [silent] suppresses the "nothing to send" feedback for the automatic
  /// foreground call, where the user did not ask for anything and should not be
  /// told about a no-op.
  Future<bool> sendCurrent({bool silent = false}) async {
    final client = _ref.read(clientProvider).valueOrNull;
    if (client == null || !client.isConnected) return false;

    state = state.copyWith(sending: true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) return false;

      final bytes = utf8.encode(text);
      final digest = await Primitives.sha256(bytes);
      final hash = Uint8List.sublistView(digest, 0, 16);

      // Already synced, in either direction. Re-sending would be harmless but
      // would bump the computer's change counter and could start a loop.
      if (Primitives.constantTimeEquals(hash, _lastHash)) return false;
      _lastHash = hash;

      final identity = await _ref.read(identityProvider.future);
      final sent = await client.send(
        ClipboardUpdate(
          items: <ClipboardItem>[ClipboardItem.text(text)],
          contentHash: hash,
          originDeviceId: identity.id.value,
          originSequence: ++_sequence,
        ),
      );

      if (sent) {
        state = ClipboardState(
          text: text,
          updatedAt: DateTime.now(),
        );
        _log.debug(() => 'sent ${bytes.length} clipboard bytes');
      }
      return sent;
    } on PlatformException catch (e) {
      // A clipboard read can be refused outright — a managed device policy, or
      // the user denying the paste prompt. Not worth an error dialog.
      _log.debug(() => 'clipboard read refused: ${e.message}');
      return false;
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  /// Asks the computer to send its current clipboard.
  Future<void> requestFromDesktop() async {
    final client = _ref.read(clientProvider).valueOrNull;
    if (client == null) return;
    await client.send(const ClipboardRequest());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;

    // The one automatic read. Coming to the foreground is the strongest signal
    // available that the user is about to use what they copied, and it costs a
    // single paste banner per visit instead of one per poll.
    //
    // Android is exempt from the banner but kept on the same schedule: two
    // different sync behaviours would be harder to explain than one.
    if (Platform.isIOS || Platform.isAndroid) {
      unawaited(sendCurrent(silent: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_messages?.cancel());
    super.dispose();
  }
}

final clipboardControllerProvider =
    StateNotifierProvider<MobileClipboardController, ClipboardState>(
  MobileClipboardController.new,
);
