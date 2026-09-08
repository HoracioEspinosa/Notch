import SwiftUI

/// Every number in this app's UI is measured off the Figma frame in
/// `docs/design/frame-124-hover-tooltip.png` (2000 x 2000 px), so the layout is
/// *proportionally* exact rather than eyeballed.
///
/// The frame fixes only ratios, never an absolute size, so one anchor picks the
/// scale: the design spec calls the provider ring 44pt across, and it measures
/// 117px in the frame. Move that anchor — which is all `size` does — and the
/// notch, its rings and its labels resize together, still in the design's
/// proportions.
///
/// One frame, two scales. Which one a measurement takes is a question about
/// what that measurement is *for*, not about where it happens to be drawn:
/// `px` and `fontSize` follow the setting, `readingPx` and `readingFontSize`
/// stay at the size the spec anchors. The reasoning is on `readingPx`.
enum Design {
    /// How big the notch is drawn, as chosen in Settings.
    ///
    /// Global mutable state, and knowingly so. Every measurement in the app
    /// reaches the scale through a `Design.px` or `Design.fontSize` call inside
    /// a static constant, and handing the scale down through SwiftUI's
    /// environment instead would mean turning all forty-odd of those constants
    /// into something a view can read — including the ones AppKit asks for to
    /// size the panel *before* SwiftUI has laid anything out, which have no
    /// environment to read from. One number, written from one place, is the far
    /// smaller price.
    ///
    /// Written by `NotchViewModel.size`, which is the only thing Settings
    /// drives; read by everything that draws.
    static var size: NotchSize = .standard

    /// Points per pixel of the design frame at the standard size — the ring's
    /// 44pt against its 117px in the frame.
    private static let standardScale: CGFloat = 44.0 / 117.0

    /// Points per pixel of the design frame.
    ///
    /// Computed on every read, and every constant derived from it likewise. A
    /// `static let` in Swift is evaluated once, at first access, and frozen for
    /// the life of the process — so a stored scale would hold whatever size the
    /// very first ring happened to be drawn at, and changing the setting would
    /// appear to do nothing until the app was restarted.
    static var scale: CGFloat { standardScale * size.scaleFactor }

    /// A distance measured in design-frame pixels, in points.
    static func px(_ pixels: CGFloat) -> CGFloat { pixels * scale }

    /// The same distance, held at the standard scale whatever the setting says.
    ///
    /// The notch is a signal rather than a document: a ring, an arc, a
    /// percentage taken in from across the desk without stopping. Nothing about
    /// it needs a particular size to do its job, so shrinking it costs only
    /// screen edge — which is the whole point of offering a smaller one.
    ///
    /// The hover card is the opposite. It is opened *in order to be read*, and
    /// its body copy is already the smallest type in the app: 18px of cap
    /// height in the frame, which lands at a 9.5pt face. Halve that and it is
    /// 4.7pt — still drawn, no longer legible, and a card nobody can read is a
    /// card with nothing left to offer. Shrinking the detail is not a smaller
    /// version of the feature; it is the feature switched off.
    ///
    /// So the card and everything welded to it — its padding, its rules, its
    /// type, its tail, and the gap the pointer crosses to reach it — is
    /// measured with these, and only the notch travels with the setting.
    static func readingPx(_ pixels: CGFloat) -> CGFloat { pixels * standardScale }

    /// Cap-height fraction of an em for SF Pro. Text in the frame can only be
    /// measured by its cap height, so this converts back to a point size.
    private static let capRatio: CGFloat = 0.714

    /// The point size whose capital letters are `pixels` tall in the frame.
    static func fontSize(capPixels pixels: CGFloat) -> CGFloat {
        px(pixels) / capRatio
    }

    /// The same point size, held at the standard scale — see `readingPx`.
    static func readingFontSize(capPixels pixels: CGFloat) -> CGFloat {
        readingPx(pixels) / capRatio
    }
}
