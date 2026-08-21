import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
// For WidgetsBindingObserver and AppLifecycleState. `services.dart` alone gives
// Clipboard but not the binding, which is what makes the foreground hook work.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import 'clipboard_history_controller.dart';
import 'clipboard_watcher.dart';

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
/// ## What is automatic, and where the limit actually is
///
/// Nothing here needs a button pressed:
///
/// * **Computer → phone.** An update arrives over the session and is written
///   with `Clipboard.setData`. Writing costs nothing and is invisible.
/// * **Phone → computer.** A [ClipboardWatcher] reports that the clipboard
///   changed — without reading it — and that is what triggers the one read.
///   Copy anything on the phone and it is on the computer a moment later.
///
/// The limit that remains is not this app's to lift: **the phone must be in
/// the foreground.** Android refuses clipboard reads to apps without focus,
/// and has since Android 10; iOS puts a permission alert in front of them. So
/// "copy on the phone with Remote Link buried in the background, paste on the
/// computer" cannot work from user space, and the resume hook below is what
/// covers it — the app catches up the moment it is looked at again.
///
/// Reading is also why this is driven by change notifications rather than by
/// polling: every read is an interruption on both platforms (a toast on
/// Android 12+, an alert on iOS 16+), so it happens once per copy, at the
/// moment there is something new to send, and never on a timer.
///
/// Universal Clipboard has neither restriction because it is the operating
/// system. A third-party app is not, and the honest version of this feature is
/// one that says so rather than one that silently stops working when the
/// screen locks.
final class MobileClipboardController extends StateNotifier<ClipboardState>
    with WidgetsBindingObserver {
  MobileClipboardController(
    this._ref, {
    ClipboardWatcher watcher = const PlatformClipboardWatcher(),
  })  : _watcher = watcher,
        super(const ClipboardState()) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_listen());
    // The app is in the foreground when this is built — that is what building
    // it means — so the watcher starts now rather than waiting for a resume
    // that will not come until the user has already left and returned.
    _startWatching();
  }

  final Ref _ref;
  final ClipboardWatcher _watcher;
  final Log _log = Log.scoped('mobile.clipboard');

  StreamSubscription<Message>? _messages;
  StreamSubscription<ClientState>? _states;
  StreamSubscription<void>? _clipboardChanges;
  Timer? _settle;

  /// Set when a send was wanted but the link was down.
  ///
  /// The link dropping is not the exception on a phone, it is the normal
  /// shape of the thing: Android freezes a backgrounded app and takes its
  /// sockets with it, so returning to Remote Link and reconnecting are
  /// seconds apart — and the copy the user made in between falls exactly in
  /// that gap. Without this, that copy was read, found undeliverable, and
  /// dropped, and nothing ever asked again.
  bool _sendWhenReconnected = false;

  /// When this controller last wrote the phone's clipboard itself.
  ///
  /// Writing fires the same change notification a user copy does, and the two
  /// are indistinguishable from the outside. Without this, every update from
  /// the computer would provoke a read on the phone — and a read is a toast on
  /// Android and an alert on iOS, so the user would be interrupted by their
  /// own clipboard arriving. The [_lastHash] guard would still stop the update
  /// being echoed back; it would just stop it after the interruption.
  DateTime? _lastSelfWrite;

  /// How long after our own write a change notification is treated as ours.
  ///
  /// Generous, because it only ever costs a send that [_lastHash] would have
  /// refused anyway: a user copying something new inside this window has their
  /// copy picked up by the next change, the next resume, or the Send button.
  static const Duration _kSelfWriteWindow = Duration(seconds: 2);

  /// How long to wait for the clipboard to stop changing before reading it.
  ///
  /// One copy can produce several notifications — an app that writes plain
  /// text and then the rich version of it fires twice — and each read is an
  /// interruption. Waiting a moment turns a burst into one read of the final
  /// content.
  static const Duration _kSettleDelay = Duration(milliseconds: 300);

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
        if (message is ClipboardSyncToggle) unawaited(_onSyncToggle(message));
      },
      cancelOnError: false,
    );
    // No flush without this. The states stream is the only thing that says the
    // link came back, and the copy the drop interrupted is waiting on it.
    _states = client.states.listen(
      (state) {
        if (state == ClientState.connected) _flushDeferredSend();
      },
      cancelOnError: false,
    );
  }

  /// Sends the clipboard a dropped link stopped us sending.
  ///
  /// Only while the watcher is running, which is this controller's one signal
  /// that the app is on screen. A reconnect that lands with Remote Link in the
  /// background is a read Android would refuse anyway, and the deferral is
  /// kept rather than spent — the next resume is where it belongs.
  void _flushDeferredSend() {
    if (!_sendWhenReconnected || _clipboardChanges == null) return;
    _log.debug(() => 'the link is back; sending the copy it missed');
    unawaited(sendCurrent(silent: true));
  }

  Future<void> _onSyncToggle(ClipboardSyncToggle toggle) async {
    await _ref
        .read(clipboardSettingsProvider.notifier)
        .setSyncFromDesktop(toggle.enabled);
    await _ref
        .read(clipboardSettingsProvider.notifier)
        .setSyncToDesktop(toggle.enabled);
  }

  /// Toggles clipboard sync on or off, and notifies the connected desktop.
  Future<void> toggleSync(bool enabled) async {
    await _ref
        .read(clipboardSettingsProvider.notifier)
        .setSyncFromDesktop(enabled);
    await _ref
        .read(clipboardSettingsProvider.notifier)
        .setSyncToDesktop(enabled);

    final client = _ref.read(clientProvider).valueOrNull;
    if (client != null && client.isConnected) {
      await client.send(
        ClipboardSyncToggle(
          enabled: enabled,
          allowImages: enabled,
          allowFiles: false,
        ),
      );
    }
  }

  /// Writes an update from the computer into the phone's clipboard.
  Future<void> _applyRemote(ClipboardUpdate update) async {
    // Adopted before anything can return early, and deliberately so. This is
    // a Lamport clock: seeing a message advances it whether or not the message
    // is used, and the desktop breaks an equal-clock tie by device id.
    // Adopting it further down — after the "same content" and "sync disabled"
    // guards, where it used to live — left the phone's counter behind the
    // computer's, so the phone's next copy tied, lost the tie-break, and was
    // discarded. From the user's side the clipboard simply did not sync, with
    // the only trace a debug line on the other machine.
    if (update.originSequence > _sequence) {
      _sequence = update.originSequence;
    }

    final settings = _ref.read(clipboardSettingsProvider);
    if (!settings.syncFromDesktop) {
      _log.debug(
          () => 'ignoring a clipboard update; sync from desktop disabled');
      return;
    }

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

    _lastSelfWrite = DateTime.now();
    await Clipboard.setData(ClipboardData(text: text));
    state = ClipboardState(
      text: text,
      fromDesktop: true,
      updatedAt: DateTime.now(),
    );

    // It is on this phone's clipboard now, so it belongs in this phone's
    // history. `isSensitive` was already refused above; passing it again is the
    // guard that survives someone rearranging the checks later.
    _recordHistory(
      kind: _kindFor(update),
      data: Uint8List.fromList(utf8.encode(text)),
      hash: update.contentHash,
      markedSensitive: update.isSensitive,
    );

    _log.debug(() => 'applied ${text.length} clipboard characters');
  }

  /// Puts [text] on the computer's clipboard without reading this phone's.
  ///
  /// For content that arrived some other way — the share sheet, principally,
  /// which is how a copy made in another app reaches the computer at all when
  /// Android will not serve this one a clipboard read.
  ///
  /// It goes through the same bookkeeping as a local copy, so it takes its turn
  /// in the same clock and cannot be echoed back.
  Future<bool> sendText(String text) async {
    if (text.isEmpty) return false;
    return _send(text);
  }

  /// Reads this phone's clipboard and sends it, if it has changed.
  ///
  /// [silent] suppresses the "nothing to send" feedback for the automatic
  /// foreground call, where the user did not ask for anything and should not be
  /// told about a no-op.
  Future<bool> sendCurrent({bool silent = false}) async {
    final settings = _ref.read(clipboardSettingsProvider);
    if (!settings.syncToDesktop) {
      _log.debug(() => 'skipping clipboard send; sync to desktop disabled');
      return false;
    }

    final client = _ref.read(clientProvider).valueOrNull;
    if (client == null || !client.isConnected) {
      // Deferred, not dropped. The clipboard is read on reconnect instead of
      // now, because reading it now would cost the user an interruption for
      // content that has nowhere to go.
      _sendWhenReconnected = true;
      _log.debug(() => 'nothing to send to; holding the copy for the reconnect');
      return false;
    }
    _sendWhenReconnected = false;

    state = state.copyWith(sending: true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) return false;
      return await _send(text);
    } on PlatformException catch (e) {
      // A clipboard read can be refused outright — a managed device policy, or
      // the user denying the paste prompt. Not worth an error dialog.
      _log.debug(() => 'clipboard read refused: ${e.message}');
      return false;
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  /// Puts [text] on the computer's clipboard and records it here.
  ///
  /// The one path out, whether the text came from a clipboard read or from a
  /// share: the hash guard, the clock and the local history all have to happen
  /// exactly once per piece of content, and two call sites doing it separately
  /// is how they drift apart.
  Future<bool> _send(String text) async {
    final client = _ref.read(clientProvider).valueOrNull;
    if (client == null || !client.isConnected) return false;

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
      state = ClipboardState(text: text, updatedAt: DateTime.now());
      _recordHistory(
        kind: ClipboardHistoryKind.text,
        data: Uint8List.fromList(bytes),
        hash: hash,
      );
      _log.debug(() => 'sent ${bytes.length} clipboard bytes');
    }
    return sent;
  }

  /// The only path from this phone's clipboard into its history.
  ///
  /// Funnelled through one method, with the "must this be forgotten?" question
  /// as a parameter that cannot be omitted, so the rule holds by construction
  /// rather than by every call site remembering to check first. The phone has
  /// no equivalent of `ConcealedType` to read locally — iOS and Android give an
  /// app no way to see that flag — so the desktop's `isSensitive` is the only
  /// signal available, and it is honoured here as well as in [_applyRemote].
  void _recordHistory({
    required ClipboardHistoryKind kind,
    required Uint8List data,
    required Uint8List hash,
    bool markedSensitive = false,
  }) {
    _ref.read(clipboardHistoryProvider).record(
          kind: kind,
          data: data,
          contentHash: hash,
          isConcealed: markedSensitive,
        );
  }

  /// Maps the update's first text-ish flavour to a history kind.
  ///
  /// A local mapping rather than a shared enum: history is not a message type,
  /// and giving it one would drag a UI list into the append-only wire contract
  /// for nothing.
  static ClipboardHistoryKind _kindFor(ClipboardUpdate update) {
    for (final item in update.items) {
      switch (item.contentType) {
        case ClipboardContentType.url:
          return ClipboardHistoryKind.url;
        case ClipboardContentType.html:
          return ClipboardHistoryKind.html;
        case ClipboardContentType.text:
          return ClipboardHistoryKind.text;
        default:
          // Every other flavour reaching us with usable plain text is recorded
          // as text, which is what `update.plainText` gave us.
          break;
      }
    }
    return ClipboardHistoryKind.text;
  }

  /// Asks the computer to send its current clipboard.
  Future<void> requestFromDesktop() async {
    final client = _ref.read(clientProvider).valueOrNull;
    if (client == null) return;
    await client.send(const ClipboardRequest());
  }

  /// Subscribes to clipboard changes, which is also what starts the platform
  /// watcher.
  void _startWatching() {
    if (_clipboardChanges != null) return;
    _clipboardChanges = _watcher.changes.listen(
      (_) => _onClipboardChanged(),
      cancelOnError: false,
    );
  }

  /// Cancels it, which is also what stops the platform watcher.
  void _stopWatching() {
    unawaited(_clipboardChanges?.cancel());
    _clipboardChanges = null;
    _settle?.cancel();
    _settle = null;
  }

  void _onClipboardChanged() {
    final selfWrite = _lastSelfWrite;
    if (selfWrite != null &&
        DateTime.now().difference(selfWrite) < _kSelfWriteWindow) {
      _log.debug(() => 'ignoring the change our own clipboard write caused');
      return;
    }

    _settle?.cancel();
    _settle = Timer(_kSettleDelay, () => unawaited(sendCurrent(silent: true)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Nothing to watch from the background: Android will not serve a
      // clipboard read to an app without focus, so a watcher left running
      // there reports changes that cannot be acted on.
      _stopWatching();
      return;
    }

    _startWatching();
    // A reconnect that happened while this app was in the background left its
    // deferral unspent on purpose. This is the moment it is owed.
    _flushDeferredSend();

    final settings = _ref.read(clipboardSettingsProvider);
    if (!settings.syncToDesktop) return;

    // Still read on resume, and not only when the watcher fires. Everything
    // copied while this app was in the background happened where no watcher of
    // ours could see it, and coming to the foreground is the moment that
    // backlog is worth one read.
    if (Platform.isIOS || Platform.isAndroid) {
      unawaited(sendCurrent(silent: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopWatching();
    unawaited(_messages?.cancel());
    unawaited(_states?.cancel());
    super.dispose();
  }
}

final clipboardControllerProvider =
    StateNotifierProvider<MobileClipboardController, ClipboardState>(
  MobileClipboardController.new,
);
