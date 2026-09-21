import SwiftUI

/// The trackpad's surface: a fixed lattice of dots.
///
/// Deliberately takes no input at all. Nothing about this view changes while a
/// finger is on the glass, so SwiftUI re-renders it exactly never, and
/// `drawingGroup()` rasterises it once into an offscreen buffer that is then
/// simply composited. That is the whole design: while a finger is down, the
/// watch's main thread does nothing but read the touch and hand movement to
/// WatchConnectivity, because latency is what this app is for.
///
/// The lattice is not decoration. A blank rectangle gives a finger nothing to
/// judge movement against, and on a watch the user is looking at the *computer*,
/// not the wrist — so the one moment they do glance down, the dots and the glow
/// are what say the surface registered anything.
struct DotField: View {
    /// Distance between dot centres. Tighter than the phone's 22pt: the widest
    /// watch is 205pt across, and at the phone's spacing the field would be
    /// nine dots wide and read as a chequerboard rather than a texture.
    private static let spacing: CGFloat = 14
    private static let dotDiameter: CGFloat = 2.0

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let columns = Int(size.width / Self.spacing)
            let rows = Int(size.height / Self.spacing)
            guard columns > 0, rows > 0 else { return }

            // Centred, so the margins match on both sides at any width.
            let originX = (size.width - CGFloat(columns - 1) * Self.spacing) / 2
            let originY = (size.height - CGFloat(rows - 1) * Self.spacing) / 2
            let ink = GraphicsContext.Shading.color(Theme.onSurfaceVariant.opacity(0.22))

            for row in 0..<rows {
                for column in 0..<columns {
                    let rect = CGRect(
                        x: originX + CGFloat(column) * Self.spacing - Self.dotDiameter / 2,
                        y: originY + CGFloat(row) * Self.spacing - Self.dotDiameter / 2,
                        width: Self.dotDiameter,
                        height: Self.dotDiameter
                    )
                    context.fill(Path(ellipseIn: rect), with: ink)
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// Dynamic touch-reactive swelling dots around the active swipe point on the watch.
///
/// Mimics the mobile app's touch feedback: dots swell smoothly up to peak radius
/// in #007ACC blue with organic smoothstep falloff, fading out on release.
/// Only iterates over dots within the proximity bounding box for 60fps responsiveness.
struct DynamicTouchDotField: View {
    let touchLocation: CGPoint?
    let fade: Double

    private static let spacing: CGFloat = 14
    private static let baseRadius: CGFloat = 1.0
    private static let maxRadius: CGFloat = 5.5
    private static let glowRadius: CGFloat = 90.0
    private static let glowRadiusSq: CGFloat = glowRadius * glowRadius

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard let touch = touchLocation, fade > 0.001 else { return }

            let columns = Int(size.width / Self.spacing)
            let rows = Int(size.height / Self.spacing)
            guard columns > 0, rows > 0 else { return }

            let originX = (size.width - CGFloat(columns - 1) * Self.spacing) / 2
            let originY = (size.height - CGFloat(rows - 1) * Self.spacing) / 2

            // Bounding box of columns and rows within glowRadius of the touch
            let minCol = max(0, Int(floor(((touch.x - Self.glowRadius) - originX) / Self.spacing)))
            let maxCol = min(columns - 1, Int(ceil(((touch.x + Self.glowRadius) - originX) / Self.spacing)))
            let minRow = max(0, Int(floor(((touch.y - Self.glowRadius) - originY) / Self.spacing)))
            let maxRow = min(rows - 1, Int(ceil(((touch.y + Self.glowRadius) - originY) / Self.spacing)))

            guard maxCol >= minCol, maxRow >= minRow else { return }

            for row in minRow...maxRow {
                let dotY = originY + CGFloat(row) * Self.spacing
                for col in minCol...maxCol {
                    let dotX = originX + CGFloat(col) * Self.spacing

                    let dx = dotX - touch.x
                    let dy = dotY - touch.y
                    let distSq = dx * dx + dy * dy
                    if distSq < Self.glowRadiusSq {
                        let dist = sqrt(distSq)
                        let t = 1.0 - (dist / Self.glowRadius)
                        if t > 0.001 {
                            // Smoothstep curve for natural organic falloff
                            let curve = t * t * (3.0 - 2.0 * t)
                            // Swells from resting radius (1.0) up to peak rounded radius (5.5)
                            let radius = Self.baseRadius + (Self.maxRadius - Self.baseRadius) * curve
                            let alpha = min(1.0, 0.95 * curve * fade)

                            let rect = CGRect(
                                x: dotX - radius,
                                y: dotY - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                            context.fill(Path(ellipseIn: rect), with: .color(Theme.dotGlow.opacity(alpha)))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
