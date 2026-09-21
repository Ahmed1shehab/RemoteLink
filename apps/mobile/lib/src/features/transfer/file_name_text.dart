import 'package:flutter/material.dart';

/// Longest suffix still treated as an extension.
///
/// `.jpeg` and `.heic` are extensions; the tail of `report.final version` is
/// not. Without a cap, a name whose last dot is early would keep half of itself
/// pinned to the right and elide the part the user actually reads.
const int _kMaxExtensionLength = 8;

/// About what two lines of a phone-width row hold at the default text size.
///
/// An approximation on purpose. Measuring the box would mean a `LayoutBuilder`,
/// and this widget is used inside an `AlertDialog`, which Material lays out with
/// `IntrinsicWidth` — a layout callback cannot run there at all. Being a few
/// characters pessimistic on a wide screen costs an ellipsis nobody needed;
/// being unable to render in the incoming-transfer prompt costs the prompt.
const int _kNameBudget = 44;

/// Splits [fileName] into the part that may be shortened and the part that
/// must not be.
///
/// Returns an empty extension when there is nothing that looks like one, in
/// which case the name is elided like any other string.
({String stem, String extension}) splitFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) {
    return (stem: fileName, extension: '');
  }
  final extension = fileName.substring(dot);
  if (extension.length > _kMaxExtensionLength + 1 || extension.contains(' ')) {
    return (stem: fileName, extension: '');
  }
  return (stem: fileName.substring(0, dot), extension: extension);
}

/// [fileName] shortened from the middle, so that its extension survives.
///
/// Names shorter than [maxCharacters] are returned untouched — most are, and a
/// name nobody had to shorten should not look like one that was.
String elideFileName(String fileName, {int maxCharacters = _kNameBudget}) {
  // Characters, not code units: cutting mid-surrogate leaves a replacement
  // glyph, and emoji in file names are ordinary now.
  final characters = fileName.characters;
  if (characters.length <= maxCharacters) return fileName;

  final parts = splitFileName(fileName);
  final extension = parts.extension.characters;
  final keep = maxCharacters - extension.length - 1;
  // A name that is all extension has nothing to shorten; let the Text ellipsis
  // deal with it rather than returning a bare `…`.
  if (keep <= 0) return fileName;

  return '${parts.stem.characters.take(keep)}…${parts.extension}';
}

/// A file name that gives up its middle rather than its extension.
///
/// A phone row has room for about forty characters, and a camera roll is full
/// of names twice that. Plain `TextOverflow.ellipsis` answers by cutting the
/// tail, which is the one form that loses the part always worth reading:
/// `Screenshot_20260819-222940_edited.png` becomes `Screenshot_20260819-2…`
/// and a photo is no longer distinguishable from a PDF. Eliding the middle
/// keeps both ends — enough of the start to recognise the file, and the
/// extension whole.
class FileNameText extends StatelessWidget {
  const FileNameText(
    this.fileName, {
    this.style,
    this.maxLines = 2,
    super.key,
  });

  final String fileName;
  final TextStyle? style;

  /// Two by default: one line loses too much of a camera or screenshot name,
  /// and three starts pushing the size and progress bar out of view.
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
        elideFileName(fileName),
        style: style,
        maxLines: maxLines,
        // The backstop for the cases the character budget cannot know about:
        // a narrower row, a larger text scale, a wide script.
        overflow: TextOverflow.ellipsis,
      );
}
