import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';

import '../input_backend.dart';
import 'win32_ffi.dart';

/// Windows clipboard access.
///
/// ## Why polling beats notification here
///
/// Windows offers `AddClipboardFormatListener`, which posts
/// `WM_CLIPBOARDUPDATE` to a window. Using it would require creating a hidden
/// window and pumping a message loop on a dedicated thread — real complexity,
/// and awkward to reach from Dart at all.
///
/// `GetClipboardSequenceNumber` is the alternative: a single system call that
/// returns a counter incremented on every clipboard change. Reading it costs
/// well under a microsecond, so polling at 50 ms is roughly 20 calls a second
/// and immeasurable CPU — while comfortably meeting the sub-100 ms sync target.
/// The clipboard itself is only opened when the counter actually moved.
///
/// ## Opening the clipboard is a shared, contended resource
///
/// Only one process may hold the clipboard open at a time, and a badly written
/// application can hold it for hundreds of milliseconds. Every open here is
/// therefore retried briefly and released in a `finally` — leaking the handle
/// would wedge copy-and-paste system-wide until RemoteLink exited, which is
/// about the most user-hostile bug this component could have.
final class Win32ClipboardBackend implements ClipboardBackend {
  Win32ClipboardBackend() : _bindings = Win32Bindings() {
    final name = kExcludeFromMonitoring.toNativeUtf16();
    try {
      _excludeFormat = _bindings.registerClipboardFormat(name);
    } finally {
      calloc.free(name);
    }
  }

  static const int _openAttempts = 5;
  static const Duration _openRetryDelay = Duration(milliseconds: 2);

  final Win32Bindings _bindings;
  final Log _log = Log.scoped('native.clipboard.win32');

  late final int _excludeFormat;
  bool _disposed = false;

  @override
  bool get isAvailable => !_disposed;

  @override
  int get changeCount => _bindings.getClipboardSequenceNumber();

  @override
  bool get isConcealed =>
      _excludeFormat != 0 &&
      _bindings.isClipboardFormatAvailable(_excludeFormat) != 0;

  /// Runs [body] with the clipboard open, retrying briefly if another process
  /// holds it.
  T? _withClipboard<T>(T? Function() body) {
    for (var attempt = 0; attempt < _openAttempts; attempt++) {
      if (_bindings.openClipboard(0) != 0) {
        try {
          return body();
        } finally {
          _bindings.closeClipboard();
        }
      }
      // A busy-wait rather than an async delay: this whole API is synchronous
      // by design, and the contention window is single-digit milliseconds.
      final deadline = DateTime.now().add(_openRetryDelay);
      while (DateTime.now().isBefore(deadline)) {
        // Spin.
      }
    }
    _log.debug(() => 'clipboard busy after $_openAttempts attempts');
    return null;
  }

  @override
  String? readText() {
    if (_disposed) return null;
    if (_bindings.isClipboardFormatAvailable(CF_UNICODETEXT) == 0) return null;

    return _withClipboard<String?>(() {
      final handle = _bindings.getClipboardData(CF_UNICODETEXT);
      if (handle == 0) return null;

      final pointer = _bindings.globalLock(handle);
      if (pointer == nullptr) return null;
      try {
        return pointer.cast<Utf16>().toDartString();
      } finally {
        _bindings.globalUnlock(handle);
      }
    });
  }

  @override
  void writeText(String text) {
    if (_disposed) return;

    // UTF-16 plus a null terminator, which CF_UNICODETEXT requires.
    final units = text.codeUnits;
    final byteLength = (units.length + 1) * 2;

    final handle = _bindings.globalAlloc(GMEM_MOVEABLE, byteLength);
    if (handle == 0) {
      _log.warn('GlobalAlloc failed for a clipboard write');
      return;
    }

    final pointer = _bindings.globalLock(handle);
    if (pointer == nullptr) {
      _bindings.globalFree(handle);
      return;
    }

    final buffer = pointer.cast<Uint16>();
    for (var i = 0; i < units.length; i++) {
      buffer[i] = units[i];
    }
    buffer[units.length] = 0;
    _bindings.globalUnlock(handle);

    final placed = _withClipboard<bool>(() {
          _bindings.emptyClipboard();
          // On success the clipboard *takes ownership* of the handle, so it
          // must not be freed. On failure ownership stays here and it must be.
          // Getting this backwards is either a leak or a double free.
          return _bindings.setClipboardData(CF_UNICODETEXT, handle) != 0;
        }) ??
        false;

    if (!placed) _bindings.globalFree(handle);
  }

  @override
  List<int>? readImagePng() {
    // Windows stores clipboard images as CF_DIB, not PNG, so this needs a DIB
    // to PNG encoder. Deferred to the clipboard-image milestone rather than
    // shipping a half-conversion that mangles alpha and colour profiles.
    return null;
  }

  @override
  void writeImagePng(List<int> pngBytes) {
    // Symmetrically deferred: writing requires decoding the PNG to a DIB.
  }

  @override
  void dispose() => _disposed = true;
}
