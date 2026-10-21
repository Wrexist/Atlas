import SwiftUI

/// An icon that is either an SF Symbol or one of the app's own template
/// glyphs in the asset catalog (the gym-equipment set under
/// `Assets.xcassets/Equipment`). Both tint with `foregroundStyle`, so a
/// caller can swap one for the other without restyling.
enum AppGlyph: Hashable, Sendable {
    case system(String)
    /// A template-rendered vector imageset drawn on a 24 pt grid with a
    /// 2 pt round stroke — the weight of an SF Symbol at medium.
    case asset(String)

    /// The bare image, for places that only accept an `Image` — menu
    /// and picker rows, which size it themselves.
    var image: Image {
        switch self {
        case .system(let name): return Image(systemName: name)
        case .asset(let name):  return Image(name)
        }
    }
}

/// Draws an `AppGlyph` at the point size an SF Symbol would get from
/// `AppFont.scaled(size, weight:)`. Asset glyphs have no font to follow,
/// so they take a square frame scaled by the same Dynamic Type metric.
struct GlyphImage: View {
    let glyph: AppGlyph
    var size: CGFloat = 11
    var weight: Font.Weight = .semibold

    /// An SF Symbol's ink runs wider than its point size; the custom
    /// glyphs fill their whole 24 pt box, so they get the same headroom.
    private static let assetScale: CGFloat = 1.35

    var body: some View {
        switch glyph {
        case .system(let name):
            Image(systemName: name)
                .font(AppFont.scaled(size, weight: weight))
        case .asset(let name):
            let side = UIFontMetrics(forTextStyle: .body).scaledValue(for: size * Self.assetScale)
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
        }
    }
}
