import SwiftUI
import WatchKit

/// The whole watch app: a full-screen surface you drag on.
///
/// There is nothing else on it — no buttons, no icons, no status row. Every
/// control that could be added here comes directly out of the area the finger
/// has to work in, which on a 41mm watch is already less than a thumbprint, and
/// the phone is a better place for anything that needs a control.
///
/// Two gestures, both made with the same finger on the same glass: drag moves
/// the pointer, and a tap that goes nowhere clicks. Tap is kept because a
/// pointer that cannot click is not a remote control — it is a cursor that can
/// only be admired.
///
/// The one piece of chrome is a line of text, and only when the chain is broken:
/// with nothing connected there is nothing to drag, and a blank black screen
/// would be indistinguishable from a crash.
struct TrackpadView: View {
    @EnvironmentObject private var link: WatchLink

    /// The previous touch location, so movement is sent as a delta.
    ///
    /// `DragGesture` reports a translation from where the gesture began, not
    /// from the last callback. Sending the translation would move the cursor by
    /// the whole distance travelled on every update — accelerating away from
    /// the finger and never coming back.
    @State private var lastPoint: CGPoint?

    /// Total distance travelled this gesture, for the tap-versus-drag decision.
    @State private var travelled: CGFloat = 0
    @State private var began: Date?

    /// When the last tap ended, for spotting a double.
    @State private var lastTapEnded: Date?

    /// Whether the left button is being held down by a press-and-hold.
    @State private var holding = false

    /// Fires if the finger stays still long enough to mean "hold", not "tap".
    @State private var holdTimer: Timer?

    /// Active touch location and fade for touch-reactive swelling dot feedback.
    @State private var touchLocation: CGPoint?
    @State private var touchFade: Double = 0.0

    /// Past these, a gesture was a drag and not a tap.
    private static let tapSlop: CGFloat = 8
    private static let tapDuration: TimeInterval = 0.4

    /// Two taps closer together than this are one double click.
    ///
    /// Longer than a Mac's own default. The watch is small and the finger is
    /// large, so the second tap of a deliberate double takes longer to place
    /// than it does on a trackpad the hand is already resting on.
    private static let doubleTapWindow: TimeInterval = 0.45

    /// How long a still finger waits before the button goes down.
    ///
    /// This is the only way to drag a window or select a run of text from the
    /// watch: hold until it clicks, then move. There is no second finger
    /// available and no room for a modifier button, so the gesture has to be
    /// made of time rather than of contacts.
    private static let holdDelay: TimeInterval = 0.45

    /// How far the cursor moves per point of finger travel.
    ///
    /// The watch screen is physically small (~170pt across), so finger gestures
    /// are tight and delicate. A slow sensitivity (~1:1 desktop pixels per watch
    /// point with default phone sensitivity) allows the user to aim precisely
    /// and move the pointer smoothly without jumping or overshooting.
    private static let gain: Double = 0.6

    var body: some View {
        ZStack {
            Theme.canvas

            if link.status.canSend {
                // Resting lattice rasterised once.
                DotField()

                // Dynamic touch-reactive swelling dots around the active swipe point.
                DynamicTouchDotField(touchLocation: touchLocation, fade: touchFade)
            } else {
                Text(link.status.message)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .padding(.horizontal, 12)
            }

            // The gesture lives on its own transparent layer covering
            // everything, so what the finger hits never changes with what is
            // drawn underneath it.
            Color.clear
                .contentShape(Rectangle())
                .gesture(drag)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Trackpad")
        .accessibilityHint(
            link.status.canSend
                ? "Drag to move the pointer. Tap to click."
                : link.status.message
        )
        .onAppear { link.refreshStatus() }
    }

    private func startHoldTimer() {
        cancelHoldTimer()
        holdTimer = Timer.scheduledTimer(
            withTimeInterval: Self.holdDelay,
            repeats: false
        ) { _ in
            Task { @MainActor in
                // Only if the finger is still down and still has not moved.
                // `onEnded` cancels this, but a timer already in flight when
                // the finger lifts would otherwise press a button nothing is
                // going to release.
                guard lastPoint != nil, travelled < Self.tapSlop else { return }
                holding = true
                link.hold()
            }
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private var drag: some Gesture {
        // `minimumDistance: 0` so a tap that never moves still reports, which is
        // the gesture a click is made of.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let previous = lastPoint else {
                    lastPoint = value.location
                    began = Date()
                    travelled = 0
                    startHoldTimer()
                    touchLocation = value.location
                    touchFade = 1.0
                    return
                }
                let dx = value.location.x - previous.x
                let dy = value.location.y - previous.y
                lastPoint = value.location
                travelled += abs(dx) + abs(dy)
                // A finger that has moved is no longer holding still, so it is
                // no longer on its way to becoming a hold.
                if travelled >= Self.tapSlop { cancelHoldTimer() }
                link.move(dx: Double(dx) * Self.gain, dy: Double(dy) * Self.gain)

                touchLocation = value.location
                touchFade = 1.0
            }
            .onEnded { _ in
                cancelHoldTimer()

                if holding {
                    // The drag ends by letting go, not by clicking.
                    holding = false
                    link.release()
                } else {
                    let quick = began.map {
                        Date().timeIntervalSince($0) < Self.tapDuration
                    } ?? false
                    // Both conditions: a finger resting on the glass for a
                    // second and lifting is someone changing their mind, not
                    // clicking.
                    if travelled < Self.tapSlop && quick {
                        let now = Date()
                        let double = lastTapEnded.map {
                            now.timeIntervalSince($0) < Self.doubleTapWindow
                        } ?? false
                        link.click(count: double ? 2 : 1)
                        // Cleared after a double, so three taps are a double and
                        // then a single rather than two overlapping doubles.
                        lastTapEnded = double ? nil : now
                    }
                }

                // Whatever the gesture turned out to be, it is over, and the
                // phone has no other way of knowing that — see
                // `WatchLink.endGesture`.
                link.endGesture()

                lastPoint = nil
                began = nil
                travelled = 0

                withAnimation(.easeOut(duration: 0.18)) {
                    touchFade = 0.0
                }
            }
    }
}
