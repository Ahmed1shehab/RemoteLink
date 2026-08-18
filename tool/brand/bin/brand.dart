import 'dart:io';

import 'package:brand/brand.dart';

/// Regenerates every icon in the repository from `assets/brand/logo.png`.
///
/// Run from anywhere in the checkout:
///
/// ```
/// dart run tool/brand/bin/brand.dart
/// ```
///
/// ## Why a generator rather than a folder of finished files
///
/// There are more than forty icon files across four platforms, at sizes from 16
/// pixels to 1024, in three different container formats. Cut by hand once, they
/// are correct once: the next time the artwork changes somebody exports the
/// obvious dozen, misses the iPad 83.5pt slot and the Windows `.ico`, and the
/// app ships wearing two logos. Which is the state this repository was already
/// in — every icon here was still the Flutter demo mark.
///
/// The rules that are easy to get wrong live in code with a reason attached:
/// iOS and Android get a full-bleed crop because they mask their own corners,
/// macOS keeps the tile's own shape because it does not, and the menu bar gets
/// an alpha mask because a template image ignores colour entirely.
void main(List<String> arguments) {
  final root = _repositoryRoot();
  final masterFile = File('${root.path}/assets/brand/logo.png');
  if (!masterFile.existsSync()) {
    stderr.writeln('no master artwork at ${masterFile.path}');
    exitCode = 1;
    return;
  }

  final master = decodePng(masterFile.readAsBytesSync());
  stdout.writeln('master ${master.width}x${master.height}');

  // The tile itself, cut off the white page it was exported on and with its
  // corners cut in the pixels. Everything that draws the mark over a background
  // of its own uses this — a white rectangle round the tile reads as a sticker
  // stuck to the window rather than as the app's icon.
  final tile = master.croppedToContent().withRoundedCorners();

  // Square, opaque, no corners at all. iOS and Android mask their own, and a
  // rounded tile handed to them is rounded twice; iOS also composites any
  // transparency over black, so the page margin would come back as a black one.
  final fullBleed = master.croppedToCentre(0.74);
  final written = <String>[];

  void write(String path, List<int> bytes) {
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    written.add(path);
  }

  void writePng(String path, Raster image, int size) =>
      write(path, encodePng(image.resized(size, size)));

  // ---- Bundled in-app artwork -------------------------------------------
  //
  // Flutter's own resolution suffixes, so a 6.7-inch phone and a Retina desk
  // get the pixels they can show and nothing larger.
  for (final app in <String>['apps/desktop', 'apps/mobile']) {
    writePng('$app/assets/brand/logo.png', tile, 256);
    writePng('$app/assets/brand/2.0x/logo.png', tile, 512);
    writePng('$app/assets/brand/3.0x/logo.png', tile, 768);
  }

  // ---- macOS ------------------------------------------------------------
  //
  // macOS applies no mask, so the icon carries its own shape — and its own
  // margin, because the Dock reserves that space for magnification and the
  // shadow it draws. Four fifths of the canvas is where Apple's own icons sit.
  final macIcon = tile.centredOnSquare(0.82);
  for (final size in <int>[16, 32, 64, 128, 256, 512, 1024]) {
    writePng(
      'apps/desktop/macos/Runner/Assets.xcassets/AppIcon.appiconset/'
      'app_icon_$size.png',
      macIcon,
      size,
    );
  }

  // ---- iOS --------------------------------------------------------------
  //
  // Full-bleed and opaque. A home-screen icon with transparency is rendered
  // over black by iOS, which is how a white page margin becomes a black one.
  const iosIcons = <String, int>{
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  iosIcons.forEach((name, size) {
    writePng(
      'apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/$name',
      fullBleed,
      size,
    );
  });

  // ---- Android ----------------------------------------------------------
  const androidIcons = <String, int>{
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  androidIcons.forEach((density, size) {
    writePng(
      'apps/mobile/android/app/src/main/res/mipmap-$density/ic_launcher.png',
      fullBleed,
      size,
    );
  });

  // ---- Windows ----------------------------------------------------------
  //
  // Full canvas, unlike macOS: Windows lays icons out in a fixed cell and adds
  // no margin of its own, so one added here just makes the app look smaller
  // than everything pinned beside it.
  write(
    'apps/desktop/windows/runner/resources/app_icon.ico',
    encodeIco(<Raster>[
      for (final size in <int>[16, 24, 32, 48, 64, 128, 256])
        tile.resized(size, size),
    ]),
  );

  // ---- The menu bar and the notification area ---------------------------
  //
  // Two different things that happen to sit in the same corner of the screen.
  // macOS wants a shape it can paint black or white to match the bar, so it
  // gets the mark as an alpha mask; Windows draws the icon as supplied, so it
  // gets the artwork in colour.
  //
  // 36 pixels because tray_manager pins the image to 18 points, and 18 points
  // on every Mac sold this decade is 36 pixels.
  //
  // Cropped tighter than the launcher icons before either is made. A menu bar
  // is eighteen points tall, so the tile's own margin is margin the mark cannot
  // afford; and masking the uncropped artwork turns the white page *around* the
  // tile into the shape, which is a solid rectangle with a logo-shaped hole.
  final trayArtwork = master.croppedToCentre(0.62);

  write(
    'apps/desktop/assets/tray/icon.png',
    encodePng(trayArtwork.asTemplateMask().resized(36, 36)),
  );
  write(
    'apps/desktop/assets/tray/icon.ico',
    encodeIco(<Raster>[
      for (final size in <int>[16, 20, 24, 32]) trayArtwork.resized(size, size),
    ]),
  );

  // ---- Launch screens ---------------------------------------------------
  //
  // The first frame the user sees. Flutter shows these before the engine has
  // started, which on a cold start is most of the wait.
  const launchScales = <String, int>{
    'LaunchImage.png': 192,
    'LaunchImage@2x.png': 384,
    'LaunchImage@3x.png': 576,
  };
  launchScales.forEach((name, size) {
    writePng(
      'apps/mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset/$name',
      tile,
      size,
    );
  });
  androidIcons.forEach((density, _) {
    // Deliberately larger than the launcher icon: this one is centred on an
    // otherwise empty screen rather than sitting in a grid.
    writePng(
      'apps/mobile/android/app/src/main/res/mipmap-$density/launch_image.png',
      tile,
      androidIcons[density]! * 3,
    );
  });

  stdout.writeln('wrote ${written.length} files');
}

/// Walks up from this script until it finds the workspace root.
///
/// Found rather than assumed so the tool works from any directory, including
/// the one it lives in.
Directory _repositoryRoot() {
  var directory = File.fromUri(Platform.script).parent;
  while (true) {
    if (File('${directory.path}/melos.yaml').existsSync()) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('could not find the repository root from '
          '${Platform.script}');
    }
    directory = parent;
  }
}
