import Combine
import Foundation
import WatchConnectivity
import WatchKit

/// What the watch knows about the chain it is at the end of.
///
/// Two links, not one, and they fail differently — so they are reported
/// differently. `phoneUnreachable` means this watch cannot talk to the iPhone;
/// `computerOffline` means it can, and the iPhone is not connected to a
/// computer. Collapsing them into "not connected" would send the user to check
/// the wrong device roughly half the time.
enum LinkStatus: Equatable {
    case starting
    case phoneUnreachable
    case computerOffline
    case connected(peer: String)

    /// What to put on screen when there is nothing to drag on.
    ///
    /// Only ever shown for the broken states, so it is a sentence rather than a
    /// label: the screen it appears on is empty, and the user's next move is
    /// different for each of them.
    var message: String {
        switch self {
        case .starting: return "Connecting…"
        case .phoneUnreachable: return "Open Remote Link on your iPhone"
        case .computerOffline: return "Your iPhone isn’t connected to a computer"
        case .connected: return ""
        }
    }

    var canSend: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// The wrist end of the link: turns gestures into messages for the iPhone.
///
/// ## Why the phone is in the middle
///
/// The watch does not speak the Remote Link protocol. Doing so would mean a
/// second implementation of the X25519 handshake, the ChaCha20-Poly1305 session
/// layer, the binary framing and the trust store — every line of `packages/` —
/// in Swift, plus a pairing flow driven from a 40mm screen, plus a watch that
/// must be on the same Wi-Fi as the computer rather than merely near the phone.
///
/// Instead the watch is a remote for the phone, which is already paired,
/// already trusted and already holding an open session. `WCSession.sendMessage`
/// wakes the iPhone app in the background to deliver, so the phone does not
/// have to be in the user's hand — see `WatchBridge.swift` on the iOS side for
/// what happens to a message that arrives before Dart is listening.
///
/// The cost of this design is stated rather than hidden: if iOS has suspended
/// the phone app's *network* session, the phone will reconnect on wake, and the
/// first gesture after a long idle can be dropped while that happens. iOS gives
/// no way for a phone app to hold a socket open indefinitely in the background,
/// so no architecture available here avoids that.
@MainActor
final class WatchLink: NSObject, ObservableObject {
    @Published private(set) var status: LinkStatus = .starting

    /// Movement and clicks that have not been sent yet.
    ///
    /// Accumulated rather than sent per event, because a finger produces touch
    /// updates far faster than WatchConnectivity will carry them.
    private var pendingX: Double = 0
    private var pendingY: Double = 0
    private var pendingClicks: Int = 0

    /// What the queued clicks count *as* — 1 for a single, 2 for a double.
    private var pendingClickCount: Int = 1

    /// Button presses and releases waiting to go out, oldest first.
    ///
    /// A queue rather than a single value, because these are edges and not a
    /// state: coalescing a press and the release that follows it into one field
    /// would leave the computer holding a button nobody ever let go of. At most
    /// one travels per message, and a queued edge is allowed to jump the send
    /// interval — a hold that arrives 16 ms late is a hold that started in the
    /// wrong place.
    private var pendingButtons: [UInt8] = []

    /// How many messages are on the wire and have not been answered.
    ///
    /// This, and the interval below, are the whole latency design.
    /// `WCSession.sendMessageData` is not a streaming channel — every call is
    /// an XPC hop and a Bluetooth transaction, and how long one takes depends
    /// on the radio, the phone's state, and what else is on the link.
    ///
    /// Two failures sit either side of the right answer, and this app has been
    /// both. Flushing on a fixed 60 Hz timer queues without bound whenever the
    /// link is slower than the timer: the cursor does not merely lag, it falls
    /// further behind for as long as the drag lasts. Sending strictly one at a
    /// time cannot queue — but it also means the cursor moves exactly once per
    /// round trip, so at 100 ms it advances in ten visible jumps a second,
    /// which reads as dropped frames rather than as lag.
    ///
    /// One at a time is the answer, and the stepping is fixed elsewhere.
    ///
    /// A window of three was tried, on the theory that staggered sends would
    /// arrive more often without any single message being older. They did not:
    /// `WCSession` serialises messages on one session, so the second and third
    /// wait behind the first, and the measured round trip went from about 60 ms
    /// to 182 — the queue had simply come back with a bound on it. Widening a
    /// window over a serialised transport buys nothing and costs everything it
    /// appears to buy.
    ///
    /// So the wire carries one message, and the next goes out only when that
    /// one is answered: the send rate becomes the link's own rate and cannot
    /// queue. The chunkiness that motivated the window is dealt with where it
    /// should be — on the phone, which pays each batch out in slices over the
    /// fast hop rather than jumping the cursor once per batch. See
    /// `WatchMotionSmoother` in `watch_bridge.dart`.
    private var inFlight = 0

    /// Messages allowed on the wire at once.
    private static let window = 1

    /// The floor on the gap between sends.
    ///
    /// Close to irrelevant at a window of one — the link is far slower than
    /// this — but it costs nothing and it is what stops a fast link being
    /// flooded with messages describing a few microseconds of movement each.
    private static let minimumInterval: TimeInterval = 1.0 / 60.0

    private var lastSend: Date?
    private var scheduled: Timer?

    /// Round trip to the phone and back, smoothed. Nil until the first reply.
    ///
    /// Measured rather than assumed, because every guess about this link so far
    /// has been wrong, and the right design depends on whether the answer is
    /// 20 ms or 200.
    @Published private(set) var roundTripMillis: Double?

    private var session: WCSession { .default }

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            status = .phoneUnreachable
            return
        }
        session.delegate = self
        session.activate()
    }

    // MARK: - Gestures

    /// Adds movement to the next message.
    func move(dx: Double, dy: Double) {
        pendingX += dx
        pendingY += dy
        pump()
    }

    /// A click, single or double.
    ///
    /// `count` is what the click *means*, not how many arrived: macOS opens a
    /// file on a `clickCount` of two and does nothing whatever for two separate
    /// clicks of one, however close together they land.
    func click(count: Int = 1) {
        WKInterfaceDevice.current().play(.click)
        pendingClickCount = max(pendingClickCount, count)
        // Queued alongside the movement rather than sent on its own, so it
        // travels in the same message as the movement that aimed it. Sent
        // separately it would need a second round trip, and could land before
        // the drag that positioned the cursor — a tap at the end of a drag would
        // click where the cursor used to be.
        pendingClicks += 1
        pump()
    }

    /// Presses the left button and leaves it down: the start of dragging a
    /// window, or of selecting text.
    func hold() {
        WKInterfaceDevice.current().play(.start)
        pendingButtons.append(1)
        pump()
    }

    /// Lets it go.
    func release() {
        WKInterfaceDevice.current().play(.stop)
        pendingButtons.append(2)
        pump()
    }

    // MARK: - Sending

    /// Sends whatever has accumulated, if the window has room.
    ///
    /// Called after every gesture event and again whenever a message is
    /// answered, so the link is kept exactly as busy as it can be and no
    /// busier.
    private func pump() {
        guard inFlight < Self.window else { return }
        guard pendingX != 0 || pendingY != 0 || pendingClicks > 0
            || !pendingButtons.isEmpty else { return }
        guard session.activationState == .activated, session.isReachable else {
            status = .phoneUnreachable
            return
        }

        // Too soon since the last one: come back when it is not, rather than
        // dropping this movement. It stays accumulated in the meantime, so
        // waiting costs nothing but the wait.
        // Movement waits its turn; a button edge does not. Holding the press
        // back for a fraction of the interval puts the button down somewhere
        // the finger has already left.
        if pendingButtons.isEmpty, let last = lastSend {
            let remaining = Self.minimumInterval - Date().timeIntervalSince(last)
            if remaining > 0 {
                schedulePump(after: remaining)
                return
            }
        }
        scheduled?.invalidate()
        scheduled = nil

        let payload = WatchInput(
            dx: pendingX,
            dy: pendingY,
            clicks: pendingClicks,
            clickCount: pendingClickCount,
            button: pendingButtons.isEmpty ? 0 : pendingButtons.removeFirst()
        )
        pendingX = 0
        pendingY = 0
        pendingClicks = 0
        pendingClickCount = 1
        inFlight += 1
        lastSend = Date()
        let sentAt = Date()

        // `sendMessageData`, not `sendMessage`. A dictionary is serialised as a
        // property list at both ends — a couple of hundred bytes of keys and
        // type tags, plus the encode and decode, for what is two numbers and a
        // count. Ten bytes of packed little-endian goes out instead.
        //
        // The reply handler is what opens the window again; its contents are
        // empty and irrelevant.
        session.sendMessageData(payload.encoded, replyHandler: { [weak self] _ in
            Task { @MainActor in
                self?.completed(sentAt: sentAt)
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.inFlight = max(0, self.inFlight - 1)
                self.status = .phoneUnreachable
            }
        })
    }

    private func completed(sentAt: Date) {
        inFlight = max(0, inFlight - 1)
        let sample = Date().timeIntervalSince(sentAt) * 1000
        // Smoothed, because a single sample on a radio link says very little
        // and a figure that flickers is a figure nobody can read.
        roundTripMillis = roundTripMillis.map { $0 * 0.8 + sample * 0.2 } ?? sample
        pump()
    }

    private func schedulePump(after delay: TimeInterval) {
        guard scheduled == nil else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            // `assumeIsolated` rather than a `Task`: the timer already fires on
            // the main run loop, so the actor requirement is satisfied without
            // allocating a continuation to reach code that was on the right
            // thread all along.
            MainActor.assumeIsolated {
                self?.scheduled = nil
                self?.pump()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduled = timer
    }

    /// Asks the phone what it is connected to.
    ///
    /// The phone also pushes this whenever it changes, so this is only needed
    /// when the watch has just woken and has no idea — on activation, and on
    /// becoming reachable again.
    func refreshStatus() {
        guard session.activationState == .activated else { return }
        guard session.isReachable else {
            status = .phoneUnreachable
            return
        }
        session.sendMessage(["t": "state"], replyHandler: { [weak self] reply in
            Task { @MainActor in self?.apply(reply) }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.status = .phoneUnreachable }
        })
    }

    fileprivate func apply(_ payload: [String: Any]) {
        let connected = payload["connected"] as? Bool ?? false
        let peer = payload["peer"] as? String ?? ""
        status = connected ? .connected(peer: peer) : .computerOffline
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            guard activationState == .activated else {
                self.status = .phoneUnreachable
                return
            }
            // Whatever the phone last pushed, so a watch that wakes with the
            // phone out of reach still shows the truth as of the last contact
            // rather than "Starting" forever.
            let context = session.receivedApplicationContext
            if !context.isEmpty { self.apply(context) }
            self.refreshStatus()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshStatus() }
    }

    /// The phone pushing a change rather than answering a question.
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}

/// One batch of input, packed for the wire.
///
/// Ten bytes, little-endian, and written out by hand rather than through
/// `Codable`: `JSONEncoder` would put this straight back into the string-keyed
/// serialisation this exists to avoid, and the layout has to be matched byte
/// for byte by `WatchBridge.swift` on the phone — which is far easier to keep
/// honest against a table than against a synthesised encoder.
///
///     0      kind, always 2
///     1..4   dx, Float32
///     5..8   dy, Float32
///     9      clicks, UInt8      how many click events
///     10     clickCount, UInt8  what each counts as: 1 single, 2 double
///     11     button, UInt8      0 none, 1 press and hold, 2 release
struct WatchInput {
    /// Distinguishes this from whatever another build sends. A phone that does
    /// not recognise the kind drops the message rather than reading the bytes
    /// as something they are not.
    static let kind: UInt8 = 2
    static let size = 12

    let dx: Double
    let dy: Double
    let clicks: Int
    let clickCount: Int
    let button: UInt8

    var encoded: Data {
        var data = Data(capacity: Self.size)
        data.append(Self.kind)
        data.appendLittleEndian(Float32(dx).bitPattern)
        data.appendLittleEndian(Float32(dy).bitPattern)
        // Saturated rather than truncated: 255 taps inside one round trip is
        // not a thing a wrist can do, but a wrap to zero would silently swallow
        // the click if it ever were.
        data.append(UInt8(min(clicks, 255)))
        data.append(UInt8(min(max(clickCount, 1), 255)))
        data.append(button)
        return data
    }
}

extension Data {
    /// Appends four bytes, least significant first.
    ///
    /// Byte by byte on purpose. The pointer-based alternatives either need an
    /// alignment guarantee the buffer does not have, or an availability floor
    /// above this app's, and neither is worth it for four bytes.
    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
