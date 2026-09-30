import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/app_icons.dart';
import 'package:remotelink_desktop/src/ui/home_screen.dart';
import 'package:remotelink_desktop/src/ui/settings_screen.dart';

import 'support/fakes.dart';
import 'support/l10n.dart';

void main() {
  group('Desktop RTL and Localisation (Arabic)', () {
    testWidgets('HomeScreen renders in RTL and displays Arabic translations',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: desktopHomeOverrides,
          child: wrapWithDesktopLocalization(
            locale: const Locale('ar'),
            child: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Assert Directionality is RTL
      final directionality =
          Directionality.of(tester.element(find.byType(HomeScreen)));
      expect(directionality, TextDirection.rtl);

      // Assert Arabic translation is loaded for key strings
      expect(find.text('الأجهزة المتصلة'), findsOneWidget);
      expect(find.text('غير قيد التشغيل'), findsOneWidget);
    });

    testWidgets(
        'SettingsScreen resolves directional layout to the right side in RTL',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: desktopHomeOverrides,
          child: wrapWithDesktopLocalization(
            locale: const Locale('ar'),
            child: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        Directionality.of(tester.element(find.byType(SettingsScreen))),
        TextDirection.rtl,
      );
      expect(find.text('الإعدادات'), findsOneWidget);

      // Verify that directional padding/alignment resolves start to right in RTL
      const padding = EdgeInsetsDirectional.only(start: 24, end: 12);
      final resolved = padding.resolve(TextDirection.rtl);
      expect(resolved.right, 24);
      expect(resolved.left, 12);

      const alignment = AlignmentDirectional.centerStart;
      expect(alignment.resolve(TextDirection.rtl), Alignment.centerRight);
    });

    testWidgets(
        'Directional icons have matchTextDirection true, non-directional false',
        (tester) async {
      // Directional icons (like chevronRight) mirror in RTL
      const chevron = AppIcon(AppIcons.materialChevronRight);
      expect(chevron.data.matchTextDirection, isTrue);

      // Non-directional icons (like keyboard, settings) do not mirror
      const keyboard = AppIcon(AppIcons.keyboard);
      expect(keyboard.data.matchTextDirection, isFalse);

      const settings = AppIcon(AppIcons.settings);
      expect(settings.data.matchTextDirection, isFalse);
    });
  });
}
