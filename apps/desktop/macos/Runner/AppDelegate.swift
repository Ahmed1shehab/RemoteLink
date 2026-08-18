import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// False, because this is a service with a window, not a window with a
  /// service behind it.
  ///
  /// The template ships `true`, and with it the close button killed the whole
  /// companion — silently, and only sometimes, which is why it survived so
  /// long. Dart intercepts the close and calls `hide()`, which is
  /// `NSWindow.orderOut`; AppKit counts a window ordered out as one that is no
  /// longer on screen, decides the last window has gone, and terminates the
  /// process. The pairing, the discovery beacon and the clipboard watcher all
  /// went with it, so a phone that was mid-transfer simply lost its computer.
  ///
  /// Quitting is the menu-bar item's job, and nothing else's.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Clicking the Dock icon brings the window back.
  ///
  /// Needed for the same reason: `orderOut` leaves AppKit with nothing to
  /// restore, so without this the Dock icon is a button that does nothing once
  /// the window has been closed once.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows where window is NSPanel == false {
        window.makeKeyAndOrderFront(self)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
