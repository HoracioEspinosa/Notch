import SwiftUI

/// Sizes are derived from cap heights measured in the design frame, so they
/// track the scale they are asked for — which is why each one is computed on
/// read rather than stored. A stored face would be built once, at whatever size
/// the first label happened to want, and would then go on being that size after
/// the notch had been resized around it.
///
/// Which scale each face takes is the split `Design.readingPx` explains: the
/// percent is a glanceable signal on the notch and travels with it, while the
/// card's two faces exist to be read and stay where the spec anchors them.
enum Typography {
    /// The percent under each provider ring. Cap height 27px in the frame.
    static var percent: Font {
        Font.system(size: Design.fontSize(capPixels: 27), weight: .semibold)
    }

    /// "Claude Usage". Cap height 26px.
    static var cardTitle: Font {
        Font.system(size: Design.readingFontSize(capPixels: 26), weight: .semibold)
    }

    /// "Current session", "73% Used", "Resets in 51 min". Cap height 18px.
    static var cardBody: Font {
        Font.system(size: Design.readingFontSize(capPixels: 18), weight: .regular)
    }
}
