import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rl_core/rl_core.dart';
import 'package:tray_manager/tray_manager.dart';
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
        home: const _TrayHost(child: HomeScreen()),
      );
}

/// Owns the menu-bar item and the window's close behaviour.
///
/// These belong together because they are two halves of one decision. The app
/// is a background service: `setPreventClose(true)` stops the red button from
/// quitting it, and `LSUIElement` keeps it out of the Dock. Each is right on
/// its own and together they are a trap — without a menu-bar icon and a close
/// handler, the window cannot be dismissed *or* reopened, and the service runs
/// on with no way to reach it.
///
/// So the tray icon is not decoration here. It is the only affordance the user
/// has while the window is hidden, which is almost all of the time.
class _TrayHost extends ConsumerStatefulWidget {
  const _TrayHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_TrayHost> createState() => _TrayHostState();
}

class _TrayHostState extends ConsumerState<_TrayHost> with WindowListener {
  late final TrayController _tray;
  int _lastCount = -1;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    _tray = TrayController(
      onShowWindow: () async {
        await windowManager.show();
        await windowManager.focus();
      },
      onQuit: () async {
        // Tear the service down before the process exits so the discovery
        // beacon sends its goodbye and clients drop the entry immediately
        // instead of waiting for it to time out.
        final service = ref.read(desktopServiceProvider).valueOrNull;
        await service?.stop();
        await _tray.dispose();
        await windowManager.destroy();
      },
      onTogglePairing: ({required bool enabled}) {
        final service = ref.read(desktopServiceProvider).valueOrNull;
        if (service != null) service.acceptsNewPairings = enabled;
      },
    );

    unawaited(_tray.initialise(connectedCount: 0));
  }

  /// The red button hides rather than quits — that is what makes this a
  /// service. Without this handler `setPreventClose(true)` leaves a button that
  /// simply does nothing when clicked.
  @override
  void onWindowClose() {
    unawaited(windowManager.hide());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    unawaited(_tray.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(connectedDevicesProvider).valueOrNull?.length ?? 0;

    // Rebuilt only when the count actually changes. The provider emits on every
    // device update, and rewriting the native menu on each one would be a
    // visible flicker in the menu bar.
    if (count != _lastCount) {
      _lastCount = count;
      unawaited(_tray.rebuild(connectedCount: count));
    }

    return widget.child;
  }
}

/// Owns the tray icon and its menu.
///
/// Kept as a plain class rather than a widget because the tray outlives every
/// window: it is the only interface the user has while the app is hidden, which
/// is most of the time.
class TrayController with TrayListener {
  TrayController({
    required this.onShowWindow,
    required this.onQuit,
    required this.onTogglePairing,
  });

  final VoidCallback onShowWindow;
  final VoidCallback onQuit;
  final void Function({required bool enabled}) onTogglePairing;

  static const String _keyShow = 'show';
  static const String _keyPairing = 'pairing';
  static const String _keyQuit = 'quit';

  bool _pairingEnabled = true;

  Future<void> initialise({required int connectedCount}) async {
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/tray/icon.ico' : 'assets/tray/icon.png',
      // macOS renders template images in the menu bar's own colour, so the
      // icon inverts correctly in dark mode instead of staying black.
      isTemplate: Platform.isMacOS,
    );
    await trayManager.setToolTip('RemoteLink');
    await rebuild(connectedCount: connectedCount);
    trayManager.addListener(this);
  }

  /// Rebuilds the menu so it reflects live state.
  Future<void> rebuild({required int connectedCount}) async {
    await trayManager.setContextMenu(
      Menu(
        items: <MenuItem>[
          MenuItem(
            label: connectedCount == 0
                ? 'No devices connected'
                : '$connectedCount device${connectedCount == 1 ? '' : 's'} '
                    'connected',
            disabled: true,
          ),
          MenuItem.separator(),
          MenuItem(key: _keyShow, label: 'Open RemoteLink'),
          MenuItem.checkbox(
            key: _keyPairing,
            label: 'Allow new devices to pair',
            checked: _pairingEnabled,
          ),
          MenuItem.separator(),
          MenuItem(key: _keyQuit, label: 'Quit RemoteLink'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    // Left click opens the window on Windows, where that is the convention.
    // macOS shows the menu on any click, matching every other status item.
    if (Platform.isWindows) {
      onShowWindow();
    } else {
      unawaited(trayManager.popUpContextMenu());
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (Platform.isWindows) {
      unawaited(trayManager.popUpContextMenu());
    } else {
      onShowWindow();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _keyShow:
        onShowWindow();
      case _keyPairing:
        _pairingEnabled = !_pairingEnabled;
        onTogglePairing(enabled: _pairingEnabled);
      case _keyQuit:
        onQuit();
    }
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
