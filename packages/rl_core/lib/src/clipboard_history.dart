import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'clock.dart';
import 'logging.dart';

/// How many entries a clipboard history keeps.
///
/// Twenty-five is the product number from RL-411, and it is small on purpose. A
/// clipboard history is a convenience for the last few things you copied, not
/// an archive; every entry retained past usefulness is one more copy of
/// something private sitting in memory (and, when persistence is on, on disk).
const int kClipboardHistoryCapacity = 25;

/// How many entries may be pinned at once.
///
/// One below the capacity, and the arithmetic is load-bearing rather than
/// arbitrary. Pinned entries are exempt from eviction, so if every slot could
/// be pinned the ring would have no victim to evict and would either grow
/// without bound or silently start dropping new copies. Leaving one unpinnable
/// slot means eviction always has somewhere to go and the cap of
/// [kClipboardHistoryCapacity] is a real bound rather than an aspiration.
const int kMaxPinnedClipboardEntries = kClipboardHistoryCapacity - 1;

/// What a history entry holds.
///
/// This deliberately mirrors `ClipboardContentType` in `rl_protocol` without
/// depending on it. History is a local concern — it is never sent, never
/// received, and adds no message type — so tying it to the wire enum would
/// couple a UI list to a compatibility guarantee it has no business in, and
/// would point the dependency arrow backwards besides ([rl_core] sits beneath
/// `rl_protocol`).
enum ClipboardHistoryKind {
  text,
  url,
  html,
  image;

  /// Stable name used in the persisted form.
  ///
  /// Written out rather than using [Enum.index] so that reordering this enum
  /// cannot silently reinterpret an existing file.
  String get storageKey => name;

  static ClipboardHistoryKind? fromStorageKey(String? key) {
    for (final kind in values) {
      if (kind.storageKey == key) return kind;
    }
    return null;
  }
}

/// One remembered clipboard item.
@immutable
final class ClipboardHistoryEntry {
  const ClipboardHistoryEntry({
    required this.id,
    required this.kind,
    required this.data,
    required this.contentHash,
    required this.copiedAt,
    this.pinned = false,
  });

  /// Stable identity, derived from the content and the moment it was copied.
  ///
  /// Derived rather than random so it survives a persistence round trip without
  /// needing a UUID dependency, and so the same entry keeps the same identity
  /// across a reload — which is what makes a pin stick to the row the user
  /// pinned rather than to a position in a list.
  final String id;

  final ClipboardHistoryKind kind;

  /// Raw bytes: UTF-8 for the text kinds, PNG for [ClipboardHistoryKind.image].
  final Uint8List data;

  /// The same 16-byte fingerprint the sync path uses, reused here for dedup.
  final Uint8List contentHash;

  final DateTime copiedAt;

  /// Pinned entries are exempt from ring eviction.
  final bool pinned;

  bool get isImage => kind == ClipboardHistoryKind.image;

  int get byteLength => data.length;

  /// Decoded text, or `null` for an image.
  ///
  /// `allowMalformed` because this is display data: a mangled character in a
  /// preview is better than an exception that takes the whole list down.
  String? get text => isImage ? null : utf8.decode(data, allowMalformed: true);

  /// A single line suitable for a list row.
  String preview({int maxCharacters = 120}) {
    if (isImage) return 'Image · ${_formatBytes(byteLength)}';
    final collapsed = text!.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return '(blank)';
    if (collapsed.length <= maxCharacters) return collapsed;
    return '${collapsed.substring(0, maxCharacters)}…';
  }

  ClipboardHistoryEntry copyWith({bool? pinned}) => ClipboardHistoryEntry(
        id: id,
        kind: kind,
        data: data,
        contentHash: contentHash,
        copiedAt: copiedAt,
        pinned: pinned ?? this.pinned,
      );

  /// Builds an entry, deriving [id] from the content hash and timestamp.
  factory ClipboardHistoryEntry.create({
    required ClipboardHistoryKind kind,
    required Uint8List data,
    required Uint8List contentHash,
    required DateTime copiedAt,
    bool pinned = false,
  }) =>
      ClipboardHistoryEntry(
        id: '${copiedAt.microsecondsSinceEpoch.toRadixString(16)}'
            '-${_hex(contentHash, 6)}',
        kind: kind,
        data: data,
        contentHash: contentHash,
        copiedAt: copiedAt,
        pinned: pinned,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.storageKey,
        'data': base64Encode(data),
        'hash': base64Encode(contentHash),
        'copiedAt': copiedAt.toUtc().toIso8601String(),
        'pinned': pinned,
      };

  /// Rebuilds an entry, or returns `null` when the record is unusable.
  ///
  /// Tolerant by design. This parses a file the app wrote itself, but a file is
  /// a file: it can be truncated by a crash mid-write, restored from an older
  /// version, or edited by anything running as the user. One bad row must cost
  /// one row, not the whole history — and never an exception on launch.
  static ClipboardHistoryEntry? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;

    final kind = ClipboardHistoryKind.fromStorageKey(json['kind'] as String?);
    if (kind == null) return null;

    final id = json['id'];
    if (id is! String || id.isEmpty) return null;

    final Uint8List data;
    final Uint8List hash;
    try {
      data = base64Decode(json['data'] as String? ?? '');
      hash = base64Decode(json['hash'] as String? ?? '');
    } on FormatException {
      return null;
    }
    if (data.isEmpty || hash.isEmpty) return null;

    final copiedAt = DateTime.tryParse(json['copiedAt'] as String? ?? '');
    if (copiedAt == null) return null;

    return ClipboardHistoryEntry(
      id: id,
      kind: kind,
      data: data,
      contentHash: hash,
      copiedAt: copiedAt,
      pinned: json['pinned'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipboardHistoryEntry &&
          other.id == id &&
          other.pinned == pinned &&
          other.kind == kind;

  @override
  int get hashCode => Object.hash(id, pinned, kind);
}

/// Entries plus whether they are being written anywhere.
///
/// The two travel together because the UI has to say which it is. "Nothing here
/// yet" means something very different depending on whether the list is
/// memory-only, and a user deciding whether to copy a password needs to know
/// which one they are looking at.
@immutable
final class ClipboardHistorySnapshot {
  const ClipboardHistorySnapshot({
    required this.entries,
    required this.isPersistent,
  });

  static const ClipboardHistorySnapshot empty = ClipboardHistorySnapshot(
    entries: <ClipboardHistoryEntry>[],
    isPersistent: false,
  );

  /// Newest first, pinned entries interleaved by recency rather than hoisted.
  final List<ClipboardHistoryEntry> entries;

  final bool isPersistent;

  int get pinnedCount => entries.where((entry) => entry.pinned).length;
}

/// Where a persistent history is written.
///
/// Deliberately a string in and a string out. The implementations live in the
/// apps because that is where the encryption key comes from — the platform
/// keystore on a phone, an owner-only key file on a desktop — and neither is
/// reachable from here: `rl_core` sits beneath `rl_crypto` and must stay free
/// of Flutter and `dart:io` both.
///
/// The contract every implementation owes: **what reaches storage is
/// ciphertext**. [ClipboardHistory] hands over plaintext JSON and has no way to
/// check what happens to it, so an implementation that writes it as-is silently
/// turns a convenience feature into a plaintext archive of everything the user
/// has copied.
abstract interface class ClipboardHistoryStore {
  /// The stored document, or `null` when nothing has been written.
  ///
  /// `null` is also the right answer for an unreadable store — a lost key, a
  /// corrupt file — because the alternative is refusing to launch over a
  /// convenience feature.
  Future<String?> read();

  Future<void> write(String document);

  /// Removes everything this store wrote, key material included.
  Future<void> destroy();
}

/// A bounded, newest-first list of recently copied items.
///
/// ## The rule that outranks the feature
///
/// **Concealed content is never recorded.** A password manager marking its
/// pasteboard entry confidential (`org.nspasteboard.ConcealedType` on macOS,
/// `ExcludeClipboardContentFromMonitorProcessing` on Windows) is asking, in the
/// only vocabulary the platform gives it, for that value not to be retained.
/// The sync path already honours it; a history that did not would be strictly
/// worse than no history, because it would take the one clipboard entry the
/// user most wants forgotten and write it into a list — and, with persistence
/// on, to disk.
///
/// That is why [record] takes `isConcealed` as a *required* argument rather
/// than reading a flag off some ambient state, and why it re-checks rather than
/// trusting the caller to have checked. A caller cannot reach the recording
/// path without answering the question, which is the only form of the guard
/// that survives someone refactoring the call site a year from now.
///
/// ## Eviction and pinning
///
/// The ring holds [kClipboardHistoryCapacity] entries and evicts the oldest
/// *unpinned* one to make room. See [kMaxPinnedClipboardEntries] for why the
/// pin count is capped one below the capacity.
final class ClipboardHistory {
  ClipboardHistory({
    Clock? clock,
    int capacity = kClipboardHistoryCapacity,
    int maxPinned = kMaxPinnedClipboardEntries,
  })  : _clock = clock ?? SystemClock(),
        _capacity = capacity,
        _maxPinned = maxPinned < capacity ? maxPinned : capacity - 1;

  final Clock _clock;
  final int _capacity;
  final int _maxPinned;

  final Log _log = Log.scoped('clipboard.history');
  final List<ClipboardHistoryEntry> _entries = <ClipboardHistoryEntry>[];
  final StreamController<ClipboardHistorySnapshot> _changes =
      StreamController<ClipboardHistorySnapshot>.broadcast();

  ClipboardHistoryStore? _store;

  /// Serialises writes so two rapid copies cannot interleave into a torn file.
  Future<void> _writes = Future<void>.value();

  bool _disposed = false;

  /// Newest first.
  List<ClipboardHistoryEntry> get entries =>
      List<ClipboardHistoryEntry>.unmodifiable(_entries);

  /// Whether entries are being written to a store.
  bool get isPersistent => _store != null;

  int get pinnedCount => _entries.where((entry) => entry.pinned).length;

  /// Whether another entry can be pinned right now.
  bool get canPinMore => pinnedCount < _maxPinned;

  int get maxPinned => _maxPinned;

  ClipboardHistorySnapshot get snapshot => ClipboardHistorySnapshot(
        entries: entries,
        isPersistent: isPersistent,
      );

  Stream<ClipboardHistorySnapshot> get changes => _changes.stream;

  /// Adds [data] to the history, unless it must not be remembered.
  ///
  /// Returns the recorded entry, or `null` when nothing was recorded — which is
  /// the answer for concealed content, for empty content, and for a repeat of
  /// something already held (that one is moved to the top instead of
  /// duplicated, so copying the same snippet twice does not fill the ring with
  /// one snippet).
  ClipboardHistoryEntry? record({
    required ClipboardHistoryKind kind,
    required Uint8List data,
    required Uint8List contentHash,
    required bool isConcealed,
  }) {
    if (isConcealed) {
      // Not logged at info, and the content is not logged at all: a debug line
      // naming what was withheld would defeat the point of withholding it.
      _log.debug(() => 'concealed clipboard content was not recorded');
      return null;
    }
    if (_disposed || data.isEmpty || contentHash.isEmpty) return null;

    final existing = _indexOfHash(contentHash);
    final wasPinned = existing == -1 ? false : _entries[existing].pinned;
    if (existing != -1) _entries.removeAt(existing);

    final entry = ClipboardHistoryEntry.create(
      kind: kind,
      data: data,
      contentHash: contentHash,
      copiedAt: _clock.now(),
      pinned: wasPinned,
    );

    _entries.insert(0, entry);
    _evict();
    _publish();
    return entry;
  }

  /// Pins or unpins an entry. Returns `false` when the pin limit is reached.
  bool setPinned(String id, {required bool pinned}) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index == -1) return false;

    final entry = _entries[index];
    if (entry.pinned == pinned) return true;
    if (pinned && !canPinMore) {
      _log.debug(() => 'pin refused: already holding $_maxPinned pinned items');
      return false;
    }

    _entries[index] = entry.copyWith(pinned: pinned);
    _publish();
    return true;
  }

  /// Forgets one entry, pinned or not.
  bool remove(String id) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index == -1) return false;
    _entries.removeAt(index);
    _publish();
    return true;
  }

  /// Forgets everything, pinned entries included.
  ///
  /// "Clear all" is the control a user reaches for after copying something they
  /// regret, so it must not leave a pinned row behind on a technicality.
  void clear() {
    if (_entries.isEmpty) {
      _publish();
      return;
    }
    _entries.clear();
    _publish();
  }

  /// Hydrates from [store] if it holds anything, and keeps writing to it.
  ///
  /// Returns whether persistence was in fact on. A store with nothing in it is
  /// how "the user never opted in" is represented — there is no separate
  /// preference flag to disagree with the data, and "off" means there is
  /// nothing on disk to find rather than a file with a `false` in it.
  Future<bool> restore(ClipboardHistoryStore store) async {
    final document = await store.read();
    if (document == null) return false;

    _store = store;
    _replaceFrom(document);
    _emit();
    return true;
  }

  /// Turns persistence on, writing the current contents through [store].
  Future<void> enablePersistence(ClipboardHistoryStore store) async {
    _store = store;
    await _write();
  }

  /// Turns persistence off and destroys what was written.
  ///
  /// The in-memory list is kept: the user asked to stop persisting, not to
  /// forget what they copied a minute ago. [clear] is the control for that.
  Future<void> disablePersistence() async {
    final store = _store;
    _store = null;
    await store?.destroy();
    _emit();
  }

  int _indexOfHash(Uint8List hash) {
    // A plain byte comparison, deliberately not the constant-time one. Both
    // operands are locally produced fingerprints of content this process
    // already holds in full; there is no secret here for a timing difference to
    // leak, and anything positioned to measure it can read the list directly.
    return _entries.indexWhere((entry) => _bytesEqual(entry.contentHash, hash));
  }

  void _evict() {
    while (_entries.length > _capacity) {
      final victim = _entries.lastIndexWhere((entry) => !entry.pinned);
      if (victim == -1) {
        // Unreachable while _maxPinned < _capacity, which the constructor
        // enforces. Bail rather than loop forever if that ever stops holding.
        _log.warn('clipboard history is entirely pinned; cannot evict');
        return;
      }
      _entries.removeAt(victim);
    }
  }

  void _replaceFrom(String document) {
    final restored = <ClipboardHistoryEntry>[];
    try {
      final decoded = jsonDecode(document);
      if (decoded is Map<String, Object?>) {
        final rows = decoded['entries'];
        if (rows is List) {
          for (final row in rows) {
            final entry = ClipboardHistoryEntry.tryFromJson(row);
            if (entry != null) restored.add(entry);
          }
        }
      }
    } on FormatException catch (error) {
      _log.warn(
        'stored clipboard history could not be parsed; starting empty',
        fields: <String, Object?>{'error': error.message},
      );
      return;
    }

    restored.sort((a, b) => b.copiedAt.compareTo(a.copiedAt));
    _entries
      ..clear()
      ..addAll(restored);

    // A file can hold more than the ring allows — the capacity may have been
    // lowered, or the file tampered with. Trim on the way in rather than
    // trusting it.
    _evict();
    while (_entries.length > _capacity) {
      _entries.removeLast();
    }
  }

  String _encode() => jsonEncode(<String, Object?>{
        'version': 1,
        'entries': <Map<String, Object?>>[
          for (final entry in _entries) entry.toJson(),
        ],
      });

  void _publish() {
    _emit();
    if (_store == null) return;
    _writes = _writes.then((_) => _write());
  }

  Future<void> _write() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.write(_encode());
    } on Object catch (error) {
      // A history that cannot be written is a degraded convenience, not a
      // reason to take the app down mid-copy.
      _log.warn(
        'could not persist the clipboard history',
        fields: <String, Object?>{'error': error.toString()},
      );
    }
  }

  void _emit() {
    if (_disposed || _changes.isClosed) return;
    _changes.add(snapshot);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _writes;
    await _changes.close();
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _hex(List<int> bytes, int count) {
  final buffer = StringBuffer();
  for (var i = 0; i < count && i < bytes.length; i++) {
    buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
