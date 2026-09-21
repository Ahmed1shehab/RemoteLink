import Flutter
import Foundation
import WatchConnectivity

/// The phone end of the Apple Watch link.
///
/// The watch does not speak the Remote Link protocol — see `WatchLink.swift` in
/// the watch target for why not. It sends intents ("move by this much", "left
/// click") over WatchConnectivity, and this class hands them to Dart, which
/// puts them on the session that is already open to the computer.
///
/// Two channels, because the traffic runs both ways and is not the same shape
/// in each direction:
///
/// * `watch_commands` — an event channel, watch to Dart, one event per intent.
/// * `watch` — a method channel, Dart to here, carrying the connection state so
///   the watch can say what it is connected to, and answering questions about
///   the watch itself so Settings can be honest about whether there is one.
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    private var sink: FlutterEventSink?

    /// Intents that arrived before Dart was listening.
    ///
    /// This is not a rare case, it is the *normal* one: `sendMessage` launches
    /// the iPhone app in the background to deliver, so the first message of a
    /// session routinely arrives while the Flutter engine is still starting and
    /// no Dart code has subscribed yet. Dropping it would mean the first thing
    /// the user does on the watch after a while never happens, which reads as a
    /// broken app rather than a cold start.
    private var backlog: [[String: Any]] = []

    /// Oldest-first eviction past this. Movement is only meaningful while it is
    /// fresh, and a backlog long enough to matter is a backlog whose contents
    /// describe a gesture that finished long ago.
    private static let backlogLimit = 64

    /// What Dart last said about the computer link, and what the watch is told
    /// when it asks.
    private var linkState: [String: Any] = ["connected": false, "peer": ""]

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    /// Wires up both channels and activates the session.
    ///
    /// Called from `AppDelegate` as the engine comes up, which is early enough
    /// that a message delivered by a background launch finds the session
    /// already activating.
    func start(with registrar: FlutterPluginRegistrar) {
        FlutterEventChannel(
            name: "com.remotelink.app/watch_commands",
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(self)

        let methods = FlutterMethodChannel(
            name: "com.remotelink.app/watch",
            binaryMessenger: registrar.messenger()
        )
        methods.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }

        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setLinkState":
            let arguments = call.arguments as? [String: Any] ?? [:]
            let state: [String: Any] = [
                "connected": arguments["connected"] as? Bool ?? false,
                "peer": arguments["peer"] as? String ?? "",
            ]
            linkState = state
            // Pushed rather than left for the watch to ask about. The watch is
            // asleep most of the time and application context is delivered
            // whenever it next wakes, so the header is right the moment the
            // user raises their wrist instead of after a round trip.
            try? session?.updateApplicationContext(state)
            result(nil)

        case "watchState":
            guard let session, session.activationState == .activated else {
                result([
                    "supported": WCSession.isSupported(),
                    "paired": false,
                    "installed": false,
                    "reachable": false,
                ])
                return
            }
            result([
                "supported": true,
                "paired": session.isPaired,
                "installed": session.isWatchAppInstalled,
                "reachable": session.isReachable,
            ])

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Hands one intent to Dart, or holds it until Dart is there to take it.
    private func deliver(_ message: [String: Any]) {
        // The event sink is not thread-safe and must be called on the platform
        // thread; WatchConnectivity calls back on its own queue.
        DispatchQueue.main.async {
            guard let sink = self.sink else {
                self.backlog.append(message)
                if self.backlog.count > Self.backlogLimit {
                    self.backlog.removeFirst(self.backlog.count - Self.backlogLimit)
                }
                return
            }
            sink(message)
        }
    }
}

extension WatchBridge: FlutterStreamHandler {
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        sink = events
        let held = backlog
        backlog.removeAll()
        for message in held { events(message) }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}

extension WatchBridge: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    /// iOS only: the session has to be reactivated after switching watches.
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    /// The one dictionary message the watch waits on an answer for.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if message["t"] as? String == "state" {
            replyHandler(linkState)
            return
        }
        deliver(message)
        replyHandler([:])
    }

    /// Input, packed. This is the hot path — everything a finger does arrives
    /// here — and the reply is what tells the watch it may send the next batch,
    /// so it is sent before the message is handed on rather than after.
    func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        replyHandler(Data())
        guard let input = WatchInput(messageData) else { return }
        var payload: [String: Any] = [
            "t": "move",
            "dx": input.dx,
            "dy": input.dy,
        ]
        // The path, when the watch sent one, flattened to dx, dy, millis per
        // slice. Flat rather than nested because the standard Flutter codec
        // carries a list of numbers for nothing and a list of lists for rather
        // more, and there is no ambiguity in a list whose length is a multiple
        // of three. Dart replays this and ignores the summed `dx`/`dy` above,
        // which are kept for a phone talking to a watch too old to send a path.
        if !input.path.isEmpty { payload["path"] = input.path }
        if input.clicks > 0 {
            payload["clicks"] = input.clicks
            payload["clickCount"] = input.clickCount
        }
        if input.button == 3 {
            // Not a button edge at all: the finger left the glass. Named rather
            // than passed through as a code, because Dart treats it as the end
            // of the gesture and not as something to press.
            payload["ended"] = true
        } else if input.button != 0 {
            payload["button"] = Int(input.button)
        }
        deliver(payload)
    }
}

/// The phone's half of the packed layout in `WatchLink.swift`.
///
/// Kind 3, the current one:
///
///     0      kind, always 3
///     1      clicks, UInt8      how many click events
///     2      clickCount, UInt8  what each counts as: 1 single, 2 double
///     3      button, UInt8      0 none, 1 press and hold, 2 release,
///                               3 the finger left the glass
///     4      samples, UInt8     how many path slices follow
///     then, per slice, ten bytes:
///     +0..3  dx, Float32
///     +4..7  dy, Float32
///     +8..9  millis, UInt16     how long the slice covers
///
/// Kind 2, still accepted:
///
///     0      kind, always 2
///     1..4   dx, Float32
///     5..8   dy, Float32
///     9      clicks, UInt8
///     10     clickCount, UInt8
///     11     button, UInt8
///
/// Both are read because the watch and the phone are updated independently by
/// the App Store, and a phone that has run ahead of the watch on the wrist must
/// keep working. Returns nil for anything else: reading unknown bytes as one of
/// these would move the cursor somewhere arbitrary, so an unrecognised message
/// is dropped, which costs one batch of movement.
struct WatchInput {
    /// Total movement in the message, whatever shape it arrived in.
    let dx: Double
    let dy: Double

    /// The path, flattened to dx, dy, millis per slice. Empty for a kind 2
    /// message, which carries only the total.
    let path: [Double]

    let clicks: Int
    let clickCount: Int
    let button: UInt8

    init?(_ data: Data) {
        guard let kind = data.first else { return nil }
        switch kind {
        case 3: self.init(path: data)
        case 2: self.init(total: data)
        default: return nil
        }
    }

    /// Kind 3: a path of slices.
    private init?(path data: Data) {
        let header = 5
        let stride = 10
        guard data.count >= header else { return nil }
        let base = data.startIndex
        let count = Int(data[base + 4])
        guard data.count >= header + count * stride else { return nil }

        var flattened: [Double] = []
        flattened.reserveCapacity(count * 3)
        var totalX = 0.0
        var totalY = 0.0
        for index in 0..<count {
            let offset = header + index * stride
            let x = data.float32(at: base + offset)
            let y = data.float32(at: base + offset + 4)
            // A NaN or an infinity here would reach `MouseMove` and be rounded
            // to an arbitrary integer. Nothing legitimate produces one, so
            // anything that does is corrupt and the message is dropped whole
            // rather than partly replayed.
            guard x.isFinite, y.isFinite else { return nil }
            let millis = Double(data.uint16(at: base + offset + 8))
            totalX += x
            totalY += y
            flattened.append(contentsOf: [x, y, millis])
        }

        dx = totalX
        dy = totalY
        path = flattened
        clicks = Int(data[base + 1])
        clickCount = max(1, Int(data[base + 2]))
        let raw = data[base + 3]
        button = raw <= 3 ? raw : 0
    }

    /// Kind 2: one summed delta, from a watch older than the path format.
    private init?(total data: Data) {
        guard data.count >= 12 else { return nil }
        let base = data.startIndex
        let x = data.float32(at: base + 1)
        let y = data.float32(at: base + 5)
        guard x.isFinite, y.isFinite else { return nil }
        dx = x
        dy = y
        path = []
        clicks = Int(data[base + 9])
        clickCount = max(1, Int(data[base + 10]))
        // Anything outside the three it knows is treated as "no change", which
        // leaves the button exactly as it was rather than guessing at an edge.
        let raw = data[base + 11]
        button = raw <= 2 ? raw : 0
    }
}

extension Data {
    /// Reads four little-endian bytes as a `Float32`.
    ///
    /// Assembled byte by byte: `Data` off the wire carries no alignment
    /// guarantee, and a misaligned load of a `UInt32` is undefined rather than
    /// merely slow.
    func float32(at index: Index) -> Double {
        let bits = UInt32(self[index])
            | UInt32(self[index + 1]) << 8
            | UInt32(self[index + 2]) << 16
            | UInt32(self[index + 3]) << 24
        return Double(Float32(bitPattern: bits))
    }

    /// Reads two little-endian bytes as a `UInt16`.
    func uint16(at index: Index) -> UInt16 {
        UInt16(self[index]) | UInt16(self[index + 1]) << 8
    }
}
