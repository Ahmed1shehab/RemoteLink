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
const String kAppVersion = '0.1.0';

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

/// What the phone shows before it has found anything to talk to.
///
/// The native launch screen shows the same mark, so this one continues it
/// rather than replacing it: the engine hands over mid-animation and the user
/// sees one screen settling instead of two screens swapping.
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const BrandMark(size: 96),
            const SizedBox(height: 20),
            Text(
              kProductName,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? 'Looking for your computer…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 132,
              child: LinearProgressIndicator(
                borderRadius: BorderRadius.circular(4),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
