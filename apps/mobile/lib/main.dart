import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';

import 'src/app/theme.dart';
import 'src/features/devices/device_list_screen.dart';

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

class RemoteLinkApp extends StatelessWidget {
  const RemoteLinkApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RemoteLink',
        debugShowCheckedModeBanner: false,
        theme: remoteLinkTheme(Brightness.light),
        darkTheme: remoteLinkTheme(Brightness.dark),
        // System-following by default. A remote control is used in the dark as
        // often as not, and a phone that lights up the room is a worse remote.
        themeMode: ThemeMode.system,
        home: const DeviceListScreen(),
      );
}
