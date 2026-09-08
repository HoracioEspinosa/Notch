import Foundation

/// How big the notch is drawn.
///
/// Not a second layout, and deliberately not one: both sizes are the *same*
/// design frame read at a different number of points per pixel. The frame fixes
/// ratios and never an absolute size, so moving the anchor moves the body, the
/// rings and their labels together — the shape stays the shape, it just claims
/// less of the screen.
///
/// Which is why this is one multiplier rather than a set of compact
/// measurements: a hand-tuned small variant would be a second design to keep in
/// step with the first, and the first is measured off a 2000px frame.
///
/// The hover card is outside all of this. It is measured with
/// `Design.readingPx`, which ignores the setting, for the reason set out there.
enum NotchSize: String, CaseIterable, Identifiable {
    /// What the design spec anchors: a 44pt provider ring.
    case standard
    /// Half of that, for an edge that has other things to do.
    case compact

    var id: String { rawValue }

    /// What `.compact` multiplies the design scale by.
    ///
    /// Exactly half. Kept as one named number because it is the single figure
    /// in this feature anyone is likely to want to move: it can only honestly
    /// be judged on a screen, and the whole notch travels with it.
    static let compactFactor: CGFloat = 0.5

    /// Points per design-frame pixel, against the standard size.
    var scaleFactor: CGFloat {
        switch self {
        case .standard: return 1
        case .compact:  return Self.compactFactor
        }
    }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .compact:  return "Compact"
        }
    }

    var explanation: String {
        switch self {
        case .standard:
            return "The notch at its designed size, with room for the readings "
                 + "to be read at a glance."
        case .compact:
            return "Half as large, in the same proportions — a smaller thing to "
                 + "aim at and less of the screen edge spent. The hover card "
                 + "keeps its full size, so the detail still reads."
        }
    }
}
