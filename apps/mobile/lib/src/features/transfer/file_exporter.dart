import 'dart:io';

import 'package:gal/gal.dart';
import 'package:rl_core/rl_core.dart';
import 'package:share_plus/share_plus.dart';

/// Why an export did not happen.
enum ExportFailure {
  /// The user dismissed the share sheet without picking anything.
  cancelled,

  /// The photo library refused, and only the user can change that.
  permissionDenied,

  /// Anything else — a full disk, a library that rejected the format.
  failed,
}

/// An export that did not put the file anywhere.
final class ExportError implements Exception {
  const ExportError(this.reason, {this.cause});

  final ExportFailure reason;
  final Object? cause;

  /// What to show the user. Written to be read on a phone, mid-transfer.
  String get message => switch (reason) {
        ExportFailure.cancelled => 'Not saved — you closed the share sheet.',
        ExportFailure.permissionDenied =>
          'Remote Link cannot add to your photo library. Allow it under '
              'Settings › Remote Link › Photos, then send it again.',
        ExportFailure.failed => 'Could not save this file to your phone.',
      };

  @override
  String toString() => 'ExportError(${reason.name}): $message';
}

/// Hands a finished file to the phone, and keeps nothing.
///
/// This app stores nothing of its own. A received file lands in a cache
/// directory only for as long as it takes to assemble and verify it — bytes
/// have to go somewhere before a hash can be checked over them — and then it
/// leaves through here, into somewhere the phone's own apps can see. Whether it
/// worked or not, nothing is left behind: [MobileTransferStore] deletes the
/// staged copy either way.
///
/// The split is by file type rather than by asking, because the two
/// destinations are not interchangeable. The photo library cannot hold a PDF,
/// and a photo filed into a folder is a photo missing from the camera roll —
/// which is where the person who just sent it will look for it.
abstract interface class IncomingFileExporter {
  /// Puts [file] somewhere the user can find it.
  ///
  /// Throws [ExportError] when it could not, so the transfer can be reported
  /// as failed rather than silently succeeding into a file nobody has.
  Future<void> export(File file, {required String mimeType});
}

/// The real one: the photo library for media, the share sheet for the rest.
final class SystemFileExporter implements IncomingFileExporter {
  const SystemFileExporter();

  static final Log _log = Log.scoped('mobile.transfer.export');

  @override
  Future<void> export(File file, {required String mimeType}) async {
    if (_isImage(mimeType) || _isVideo(mimeType)) {
      await _saveToPhotos(file, isVideo: _isVideo(mimeType));
      return;
    }
    await _offerToShare(file);
  }

  Future<void> _saveToPhotos(File file, {required bool isVideo}) async {
    // `toAlbum: false` asks for the narrower grant. Writing to the camera roll
    // needs add-only access, which iOS can give without handing this app the
    // ability to read a single existing photo — and this app has no reason to
    // read any.
    if (!await Gal.hasAccess()) {
      if (!await Gal.requestAccess()) {
        throw const ExportError(ExportFailure.permissionDenied);
      }
    }

    try {
      if (isVideo) {
        await Gal.putVideo(file.path);
      } else {
        await Gal.putImage(file.path);
      }
    } on GalException catch (error) {
      _log.warn('the photo library refused a file', error: error);
      throw ExportError(
        error.type == GalExceptionType.accessDenied
            ? ExportFailure.permissionDenied
            : ExportFailure.failed,
        cause: error,
      );
    }
  }

  Future<void> _offerToShare(File file) async {
    final result = await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(file.path)]),
    );

    // Treated as a failure on purpose. The staged copy is about to be deleted,
    // so a dismissed sheet means the file is gone — and a transfer row that
    // says "completed" over a file the user does not have is worse than one
    // that says it was not saved.
    if (result.status == ShareResultStatus.dismissed) {
      throw const ExportError(ExportFailure.cancelled);
    }
  }

  static bool _isImage(String mimeType) => mimeType.startsWith('image/');

  static bool _isVideo(String mimeType) => mimeType.startsWith('video/');
}
