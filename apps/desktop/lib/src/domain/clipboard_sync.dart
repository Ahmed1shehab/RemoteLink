import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// How often the clipboard change counter is read.
///
/// 50 ms is chosen against the sub-100 ms sync target: worst-case detection
/// latency is one interval, leaving the rest of the budget for encoding and a
/// LAN round trip. The poll itself is a single system call — `GetClipboard
/// SequenceNumber` on Windows, `changeCount` on macOS — so 20 reads a second
/// costs no measurable CPU. Nothing opens the clipboard unless the counter
/// actually moved.
const Duration kClipboardPollInterval = Duration(milliseconds: 50);

/// Maximum number of recent self-written content hashes retained for echo suppression.
const int kMaxSelfWriteHashes = 3;

/// Time after which a self-written content hash expires and is no longer treated as our own write.
const Duration kSelfWriteExpiry = Duration(seconds: 2);

/// Largest text payload mirrored automatically.
///
/// Someone copying a 50 MB log file should not have it silently pushed to their
/// phone over Wi-Fi. Past this size the sync is offered rather than performed.
const int kMaxAutoSyncTextBytes = 256 * 1024;

/// Largest image payload mirrored automatically (1 MiB).
///
/// Images above this size require explicit user action rather than auto-syncing.
const int kMaxAutoSyncImageBytes = 1024 * 1024;

/// Hard cap on image payload size for clipboard sync (10 MiB).
///
/// Images above this size are skipped; large images belong in file transfer.
const int kMaxImageBytes = 10 * 1024 * 1024;

final class _SelfWrite {
  _SelfWrite({required this.hash, required this.recordedAtMicros});

  final Uint8List hash;
  final int recordedAtMicros;
}

/// Mirrors the clipboard between this computer and connected phones.
///
/// The product requirement is that copying on one device and pasting on the
/// other uses exactly the same muscle memory as copying and pasting on one
/// device: no "send clipboard" button, no confirmation, no visible sync step.
/// Everything below exists to make that safe and stable.
///
/// ## The echo loop, and why content-hash origin tracking solves it
///
/// Naive bidirectional mirroring oscillates forever. The desktop pushes to the
/// phone, the phone's watcher sees a change and pushes back, and the two bounce
/// the same text between them until something gives.
///
/// To break the loop without suppressing deliberate duplicate copies, we record
/// the content hash of writes we perform ourselves (keeping the last
/// [kMaxSelfWriteHashes] hashes, expiring after [kSelfWriteExpiry]). When the
/// watcher observes an OS clipboard change, it hashes the current content: if it
/// matches a recorded self-write, it is recognized as our own echo and suppressed.
/// Genuine user copies (including identical text copied afresh) produce hashes not
/// held in the self-write buffer, and are broadcast normally.
///
/// ## Concurrent changes
///
/// If both sides copy at the same instant, the higher origin sequence wins, and
/// on an exact tie the lexicographically greater device ID does. Both sides run
/// the same rule against the same inputs, so they converge on the same answer
/// without a round trip to negotiate it.
final class ClipboardSyncService {
  ClipboardSyncService({
    required ClipboardBackend clipboard,
    required this.localDeviceId,
    Clock? clock,
    ClipboardHistory? history,
    this.pollInterval = kClipboardPollInterval,
    bool allowImages = true,
  })  : _clipboard = clipboard,
        _clock = clock ?? SystemClock(),
        _allowImages = allowImages,
        _providedHistory = history;

  final ClipboardBackend _clipboard;
  final DeviceId localDeviceId;
  final Clock _clock;
  final Duration pollInterval;

  final ClipboardHistory? _providedHistory;

  /// The last few things copied on this computer.
  ///
  /// Injected when the app owns it — the UI needs the same instance the sync
  /// path writes to, and it outlives any single service restart — and created
  /// here otherwise so a test or a headless run gets a working history without
  /// having to assemble one.
  late final ClipboardHistory history =
      _providedHistory ?? ClipboardHistory(clock: _clock);

  final Log _log = Log.scoped('desktop.clipboard');
  final StreamController<ClipboardUpdate> _outbound =
      StreamController<ClipboardUpdate>.broadcast();

  Timer? _poller;
  int _lastChangeCount = -1;

  /// Hash of the content currently held, used to skip no-op updates.
  Uint8List _currentHash = Uint8List(0);

  /// Recent self-written hashes for echo suppression.
  final List<_SelfWrite> _selfWrites = <_SelfWrite>[];

  int _localSequence = 0;
  bool _enabled = true;
  bool _allowImages = true;

  /// Updates to broadcast to connected phones.
  Stream<ClipboardUpdate> get outbound => _outbound.stream;

  bool get isEnabled => _enabled;

  /// Turns mirroring on or off for this computer.
  void setEnabled({required bool enabled, bool allowImages = true}) {
    _enabled = enabled;
    _allowImages = allowImages;
    if (!enabled) {
      _log.info('clipboard mirroring disabled');
    }
  }

  /// Begins watching.
  void start() {
    if (_poller != null) return;
    if (!_clipboard.isAvailable) {
      _log.warn('clipboard backend unavailable; mirroring will not run');
      return;
    }

    // Seed the counter so the clipboard's existing contents are not immediately
    // broadcast as though they were new. Pushing whatever happened to be
    // copied hours ago the moment a phone connects would be surprising and
    // occasionally a privacy problem.
    _lastChangeCount = _clipboard.changeCount;
    _poller = Timer.periodic(pollInterval, (_) => _poll());
    _log.info('watching the clipboard');
  }

  void _recordSelfWrite(Uint8List hash) {
    _pruneExpiredSelfWrites();
    if (_selfWrites.length >= kMaxSelfWriteHashes) {
      _selfWrites.removeAt(0);
    }
    _selfWrites.add(
      _SelfWrite(
        hash: hash,
        recordedAtMicros: _clock.monotonicMicros(),
      ),
    );
  }

  void _pruneExpiredSelfWrites() {
    final now = _clock.monotonicMicros();
    final expiryMicros = kSelfWriteExpiry.inMicroseconds;
    _selfWrites.removeWhere(
      (entry) => (now - entry.recordedAtMicros) > expiryMicros,
    );
  }

  bool _isSelfWrite(Uint8List hash) {
    _pruneExpiredSelfWrites();
    final index = _selfWrites.indexWhere(
      (entry) => Primitives.constantTimeEquals(entry.hash, hash),
    );
    if (index != -1) {
      _selfWrites.removeAt(index);
      return true;
    }
    return false;
  }

  /// The only path from the clipboard into the history.
  ///
  /// It re-reads [ClipboardBackend.isConcealed] rather than relying on the
  /// early return in [_poll] having already covered it. That looks redundant
  /// today and is the point: the caller's check is an ordering property of one
  /// method, and ordering properties do not survive refactoring, while a check
  /// welded to the recording call does. A password manager's entry becoming a
  /// persisted history row is the one failure this feature cannot have.
  void _recordHistory({
    required ClipboardHistoryKind kind,
    required Uint8List data,
    required Uint8List hash,
    bool markedSensitive = false,
  }) {
    history.record(
      kind: kind,
      data: data,
      contentHash: hash,
      isConcealed: markedSensitive || _clipboard.isConcealed,
    );
  }

  /// Maps a wire flavour to a history kind.
  ///
  /// A local mapping rather than a shared enum: the history is not a message
  /// type, and giving it one would put a UI list inside the append-only wire
  /// contract for no gain.
  static ClipboardHistoryKind _kindFor(ClipboardContentType type) =>
      switch (type) {
        ClipboardContentType.url => ClipboardHistoryKind.url,
        ClipboardContentType.html => ClipboardHistoryKind.html,
        ClipboardContentType.imagePng => ClipboardHistoryKind.image,
        _ => ClipboardHistoryKind.text,
      };

  Future<void> _poll() async {
    if (!_enabled) return;

    final count = _clipboard.changeCount;
    if (count == _lastChangeCount) return;
    _lastChangeCount = count;

    // A password manager marking its entry confidential is an explicit request
    // not to have it copied elsewhere. Honouring it matters: mirroring would
    // land the password in the phone's clipboard history and quietly undo the
    // manager's whole security model.
    if (_clipboard.isConcealed) {
      _log.debug(() => 'clipboard entry is marked concealed; not mirroring');
      return;
    }

    final text = _clipboard.readText();
    if (text != null && text.isNotEmpty) {
      final bytes = utf8.encode(text);
      if (bytes.length > kMaxAutoSyncTextBytes) {
        _log.info(
          'clipboard content too large to mirror automatically',
          fields: <String, Object?>{'bytes': bytes.length},
        );
        return;
      }

      final hash = await _hash(bytes);
      if (_isSelfWrite(hash)) {
        _log.debug(() => 'suppressed the echo of our own clipboard write');
        return;
      }

      _currentHash = hash;

      final isUrl = _looksLikeUrl(text);
      _recordHistory(
        kind: isUrl ? ClipboardHistoryKind.url : ClipboardHistoryKind.text,
        data: Uint8List.fromList(bytes),
        hash: hash,
      );

      final update = ClipboardUpdate(
        items: <ClipboardItem>[
          // A URL is sent as its own flavour so the phone can offer to open it
          // and macOS can populate the URL pasteboard type.
          ClipboardItem(
            contentType:
                isUrl ? ClipboardContentType.url : ClipboardContentType.text,
            data: Uint8List.fromList(bytes),
          ),
        ],
        contentHash: hash,
        originDeviceId: localDeviceId.value,
        originSequence: ++_localSequence,
      );

      if (!_outbound.isClosed) _outbound.add(update);
      _log.debug(() => 'broadcasting ${bytes.length} clipboard bytes');
      return;
    }

    if (_allowImages) {
      final imageBytes = _clipboard.readImagePng();
      if (imageBytes != null && imageBytes.isNotEmpty) {
        if (imageBytes.length > kMaxImageBytes) {
          _log.info(
            'clipboard image exceeds 10 MiB cap; skipping (large images belong in file transfer)',
            fields: <String, Object?>{'bytes': imageBytes.length},
          );
          return;
        }

        if (imageBytes.length > kMaxAutoSyncImageBytes) {
          _log.info(
            'clipboard image too large to mirror automatically (> 1 MiB requires explicit user action)',
            fields: <String, Object?>{'bytes': imageBytes.length},
          );
          return;
        }

        final data = imageBytes is Uint8List
            ? imageBytes
            : Uint8List.fromList(imageBytes);
        final hash = await _hash(data);
        if (_isSelfWrite(hash)) {
          _log.debug(
            () => 'suppressed the echo of our own clipboard image write',
          );
          return;
        }

        _currentHash = hash;

        _recordHistory(
          kind: ClipboardHistoryKind.image,
          data: data,
          hash: hash,
        );

        final update = ClipboardUpdate(
          items: <ClipboardItem>[
            ClipboardItem(
              contentType: ClipboardContentType.imagePng,
              data: data,
            ),
          ],
          contentHash: hash,
          originDeviceId: localDeviceId.value,
          originSequence: ++_localSequence,
        );

        if (!_outbound.isClosed) _outbound.add(update);
        _log.debug(
          () => 'broadcasting ${data.length} clipboard image bytes',
        );
      }
    }
  }

  /// Applies an update received from a phone.
  ///
  /// Returns `false` when the update was ignored, which the caller reports in
  /// the connection status so a user watching the diagnostics panel can see
  /// that sync is working even when nothing appears to happen.
  Future<bool> applyRemote(ClipboardUpdate update) async {
    if (!_enabled || !_clipboard.isAvailable) return false;
    if (update.isSensitive) {
      _log.debug(() => 'ignoring an update marked sensitive');
      return false;
    }

    if (Primitives.constantTimeEquals(update.contentHash, _currentHash)) {
      // Already holding exactly this. Writing it again would bump the change
      // counter and start the loop we spent this whole class avoiding.
      return false;
    }

    final text = update.plainText;
    if (text != null) {
      _recordSelfWrite(update.contentHash);
      _clipboard.writeText(text);
      _currentHash = update.contentHash;

      // Content that arrived from the phone is now on this computer's
      // clipboard, so it belongs in this computer's history. The poller will
      // recognise it as our own write and not record it twice.
      var flavour = ClipboardHistoryKind.text;
      for (final item in update.items) {
        if (item.contentType == ClipboardContentType.imagePng) continue;
        flavour = _kindFor(item.contentType);
        break;
      }

      _recordHistory(
        kind: flavour,
        data: Uint8List.fromList(utf8.encode(text)),
        hash: update.contentHash,
        markedSensitive: update.isSensitive,
      );

      _log.debug(
        () => 'applied a clipboard update from ${update.originDeviceId}',
        fields: <String, Object?>{'bytes': text.length},
      );
      return true;
    }

    if (!_allowImages) return false;

    ClipboardItem? imageItem;
    for (final item in update.items) {
      if (item.contentType == ClipboardContentType.imagePng) {
        imageItem = item;
        break;
      }
    }

    if (imageItem == null) return false;

    if (imageItem.data.length > kMaxImageBytes) {
      _log.info(
        'inbound clipboard image exceeds 10 MiB cap; skipping',
        fields: <String, Object?>{'bytes': imageItem.data.length},
      );
      return false;
    }

    _recordSelfWrite(update.contentHash);
    _clipboard.writeImagePng(imageItem.data);
    _currentHash = update.contentHash;

    _recordHistory(
      kind: ClipboardHistoryKind.image,
      data: imageItem.data,
      hash: update.contentHash,
      markedSensitive: update.isSensitive,
    );

    _log.debug(
      () => 'applied a clipboard image update from ${update.originDeviceId}',
      fields: <String, Object?>{'bytes': imageItem.data.length},
    );
    return true;
  }

  /// The current clipboard as an update, for answering a request on connect.
  ///
  /// A phone that was asleep while the user copied still gets the content the
  /// moment it wakes, which is what makes "copy here, walk over there, paste"
  /// work rather than only syncing while both devices happen to be awake.
  Future<ClipboardUpdate?> snapshot() async {
    if (!_enabled || !_clipboard.isAvailable) return null;
    if (_clipboard.isConcealed) return null;

    final text = _clipboard.readText();
    if (text != null && text.isNotEmpty) {
      final bytes = utf8.encode(text);
      if (bytes.length > kMaxAutoSyncTextBytes) return null;

      return ClipboardUpdate(
        items: <ClipboardItem>[
          ClipboardItem(
            contentType: _looksLikeUrl(text)
                ? ClipboardContentType.url
                : ClipboardContentType.text,
            data: Uint8List.fromList(bytes),
          ),
        ],
        contentHash: await _hash(bytes),
        originDeviceId: localDeviceId.value,
        originSequence: _localSequence,
        isSensitive: false,
      );
    }

    if (_allowImages) {
      final imageBytes = _clipboard.readImagePng();
      if (imageBytes != null &&
          imageBytes.isNotEmpty &&
          imageBytes.length <= kMaxAutoSyncImageBytes) {
        final data = imageBytes is Uint8List
            ? imageBytes
            : Uint8List.fromList(imageBytes);
        return ClipboardUpdate(
          items: <ClipboardItem>[
            ClipboardItem(
              contentType: ClipboardContentType.imagePng,
              data: data,
            ),
          ],
          contentHash: await _hash(data),
          originDeviceId: localDeviceId.value,
          originSequence: _localSequence,
          isSensitive: false,
        );
      }
    }

    return null;
  }

  /// Puts a history entry back on this computer's clipboard.
  ///
  /// Deliberately does *not* record a self-write hash. Re-copying is a user
  /// action, indistinguishable in intent from copying the thing again by hand,
  /// so the poller should see it, broadcast it to the phone, and float it back
  /// to the top of the history — which is exactly what happens if we stay out
  /// of the way.
  bool recopy(ClipboardHistoryEntry entry) {
    if (!_clipboard.isAvailable) return false;

    if (entry.isImage) {
      if (!_allowImages) return false;
      _clipboard.writeImagePng(entry.data);
    } else {
      final text = entry.text;
      if (text == null || text.isEmpty) return false;
      _clipboard.writeText(text);
    }

    _log.debug(() => 'copied a history entry back to the clipboard');
    return true;
  }

  /// Decides a simultaneous-change conflict.
  ///
  /// Deterministic on both sides from the same inputs, so the two devices
  /// converge without exchanging another message.
  bool remoteWins(ClipboardUpdate remote) {
    if (remote.originSequence != _localSequence) {
      return remote.originSequence > _localSequence;
    }
    return remote.originDeviceId.compareTo(localDeviceId.value) > 0;
  }

  /// First 16 bytes of SHA-256.
  ///
  /// Truncated because this is a change-detection fingerprint, not a security
  /// control; 128 bits makes an accidental collision impossible in practice and
  /// halves the bytes on the wire.
  Future<Uint8List> _hash(List<int> bytes) async {
    final digest = await Primitives.sha256(bytes);
    return Uint8List.sublistView(digest, 0, 16);
  }

  static final RegExp _urlPattern = RegExp(
    r'^(https?|ftp|mailto|file)://\S+$|^mailto:\S+$',
    caseSensitive: false,
  );

  bool _looksLikeUrl(String text) {
    final trimmed = text.trim();
    // Single-token check: a paragraph that merely contains a link is still
    // text, and typing it as a URL would make the phone offer to open it.
    if (trimmed.contains(RegExp(r'\s'))) return false;
    return _urlPattern.hasMatch(trimmed);
  }

  Future<void> dispose() async {
    _poller?.cancel();
    _poller = null;
    // Only the history this service made is this service's to close. An
    // injected one outlives the service — the window still renders it after a
    // restart of the listener.
    if (_providedHistory == null) await history.dispose();
    await _outbound.close();
  }
}
