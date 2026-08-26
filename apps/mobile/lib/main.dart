import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';

import 'src/app/brand.dart';
import 'src/app/providers.dart';
import 'src/app/theme.dart';
import 'src/features/devices/auto_connect.dart';
import 'src/features/devices/device_list_screen.dart';
import 'src/features/devices/link_service.dart';
import 'src/features/share/share_intake.dart';
import 'src/features/watch/watch_bridge.dart';

/// Entry point for the phone app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Log.level = const bool.fromEnvironment('dart.vm.product')
      ? LogLevel.warn
      : LogLevel.debug;
  Log.sink = MultiLogSink(<LogSink>[
    const ConsoleLogSink(),
    // Kept so a bug report can attach recent history without the user having
    // needed to enable logging beforehand.
    MemoryLogSink(),
  ]);

  runApp(const ProviderScope(child: RemoteLinkApp()));
}

/// The messenger every screen's snackbars go through.
///
/// A share can be answered while the user is anywhere in the app — or, on a
/// cold start, before any screen has finished building — so the confirmation
/// cannot depend on having a particular `BuildContext` to hand.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class RemoteLinkApp extends ConsumerWidget {
  const RemoteLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched here, at the root, for two reasons. A Riverpod provider nobody
    // watches is never created, so a listener declared and left unwatched is
    // simply dead code that looks alive. And this one has to outlive any single
    // screen: the address a computer moved to matters just as much while the
    // user is on the touchpad as while they are staring at the device list.
    ref.watch(connectionRetargetProvider);
    // Same reasoning, same place: the background service has to be running
    // while the user is anywhere in the app, and the moment it matters most is
    // the moment they leave it.
    ref.watch(backgroundLinkProvider);
    // And again for the Apple Watch relay. This one has the strongest claim of
    // the three: iOS launches this app in the background purely to deliver a
    // message from the wrist, and in that launch there is no screen at all —
    // so a listener owned by any screen would not exist at the only moment it
    // was needed.
    ref.watch(watchBridgeProvider);
    // And the same again for shares: something has to be listening when the
    // system hands over a link the user shared into this app, whichever screen
    // happens to be open at the time.
    ref.listen<ShareOutcome>(shareControllerProvider, (previous, next) {
      final message = switch (next) {
        ShareIdle() => null,
        ShareSent(:final description, :final peerName) =>
          'Sent $description to $peerName.',
        ShareWaiting(:final description) =>
          'Holding $description until your computer is back.',
        ShareFailed(:final reason) => 'Could not send that: $reason',
      };
      if (message == null) return;
      scaffoldMessengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
      ref.read(shareControllerProvider.notifier).acknowledge();
    });

    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: kProductName,
      debugShowCheckedModeBanner: false,
      theme: remoteLinkTheme(Brightness.light),
      darkTheme: remoteLinkTheme(Brightness.dark),
      // Dark unless the user has said otherwise — see [ThemeModeNotifier] for
      // why this app is the one that does not simply follow the phone. The
      // choice is in Settings › Appearance and is persisted, so `system`,
      // `light` and `dark` are all reachable; only the default differs.
      themeMode: ref.watch(themeModeProvider),
      home: const DeviceListScreen(),
    );
  }
}
