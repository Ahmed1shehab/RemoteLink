import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let clipboardWatcher = ClipboardChangeStreamHandler()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    FlutterEventChannel(
      name: "com.remotelink.app/clipboard_changes",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setStreamHandler(clipboardWatcher)

    super.awakeFromNib()
  }
}

/// Reports that the pasteboard changed, without reading a byte of it.
///
/// macOS has no change notification for the pasteboard at all — `changeCount`
/// polling is the documented way to notice one, and it is what every clipboard
/// manager on the platform does. Nothing here reads the contents; Dart does
/// that once, after this fires.
///
/// This runs in the client's macOS build, which exists so the whole stack can
/// be exercised in a window without a simulator. Keeping the behaviour the same
/// there as on a phone is the point: a sync that only works on real hardware is
/// a sync nobody can debug.
final class ClipboardChangeStreamHandler: NSObject, FlutterStreamHandler {
  private static let interval: TimeInterval = 0.6

  private var timer: Timer?
  private var lastChangeCount = 0

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    lastChangeCount = NSPasteboard.general.changeCount

    let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
      guard let self else { return }
      let count = NSPasteboard.general.changeCount
      guard count != self.lastChangeCount else { return }
      self.lastChangeCount = count
      events(nil)
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    timer?.invalidate()
    timer = nil
    return nil
  }
}
