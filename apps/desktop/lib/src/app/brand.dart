import 'package:flutter/material.dart';

/// The product's name, spelled one way, in one place.
///
/// It was previously typed out at each of the dozen places it appears — the
/// window title, the menu bar, three menu items, the sidebar, the local-network
/// prompt — which is how a rename turns into a hunt and how two spellings end up
/// shipping side by side.
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

/// What the window shows before the service has finished starting.
///
/// Starting takes as long as it takes to read the identity key, open the
/// listening socket and register with Bonjour. A bare spinner for that time says
/// only that something is happening; the mark and a line of text say which
/// program is running and what it is waiting for, which is the difference
/// between a slow launch and an app that looks broken.
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
              message ?? 'Starting the service…',
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
