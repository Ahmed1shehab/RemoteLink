import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/brand.dart';

void main() {
  group('the name', () {
    test('is spelled with a space, everywhere it is user-visible', () {
      expect(kProductName, 'Remote Link');
    });

    test('does not appear in its old spelling in anything the user reads', () {
      // Identifiers keep the old spelling deliberately — class names, the
      // bundle identifier, and the `RemoteLink` data directory, which cannot be
      // renamed without orphaning every existing installation's identity key
      // and trust store. String literals are the part the user sees.
      final offenders = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          if (!line.contains('RemoteLink')) continue;
          // The storage path, and Dart identifiers, which never sit directly
          // against a quote or a space in a sentence.
          if (line.contains(r'${base.path}/RemoteLink')) continue;
          if (RegExp(r'RemoteLink[A-Za-z]').hasMatch(line)) continue;
          offenders.add('${file.path}: ${line.trim()}');
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('the version', () {
    test('matches the one in pubspec.yaml', () {
      // The whole reason a constant is affordable instead of a plugin: the
      // drift the plugin was insuring against is caught here for free.
      final declared = File('pubspec.yaml')
          .readAsLinesSync()
          .firstWhere((line) => line.startsWith('version:'))
          .split(':')
          .last
          .trim();
      expect(kAppVersion, declared);
    });
  });

  group('the artwork', () {
    testWidgets('is bundled and renders at the size asked for', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BrandMark(size: 48))),
      );
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, kLogoAsset);
      expect(tester.getSize(find.byType(Image)), const Size(48, 48));
    });

    testWidgets('the splash names the product rather than only spinning',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BrandSplash())),
      );
      // Pumped once rather than settled: the progress bar never stops, which
      // is the point of it.
      await tester.pump();

      expect(find.text(kProductName), findsOneWidget);
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('the splash says what it is waiting for', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BrandSplash(message: 'Reticulating splines')),
        ),
      );
      await tester.pump();

      expect(find.text('Reticulating splines'), findsOneWidget);
    });
  });

  group('the icons the generator writes', () {
    test('exist for every size the asset catalogue names', () {
      // The catalogue is what Xcode reads; a missing file is a build failure
      // on a machine that is not this one, which is the worst place to find it.
      const directory =
          'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final size in <int>[16, 32, 64, 128, 256, 512, 1024]) {
        final file = File('$directory/app_icon_$size.png');
        expect(file.existsSync(), isTrue, reason: file.path);
        expect(file.lengthSync(), greaterThan(256), reason: file.path);
      }
    });

    test('the menu bar icon is a mask rather than a filled rectangle', () {
      // macOS ignores a template image's colours and paints its alpha. The
      // placeholder that shipped was 203 bytes of opaque white, so the item was
      // there and invisible — and the menu is the only way to quit.
      final icon = File('assets/tray/icon.png');
      expect(icon.existsSync(), isTrue);
      expect(
        icon.lengthSync(),
        greaterThan(400),
        reason: 'a blank placeholder is a few hundred bytes',
      );
    });
  });
}
