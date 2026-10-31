import SwiftUI

/// The app's one icon container: a small raised key with a monochrome
/// glyph. Lit from the top, with a bright upper rim and a tight contact
/// shadow, so it reads as a 2.5D object sitting on the card.
///
/// Icons are ink, never a per-feature colour. A screen full of coloured
/// glyphs on pastel squares is what makes an app look assembled rather
/// than designed; colour is kept for data and for the one primary action,
/// which takes the `.accent` style.
struct IconTile: View {
    enum Style {
        /// Neutral raised key with an ink glyph. The default.
        case neutral
        /// Filled with the theme accent, white glyph. One per screen at
        /// most: the thing the user most likely came to do.
        case accent
    }

    enum Silhouette {
        case rounded, circle
    }

    let glyph: AppGlyph
    var size: CGFloat = 40
    var style: Style = .neutral
    var silhouette: Silhouette = .rounded

    init(_ systemName: String, size: CGFloat = 40, style: Style = .neutral, silhouette: Silhouette = .rounded) {
        self.init(glyph: .system(systemName), size: size, style: style, silhouette: silhouette)
    }

    init(glyph: AppGlyph, size: CGFloat = 40, style: Style = .neutral, silhouette: Silhouette = .rounded) {
        self.glyph = glyph
        self.size = size
        self.style = style
        self.silhouette = silhouette
    }

    var body: some View {
        GlyphImage(glyph: glyph, size: size * 0.4, weight: .medium)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(style == .accent ? AppColor.onAccent : AppColor.textPrimary)
            .frame(width: size, height: size)
            .background { face }
            .accessibilityHidden(true)
    }

    private var shape: AnyShape {
        switch silhouette {
        case .rounded: AnyShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        case .circle: AnyShape(Circle())
        }
    }

    private var faceColors: [Color] {
        switch style {
        case .neutral: [AppColor.tileTop, AppColor.tileBottom]
        case .accent: [AppColor.accentPrimary, AppColor.accentFill]
        }
    }

    private var face: some View {
        shape
            .fill(LinearGradient(colors: faceColors, startPoint: .top, endPoint: .bottom))
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [AppColor.cardRim.opacity(style == .accent ? 0.5 : 1), .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
                .clipShape(shape)
            }
            .overlay { shape.stroke(AppColor.paperEdge, lineWidth: 0.5) }
            .appShadow(AppShadow.tileContact)
            .appShadow(style == .accent ? AppShadow.accentTile : AppShadow.tileDrop)
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        HStack(spacing: Spacing.md) {
            IconTile("magnifyingglass")
            IconTile("barcode.viewfinder")
            IconTile("camera", style: .accent)
            IconTile("figure.run", silhouette: .circle)
        }
        .padding(Spacing.lg)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }
    .padding(Spacing.lg)
    .pageBackground()
}
