import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rl_core/rl_core.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app/providers.dart';
import 'src/ui/home_screen.dart';

/// Entry point for the desktop companion.
///
/// The product is a background service, not a window. The window is an
/// occasional inspector the user opens to pair a phone or check status, and the
/// service must keep running when it closes — which is why `setPreventClose`
/// is set and the close button hides rather than exits.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Log.level = kReleaseBuild ? LogLevel.info : LogLevel.debug;
  Log.sink = MultiLogSink(<LogSink>[
    const ConsoleLogSink(),
    MemoryLogSink(),
  ]);

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(880, 620),
      minimumSize: Size(720, 520),
      center: true,
      title: 'RemoteLink',
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      await windowManager.show();
      // Intercepting close is what makes this a service rather than an app: the
      // listener hides the window and leaves the socket, discovery beacon, and
      // clipboard watcher running.
      await windowManager.setPreventClose(true);
    },
  );

  await _configureAutoLaunch();

  runApp(const ProviderScope(child: RemoteLinkDesktopApp()));
}

/// Set by the build system for release binaries.
const bool kReleaseBuild = bool.fromEnvironment('dart.vm.product');

Future<void> _configureAutoLaunch() async {
  try {
    final info = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: info.appName,
      appPath: Platform.resolvedExecutable,
      // Starting minimised is the whole point: the user installed a service,
      // and having a window appear on every login would be an annoyance they
      // would fix by disabling autostart entirely.
      args: <String>['--minimised'],
    );
  } on Object catch (e) {
    Log.scoped('desktop.autostart').warn('could not configure autostart',
        error: e);
  }
}

class RemoteLinkDesktopApp extends StatelessWidget {
  const RemoteLinkDesktopApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RemoteLink',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D5AFE)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3D5AFE),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      );
}

/// Owns the tray icon and its menu.
///
/// Kept as a plain class rather than a widget because the tray outlives every
/// window: it is the only interface the user has while the app is hidden, which
/// is most of the time.
class TrayController {
  TrayController({
    required this.onShowWindow,
    required this.onQuit,
    required this.onTogglePairing,
  });

  final VoidCallback onShowWindow;
  final VoidCallback onQuit;
  final void Function({required bool enabled}) onTogglePairing;

  final SystemTray _tray = SystemTray();
  final Menu _menu = Menu();

  Future<void> initialise({required int connectedCount}) async {
    await _tray.initSystemTray(
      iconPath: Platform.isWindows
          ? 'assets/tray/icon.ico'
          : 'assets/tray/icon.png',
      toolTip: 'RemoteLink',
    );

    await rebuild(connectedCount: connectedCount, pairingEnabled: true);

    // Left click opens the window on Windows, where that is the convention;
    // macOS shows the menu on any click, matching every other status item.
    _tray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        Platform.isWindows ? onShowWindow() : _tray.popUpContextMenu();
      } else if (eventName == kSystemTrayEventRightClick) {
        Platform.isWindows ? _tray.popUpContextMenu() : onShowWindow();
      }
    });
  }

  /// Rebuilds the menu so it reflects live state.
  Future<void> rebuild({
    required int connectedCount,
    required bool pairingEnabled,
  }) async {
    await _menu.buildFrom(<MenuItemBase>[
      MenuItemLabel(
        label: connectedCount == 0
            ? 'No devices connected'
            : '$connectedCount device${connectedCount == 1 ? '' : 's'} '
                'connected',
        enabled: false,
      ),
      MenuSeparator(),
      MenuItemLabel(label: 'Open RemoteLink', onClicked: (_) => onShowWindow()),
      MenuItemCheckbox(
        label: 'Allow new devices to pair',
        checked: pairingEnabled,
        onClicked: (_) => onTogglePairing(enabled: !pairingEnabled),
      ),
      MenuSeparator(),
      MenuItemLabel(label: 'Quit RemoteLink', onClicked: (_) => onQuit()),
    ]);
    await _tray.setContextMenu(_menu);
  }

  Future<void> dispose() => _tray.destroy();
}
