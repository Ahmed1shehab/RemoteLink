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
    this.pollInterval = kClipboardPollInterval,
  })  : _clipboard = clipboard,
        _clock = clock ?? SystemClock();

  final ClipboardBackend _clipboard;
  final DeviceId localDeviceId;
  final Clock _clock;
  final Duration pollInterval;

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
  bool _allowImages = false;

  /// Updates to broadcast to connected phones.
  Stream<ClipboardUpdate> get outbound => _outbound.stream;

  bool get isEnabled => _enabled;

  /// Turns mirroring on or off for this computer.
  void setEnabled({required bool enabled, bool allowImages = false}) {
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
    if (text == null || text.isEmpty) return;

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

    final update = ClipboardUpdate(
      items: <ClipboardItem>[
        // A URL is sent as its own flavour so the phone can offer to open it
        // and macOS can populate the URL pasteboard type.
        ClipboardItem(
          contentType: _looksLikeUrl(text)
              ? ClipboardContentType.url
              : ClipboardContentType.text,
          data: Uint8List.fromList(bytes),
        ),
      ],
      contentHash: hash,
      originDeviceId: localDeviceId.value,
      originSequence: ++_localSequence,
    );

    if (!_outbound.isClosed) _outbound.add(update);
    _log.debug(() => 'broadcasting ${bytes.length} clipboard bytes');
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
    if (text == null) {
      if (!_allowImages) return false;
      _log.debug(() => 'image clipboard flavours are not yet applied');
      return false;
    }

    _recordSelfWrite(update.contentHash);
    _clipboard.writeText(text);
    _currentHash = update.contentHash;

    _log.debug(
      () => 'applied a clipboard update from ${update.originDeviceId}',
      fields: <String, Object?>{'bytes': text.length},
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
    if (text == null || text.isEmpty) return null;

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
    await _outbound.close();
  }
}
