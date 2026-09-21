import SwiftUI

/// The phone app's palette, written out again for watchOS.
///
/// Duplicated on purpose, and for the same reason the desktop app duplicates
/// it: the values live in `apps/mobile/lib/src/app/theme.dart`, that file is
/// Dart, and nothing here can import it. The palette is the thing that has to
/// match, so it is written out identically rather than approximated — a watch
/// face that is nearly the app's navy reads as a different product on the
/// wrist than the one in the pocket.
///
/// Only the dark scheme is carried across. The watch is used at a glance, in
/// the dark, on an OLED panel where black costs nothing, and watchOS itself has
/// no light mode to follow.
enum Theme {
    /// `_darkCanvas` — the page behind everything.
    static let canvas = Color(hex: 0x06080C)

    /// `surfaceContainerHigh` — the top of the trackpad's gradient.
    static let surfaceHigh = Color(hex: 0x1B222E)

    /// `surfaceContainerLowest` — the bottom of it.
    static let surfaceLowest = Color(hex: 0x05070B)

    /// `surfaceContainerLow` — the click buttons at rest.
    static let surfaceLow = Color(hex: 0x11161F)

    /// `onSurface` — body text.
    static let onSurface = Color(hex: 0xE7ECF5)

    /// `onSurfaceVariant` — secondary text and the resting dot lattice.
    static let onSurfaceVariant = Color(hex: 0xB3BDCE)

    /// `primary` — the accent, and the colour the touch glow is drawn in.
    static let primary = Color(hex: 0xB6C8E6)

    /// Dynamic touch dot swelling — #007ACC blue matching the phone.
    static let dotGlow = Color(hex: 0x007ACC)

    /// `outlineVariant` — hairlines.
    static let outlineVariant = Color(hex: 0x39435A)

    /// The connected dot. The same green the phone's app bar uses, which is not
    /// a Material role — Material 3 has no "this is live" colour, so both apps
    /// name the literal.
    static let live = Color(hex: 0x3DD68C)

    /// Amber for the states between connected and not.
    static let pending = Color(hex: 0x9FC2E8)

    /// `error`.
    static let error = Color(hex: 0xF2B8B5)
}

extension Color {
    /// Builds a colour from the same `0xRRGGBB` literals the Dart theme uses,
    /// so the two files can be diffed against each other by eye.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
