import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';

import 'src/app/brand.dart';
import 'src/app/providers.dart';
import 'src/app/splash_screen.dart';
import 'src/app/theme.dart';
import 'src/features/devices/auto_connect.dart';
import 'src/features/devices/connection_hold.dart';
import 'src/features/devices/link_service.dart';
import 'src/features/devices/remember_prompt.dart';
import 'src/features/host/host_providers.dart';
import 'src/features/host/nearby_prompts.dart';
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

/// The navigator every root-level prompt is raised on.
///
/// Same reasoning as [scaffoldMessengerKey], one step further. A device asking
/// to pair, or offering a file, is a question from outside the app, and the
/// answer has to be asked for wherever the user happens to be — including on a
/// launch where no screen has finished building yet. `MaterialApp.builder`
/// cannot help: its context sits *above* the navigator it wraps, so a sheet
/// pushed from there has nothing to push onto.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
    // And once more for the listening half. A phone that another phone is
    // sending to is not looking at a particular tab — it is very often not
    // looking at the app at all — so the thing that answers the door cannot be
    // owned by a screen that may not be built.
    ref.watch(phoneHostRunnerProvider);
    // Both questions a nearby device can ask, raised from here for the same
    // reason: the phone being sent to is very often not the phone being looked
    // at, and neither question can wait for the right tab to be open.
    listenForNearbyPrompts(ref, navigatorKey);
    // And the mirror image of those: this phone waiting at someone else's
    // door. Same place, same reason — the hold begins wherever the user
    // happens to be, including on a launch that reconnected by itself.
    listenForConnectionHolds(ref, navigatorKey);
    // And the question that decides whether either of the two above happens
    // again. Root-level for the same reason as the rest: the answer is about
    // the next launch, and the connection it is about can come up on any
    // screen — or on none.
    ref.watch(rememberNegotiationProvider);
    listenForRememberPrompts(ref, navigatorKey);
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
      navigatorKey: navigatorKey,
      title: kProductName,
      debugShowCheckedModeBanner: false,
      theme: remoteLinkTheme(Brightness.light),
      darkTheme: remoteLinkTheme(Brightness.dark),
      // Dark unless the user has said otherwise — see [ThemeModeNotifier] for
      // why this app is the one that does not simply follow the phone. The
      // choice is in Settings › Appearance and is persisted, so `system`,
      // `light` and `dark` are all reachable; only the default differs.
      themeMode: ref.watch(themeModeProvider),
      home: const LaunchScreen(),
    );
  }
}
