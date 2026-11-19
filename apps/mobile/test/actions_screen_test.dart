import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/l10n.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/actions/actions_controller.dart';
import 'package:remotelink_mobile/src/features/control/control_screen.dart';
import 'package:remotelink_mobile/src/features/host/host_providers.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

void main() {
  testWidgets(
      'Actions appears only with the capability and shows empty state or tiles',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final identity = await tester.runAsync(DeviceIdentity.generate);
    for (final locale in [const Locale('en'), const Locale('ar')]) {
      const base = Capabilities(
        Capabilities.mouse |
            Capabilities.keyboard |
            Capabilities.mediaControl |
            Capabilities.clipboardText |
            Capabilities.fileTransfer,
      );
      final capabilities = StateProvider<Capabilities>((_) => base);
      final catalog = StateProvider<List<CommandCatalogEntry>>((_) => []);
      final container = ProviderContainer(overrides: [
        activeCapabilitiesProvider
            .overrideWith((ref) => ref.watch(capabilities)),
        actionsCatalogProvider.overrideWith((ref) => ref.watch(catalog)),
        identityProvider.overrideWith((ref) => identity!),
        clientStateProvider.overrideWith(
          (ref) => Stream.value(ClientState.connected),
        ),
        systemStatusProvider
            .overrideWith((ref) => const Stream<SystemStatus?>.empty()),
        connectionQualityProvider
            .overrideWith((ref) => const Stream<ConnectionQuality>.empty()),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ControlScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.tabActions), findsNothing);
      container.read(capabilities.notifier).state =
          base.plus(Capabilities.commandRegistry);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.tabActions));
      await tester.pumpAndSettle();
      expect(find.text(l10n.actionsEmpty), findsOneWidget);

      const label = 'نسخ احتياطي';
      container.read(catalog.notifier).state = const [
        CommandCatalogEntry(id: 'backup-id', name: label),
      ];
      await tester.pumpAndSettle();
      expect(find.text(l10n.actionsEmpty), findsNothing);
      expect(find.widgetWithText(TextButton, label), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(label))),
        locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
