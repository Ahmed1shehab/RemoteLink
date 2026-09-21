import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rl_core/rl_core.dart';

import 'file_name_text.dart';

/// Whether [fileName] names something this app can draw.
///
/// Decided from the name rather than the bytes because the picker hands over a
/// path, and reading a header off every file to find out would cost a disk
/// round trip per row in a list that scrolls. Getting it wrong costs a broken
/// thumbnail, which [ImageThumbnail] already handles.
bool isPreviewableImage(String fileName) {
  final mime = mimeTypeForFileName(fileName);
  if (!mime.startsWith('image/')) return false;
  // Flutter's decoder handles these; HEIC and SVG it does not, and the phone's
  // camera roll is full of the former.
  return const <String>{
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'image/bmp',
  }.contains(mime);
}

/// A small square preview of an image file, or [fallback] when it cannot be
/// drawn.
class ImageThumbnail extends StatelessWidget {
  const ImageThumbnail({
    required this.file,
    required this.fileName,
    required this.fallback,
    this.size = 40,
    super.key,
  });

  final File file;
  final String fileName;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!isPreviewableImage(fileName)) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decoded at the size it is drawn. A 12-megapixel photo decoded at full
        // size for a 40-pixel square is 48 MB of memory per row, which on a
        // list of picked photos is how an app gets killed.
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

/// Full-screen look at one image, zoomable, with its name.
///
/// Shown from the send list so the user can check they picked the right photo
/// before it leaves the phone — the thumbnails are 40 pixels across and four
/// screenshots from the same afternoon look identical at that size.
class ImagePreviewPage extends StatelessWidget {
  const ImagePreviewPage({
    required this.file,
    required this.fileName,
    super.key,
  });

  final File file;
  final String fileName;

  static Future<void> show(
    BuildContext context, {
    required File file,
    required String fileName,
  }) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (context) =>
              ImagePreviewPage(file: file, fileName: fileName),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: FileNameText(
          fileName,
          maxLines: 1,
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This image could not be opened.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
