import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/app_icons.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/devices/device_list_screen.dart';
import 'package:remotelink_mobile/src/features/input/touchpad_screen.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';
import 'support/l10n.dart';

void main() {
  group('Mobile RTL and Localisation (Arabic)', () {
    testWidgets(
        'TouchpadScreen root is RTL while physical touchpad and buttons remain LTR',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith(
              (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
            ),
            clientStateProvider.overrideWith(
              (ref) => Stream<ClientState>.value(ClientState.connected),
            ),
          ],
          child: wrapWithMobileLocalization(
            locale: const Locale('ar'),
            child: const Scaffold(
              body: TouchpadSurfaceView(immersive: false),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Root screen directionality is RTL under Arabic locale
      final screenDirectionality =
          Directionality.of(tester.element(find.byType(TouchpadSurfaceView)));
      expect(screenDirectionality, TextDirection.rtl);

      // Verify that the gesture area / buttons row are explicitly kept LTR so cursor
      // movement and physical button placement are not mirrored.
      final ltrWidgets = tester
          .widgetList<Directionality>(find.byType(Directionality))
          .where((d) => d.textDirection == TextDirection.ltr)
          .toList();
      expect(
        ltrWidgets.length,
        greaterThanOrEqualTo(2),
        reason:
            'Touchpad surface and button row must be wrapped in LTR Directionality',
      );
    });

    testWidgets(
        'DeviceListScreen renders in RTL and displays Arabic translations',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileDeviceListOverrides(discoveryOperational: true),
          child: wrapWithMobileLocalization(
            locale: const Locale('ar'),
            child: const DeviceListScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        Directionality.of(tester.element(find.byType(DeviceListScreen))),
        TextDirection.rtl,
      );

      // Arabic translations for key strings appear
      expect(find.text('الأجهزة'), findsOneWidget);
      expect(find.text('جارٍ البحث عن أجهزة كمبيوتر'), findsOneWidget);
      expect(find.text('مسح الرمز'), findsOneWidget);
    });

    testWidgets(
        'Directional padding and alignments resolve start to right in RTL',
        (tester) async {
      const padding = EdgeInsetsDirectional.only(start: 20, end: 8);
      final resolved = padding.resolve(TextDirection.rtl);
      expect(resolved.right, 20);
      expect(resolved.left, 8);

      const alignment = AlignmentDirectional.centerStart;
      expect(alignment.resolve(TextDirection.rtl), Alignment.centerRight);
    });

    testWidgets(
        'Directional icons have matchTextDirection true, non-directional false',
        (tester) async {
      const chevron = AppIcon(AppIcons.materialChevronRight);
      expect(chevron.data.matchTextDirection, isTrue);

      const keyboard = AppIcon(AppIcons.keyboard);
      expect(keyboard.data.matchTextDirection, isFalse);

      const settings = AppIcon(AppIcons.settings);
      expect(settings.data.matchTextDirection, isFalse);
    });
  });
}
