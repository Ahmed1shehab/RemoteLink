import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/brand.dart';

void main() {
  group('the name', () {
    test('is spelled with a space', () {
      expect(kProductName, 'Remote Link');
    });

    test('does not appear in its old spelling in anything the user reads', () {
      // Identifiers keep the old spelling deliberately — `RemoteLinkClient`,
      // `RemoteLinkApp`, and the `RemoteLink` storage directory, which cannot be
      // renamed without orphaning the trust store on every phone that already
      // has one.
      final offenders = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          if (!line.contains('RemoteLink')) continue;
          if (line.contains(r'${base.path}/RemoteLink')) continue;
          if (RegExp(r'RemoteLink[A-Za-z]').hasMatch(line)) continue;
          offenders.add('${file.path}: ${line.trim()}');
        }
      }
      expect(offenders, isEmpty);
    });
  });

  test('the version matches pubspec.yaml', () {
    final declared = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((line) => line.startsWith('version:'))
        .split(':')
        .last
        .trim();
    expect(kAppVersion, declared);
  });

  testWidgets('the mark is bundled and sized as asked', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrandMark(size: 28))),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, kLogoAsset);
    expect(tester.getSize(find.byType(Image)), const Size(28, 28));
  });

  group('the launch screen', () {
    test('shows the mark rather than a blank page', () {
      // The first frame on a cold start, drawn by the OS before the engine has
      // started. The template ships a plain white rectangle, which on a
      // mid-range phone is a second of looking like nothing happened.
      for (final path in <String>[
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        final xml = File(path).readAsStringSync();
        expect(xml, contains('@mipmap/launch_image'), reason: path);
        expect(
          xml,
          isNot(contains('<!-- <item>')),
          reason: '$path still has the template bitmap commented out',
        );
      }
    });

    test('the images it names exist at every density', () {
      for (final density in <String>[
        'mdpi',
        'hdpi',
        'xhdpi',
        'xxhdpi',
        'xxxhdpi',
      ]) {
        final launch = File(
          'android/app/src/main/res/mipmap-$density/launch_image.png',
        );
        final icon = File(
          'android/app/src/main/res/mipmap-$density/ic_launcher.png',
        );
        expect(launch.existsSync(), isTrue, reason: launch.path);
        expect(icon.existsSync(), isTrue, reason: icon.path);
      }
    });
  });

  group('the launcher', () {
    test('Android shows the product name', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:label="Remote Link"'));
    });

    test('iOS shows the product name', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final display = plist.indexOf('CFBundleDisplayName');
      expect(display, greaterThan(-1));
      expect(
        plist.substring(display, display + 120),
        contains('<string>Remote Link</string>'),
      );
    });
  });
}
