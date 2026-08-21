import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';

import 'src/app/brand.dart';
import 'src/app/theme.dart';
import 'src/features/devices/auto_connect.dart';
import 'src/features/devices/device_list_screen.dart';
import 'src/features/devices/link_service.dart';

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

    return MaterialApp(
      title: kProductName,
      debugShowCheckedModeBanner: false,
      theme: remoteLinkTheme(Brightness.light),
      darkTheme: remoteLinkTheme(Brightness.dark),
      // System-following by default. A remote control is used in the dark as
      // often as not, and a phone that lights up the room is a worse remote.
      themeMode: ThemeMode.system,
      home: const DeviceListScreen(),
    );
  }
}
