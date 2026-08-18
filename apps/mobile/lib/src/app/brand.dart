import 'package:flutter/material.dart';

/// The product's name, spelled one way, in one place.
///
/// It was previously typed out at each of the places it appears — the app
/// title, the settings header, the pairing prompts — which is how a rename turns
/// into a hunt and how two spellings end up shipping side by side.
const String kProductName = 'Remote Link';

/// The version shown in Settings.
///
/// A constant rather than `package_info_plus`, which is a plugin, a platform
/// channel and a `MissingPluginException` risk in exchange for a string that is
/// known at compile time. It can drift from `pubspec.yaml`, so a test asserts
/// the two agree — which is the cheap half of what the plugin was buying.
const String kAppVersion = '1.0.0';

/// Where the artwork lives in the bundle.
const String kLogoAsset = 'assets/brand/logo.png';

/// The logo, at whatever size it is asked for.
///
/// No clip here. The corners are cut in the asset itself by the icon generator,
/// because the same file is the Dock icon and the taskbar icon, and neither of
/// those passes through a widget that could round them. Rounding it twice — once
/// in the pixels, once in a `ClipRRect` — only produces a slightly different
/// curve fighting the artwork's own.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        kLogoAsset,
        width: size,
        height: size,
        // The artwork is square, so this only guards against a future export
        // with a different aspect ratio quietly stretching.
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: kProductName,
      );
}
