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
