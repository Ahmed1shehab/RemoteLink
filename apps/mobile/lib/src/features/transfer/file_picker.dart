import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

/// One file the user chose, together with the name they know it by.
///
/// The two are carried separately because they routinely disagree. Android's
/// Storage Access Framework and the system photo picker both hand back a copy
/// in the app's cache directory, named something like
/// `image_picker_A1B2C3.jpg` regardless of what the user sees in their gallery.
/// Deriving the transfer's filename from the path — which is what the code here
/// used to do — means the desktop receives a file the sender cannot recognise.
@immutable
final class PickedFile {
  const PickedFile({required this.file, required this.displayName});

  final File file;

  /// What to call this file on the wire. Still passed through
  /// `sanitiseFileName` before it is sent: the picker's name comes from the
  /// filesystem or a content provider, and neither is a trusted source.
  final String displayName;

  @override
  String toString() => 'PickedFile($displayName, ${file.path})';
}

/// Opens the host's file and photo pickers.
///
/// An interface rather than direct plugin calls, because a widget test cannot
/// open a system picker: there is no Dart-side implementation to fall back on,
/// so the platform channel throws `MissingPluginException` and every test that
/// touches the send flow fails. The fake in `test/support` is what makes the
/// selection path testable at all.
abstract interface class TransferFilePicker {
  /// Any file. Returns an empty list when the user cancels.
  Future<List<PickedFile>> pickFiles();

  /// Photos and videos, through the system media picker.
  Future<List<PickedFile>> pickMedia();
}

/// The real picker, backed by the platform's own dialogs.
final class SystemTransferFilePicker implements TransferFilePicker {
  SystemTransferFilePicker({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;
  final Log _log = Log.scoped('mobile.picker');

  @override
  Future<List<PickedFile>> pickFiles() async {
    // No `acceptedTypeGroups`: this is the "send anything" path, and an empty
    // group list is how file_selector spells "no filter". Naming a group with
    // no extensions in it is rejected at runtime on iOS rather than ignored.
    final selected = await openFiles();
    _log.debug(() => 'picked ${selected.length} file(s)');
    return _toPickedFiles(selected);
  }

  @override
  Future<List<PickedFile>> pickMedia() async {
    final selected = await _imagePicker.pickMultipleMedia();
    _log.debug(() => 'picked ${selected.length} media item(s)');
    return _toPickedFiles(selected);
  }

  List<PickedFile> _toPickedFiles(List<XFile> selected) {
    final picked = <PickedFile>[];
    for (final xFile in selected) {
      final file = File(xFile.path);
      // A picker can hand back a path that no longer resolves — a content URI
      // whose provider has already released it, or a cache entry evicted
      // between selection and send. Dropping it here is better than offering
      // the peer a file whose length we cannot read.
      if (!file.existsSync()) {
        _log.warn(
          'picked file no longer exists',
          fields: <String, Object?>{'name': xFile.name},
        );
        continue;
      }
      picked.add(PickedFile(file: file, displayName: xFile.name));
    }
    return picked;
  }
}
