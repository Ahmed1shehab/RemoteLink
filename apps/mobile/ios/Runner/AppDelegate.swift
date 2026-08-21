import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let clipboardWatcher = ClipboardChangeStreamHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RemoteLinkClipboardWatcher") {
      FlutterEventChannel(
        name: "com.remotelink.app/clipboard_changes",
        binaryMessenger: registrar.messenger()
      ).setStreamHandler(clipboardWatcher)
    }
  }
}

/// Reports that the pasteboard changed, without reading a byte of it.
///
/// `changeCount` is the one thing iOS will tell an app about the pasteboard for
/// free. Reading `string` or `items` is what triggers the paste alert the user
/// has to dismiss, so the counter is polled and the contents are left alone;
/// Dart does the single read afterwards, once per copy, when there is something
/// new to send.
///
/// Polling only runs while Dart is subscribed, and Dart subscribes only in the
/// foreground — which is also the only place iOS would serve a read.
final class ClipboardChangeStreamHandler: NSObject, FlutterStreamHandler {
  /// Frequent enough to feel immediate, rare enough to be free. This wakes up
  /// to compare two integers; the expensive part of a clipboard sync is the
  /// read, and that only happens when this fires.
  private static let interval: TimeInterval = 0.6

  private var timer: Timer?
  private var lastChangeCount = 0

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    // Baselined at subscribe time, so whatever was already on the pasteboard
    // does not read as a change the instant the app opens. The resume hook in
    // Dart covers that case deliberately and with the user's attention on it.
    lastChangeCount = UIPasteboard.general.changeCount

    let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
      guard let self else { return }
      let count = UIPasteboard.general.changeCount
      guard count != self.lastChangeCount else { return }
      self.lastChangeCount = count
      events(nil)
    }
    // `.common`, so the timer keeps running while a scroll or a sheet has the
    // run loop in tracking mode — copying from inside a scrolling list is
    // ordinary, and a timer in `.default` would miss exactly that.
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
