import 'dart:io';

import 'package:brand/brand.dart';

/// Prints the artwork's own background colour, for the launch screens to match.
///
/// Sampled rather than eyeballed so the native splash and the Flutter splash
/// are the same colour: a launch screen one shade off flashes at handover, and
/// a hand-picked hex is exactly how that happens.
void main() {
  final logo = decodePng(File('assets/brand/logo.png').readAsBytesSync());
  // Well inside the tile and well above the mark, which is centred. Averaging
  // the middle instead would mix in the white strokes and report a grey the
  // artwork does not contain anywhere.
  final (r, g, b, _) = logo.pixelAt(logo.width ~/ 2, logo.height ~/ 8);
  stdout.writeln('#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}  rgb($r, $g, $b)');
}
