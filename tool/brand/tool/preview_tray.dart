import 'dart:io';

import 'package:brand/brand.dart';

/// Prints the menu-bar icon as text, so its shape can be checked without a Mac.
///
/// A template image is pure alpha: every viewer that renders it over white
/// shows nothing at all, which makes "did the mask come out right" impossible
/// to answer by looking at the file. This answers it.
void main(List<String> arguments) {
  final path = arguments.isEmpty ? 'apps/desktop/assets/tray/icon.png' : arguments.first;
  final icon = decodePng(File(path).readAsBytesSync());
  final buffer = StringBuffer();
  for (var y = 0; y < icon.height; y++) {
    for (var x = 0; x < icon.width; x++) {
      final alpha = icon.pixelAt(x, y).$4;
      buffer.write(switch (alpha) {
        > 170 => '#',
        > 85 => '+',
        > 25 => '.',
        _ => ' ',
      });
    }
    buffer.writeln();
  }
  stdout.write(buffer);
}
