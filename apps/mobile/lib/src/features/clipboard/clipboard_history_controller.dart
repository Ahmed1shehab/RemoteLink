import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rl_core/rl_core.dart';

import '../../app/providers.dart';
import 'clipboard_history_store.dart';

/// The last few things copied on this phone.
///
/// A plain [Provider], created synchronously and doing no I/O. Hydration from
/// storage is the controller's job and happens off to the side, so a phone with
/// no keystore access — a locked device, a test host, a platform channel that
/// is not there — still gets a working in-memory history instead of an error.
final clipboardHistoryProvider = Provider<ClipboardHistory>((ref) {
  final history = ClipboardHistory(clock: ref.watch(clockProvider));
  ref.onDispose(() => unawaited(history.dispose()));
  return history;
});

/// Drives the history list in the clipboard tab.
final class MobileClipboardHistoryController
    extends StateNotifier<ClipboardHistorySnapshot> {
  MobileClipboardHistoryController(this._ref)
      : super(ClipboardHistorySnapshot.empty) {
    _history = _ref.read(clipboardHistoryProvider);
    state = _history.snapshot;
    _changes = _history.changes.listen((snapshot) => state = snapshot);
    unawaited(_restore());
  }

  final Ref _ref;
  final Log _log = Log.scoped('mobile.clipboard.history');

  late final ClipboardHistory _history;
  StreamSubscription<ClipboardHistorySnapshot>? _changes;

  /// Picks up an opted-in history from a previous run.
  ///
  /// The existence of the encrypted file *is* the preference — there is no
  /// separate flag that could disagree with it, and "off" means there is
  /// nothing on the device to find.
  Future<void> _restore() async {
    try {
      final restored = await _history.restore(await _openStore());
      if (restored) {
        _log.debug(
          () => 'restored ${_history.entries.length} clipboard history items',
        );
      }
    } on Object catch (error) {
      // Storage is a convenience here, not a dependency. A phone that cannot
      // reach its keystore should show a working memory-only list rather than
      // an error the user can do nothing about.
      _log.debug(() => 'clipboard history storage unavailable: $error');
    }
  }

  Future<EncryptedClipboardHistoryStore> _openStore() async {
    final keys = await _ref.read(identityStoreProvider.future);
    final base = await getApplicationSupportDirectory();
    return EncryptedClipboardHistoryStore(
      keys: keys,
      file: File('${base.path}/RemoteLink/clipboard_history.enc'),
    );
  }

  /// Turns opt-in persistence on or off.
  ///
  /// Returns whether the request could be honoured; a phone that cannot reach
  /// its keystore stays memory-only rather than pretending otherwise, because
  /// telling a user their clipboard history is saved when it is not is the
  /// wrong way round to be wrong.
  Future<bool> setPersistenceEnabled({required bool enabled}) async {
    try {
      if (!enabled) {
        await _history.disablePersistence();
        return true;
      }
      await _history.enablePersistence(await _openStore());
      return true;
    } on Object catch (error) {
      _log.warn(
        'could not change clipboard history persistence',
        fields: <String, Object?>{'error': error.toString()},
      );
      state = _history.snapshot;
      return false;
    }
  }

  /// Pins or unpins. `false` means the pin limit is already reached.
  bool setPinned(String id, {required bool pinned}) =>
      _history.setPinned(id, pinned: pinned);

  void remove(String id) => _history.remove(id);

  void clear() => _history.clear();

  /// Puts an entry back on this phone's clipboard.
  ///
  /// Writing costs nothing and shows no banner — it is *reading* that iOS
  /// prompts about — so this is the one clipboard operation the phone can do
  /// freely, and it is why the history list is worth having here at all.
  Future<bool> copyToClipboard(ClipboardHistoryEntry entry) async {
    final text = entry.text;
    if (text == null || text.isEmpty) return false;

    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException catch (error) {
      _log.debug(() => 'clipboard write refused: ${error.message}');
      return false;
    }

    // Float it back to the top, matching what copying it by hand would do.
    _history.record(
      kind: entry.kind,
      data: entry.data,
      contentHash: entry.contentHash,
      isConcealed: false,
    );
    return true;
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _changes = null;
    super.dispose();
  }
}

final clipboardHistoryControllerProvider = StateNotifierProvider<
    MobileClipboardHistoryController, ClipboardHistorySnapshot>(
  MobileClipboardHistoryController.new,
);
