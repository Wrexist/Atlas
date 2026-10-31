import SwiftUI
import UIKit

/// App typography ramp. All standard styles use `Font.system(_:design:weight:)`
/// with a TextStyle so they participate in Dynamic Type. The design-specific
/// sizes below the ramp (badges, chips, eyebrows, hero stats) route through
/// `scaled(_:weight:design:relativeTo:)`, so they render at their designed
/// point size at the default content size and grow with the user's setting.
///
/// For the many one-off sizes the design calls for (badges, chips, dense row
/// labels), use `AppFont.scaled(_:weight:design:)` rather than a bare
/// `.font(.system(size:))` — see its documentation. A SwiftLint rule
/// (`fixed_font_size`) enforces this outside this file.
enum AppFont {
    /// The body type scale — six steps, and nothing between them.
    ///
    /// The app had *thirty* distinct point sizes, thirteen of them inside a
    /// 12pt band. That's not a scale, it's thirty separate decisions, and it
    /// is the single loudest tell that a UI was assembled rather than
    /// designed: at 11 vs 12 vs 13pt nobody can see the difference, but the
    /// inconsistency is felt everywhere.
    ///
    /// Hierarchy below `heading` should come from **weight and colour first,
    /// size second** — that's why `badge`, `badgeSmall` and `eyebrow` are all
    /// one size at three weights.
    ///
    /// Above `heading` are display glyphs — the one big number a screen is
    /// about. Those are sized per screen on purpose and aren't part of this
    /// scale.
    enum Scale {
        /// Dense superscripts and count flags.
        static let micro: CGFloat = 8
        /// Pills, status chips, uppercase eyebrows.
        static let badge: CGFloat = 11
        /// Secondary row copy, captions, metadata.
        static let caption: CGFloat = 13
        /// Default reading size for labels and row titles.
        static let body: CGFloat = 16
        /// Card titles and section headers.
        static let title: CGFloat = 20
        /// The largest non-display size.
        static let heading: CGFloat = 24

        static let all: [CGFloat] = [micro, badge, caption, body, title, heading]
    }

    static let largeTitle  = Font.system(.largeTitle,  design: .rounded, weight: .bold)
    static let title       = Font.system(.title,       design: .rounded, weight: .bold)
    static let title2      = Font.system(.title2,                        weight: .semibold)
    static let title3      = Font.system(.title3,                        weight: .semibold)
    static let headline    = Font.system(.headline,                      weight: .semibold)
    static let body        = Font.system(.body,                          weight: .regular)
    static let callout     = Font.system(.callout,                       weight: .regular)
    static let subheadline = Font.system(.subheadline,                   weight: .regular)
    static let footnote    = Font.system(.footnote,                      weight: .regular)
    static let caption2    = Font.system(.caption2,                      weight: .regular)

    /// The bold rounded title under each Today section's eyebrow.
    static let sectionTitle = Font.system(.title2, design: .rounded, weight: .bold)

    // Hero stats. Computed so they re-read the content-size category on each
    // `body` pass; scaled along `.largeTitle`, whose ramp grows gently.
    //
    // Light, not bold: at display size a thin numeral is what reads as
    // calm and premium (Health, Xeyo); a heavy rounded one reads as a
    // game score. Size carries the emphasis, so the weight doesn't have to.
    static var statValue: Font      { scaled(52, weight: .light, relativeTo: .largeTitle) }
    static var statValueSmall: Font { scaled(34, weight: .light, relativeTo: .largeTitle) }

    // Badges / chips for dense UI like count pills, status chips, and the
    // little flags inside list rows. Scaled along `.caption1` so they grow
    // more gently than body copy.
    //
    // These were 10 / 11 / 12pt, which is three sizes nobody can tell apart
    // and one more reason the app carried thirty of them. They're one size
    // now; the distinction they were reaching for is weight, which is the
    // cheaper axis anyway.
    static var badge: Font      { scaled(Scale.badge, weight: .bold, relativeTo: .caption1) }
    static var badgeSmall: Font { scaled(Scale.badge, weight: .semibold, relativeTo: .caption1) }
    static var chipText: Font   { scaled(Scale.caption, weight: .semibold, relativeTo: .caption1) }

    /// Tiny heavy uppercase-style eyebrow label used above stats and in
    /// dense list rows.
    static var eyebrow: Font    { scaled(Scale.badge, weight: .heavy, relativeTo: .caption1) }
    /// Section/stat header that sits between `title2` and `statValueSmall`
    /// — used for the headline number on detail screens.
    static var statHeader: Font { scaled(28, weight: .regular, relativeTo: .title1) }

    /// A system font at `size`, scaled for the user's Dynamic Type setting.
    ///
    /// `Font.system(size:)` is *fixed* — it ignores the content-size category
    /// entirely, which is why ~800 call sites across the app used to be
    /// invisible to low-vision users. This routes the point size through
    /// `UIFontMetrics` first, so 13pt becomes 13pt at the default setting and
    /// grows from there, while every call site keeps the exact size the design
    /// specifies.
    ///
    /// It returns a `Font` rather than applying a `ViewModifier` so it still
    /// composes inside `Text(…) + Text(…)` concatenations. The trade-off: by
    /// default the metrics come from UIKit's current trait collection, not
    /// the SwiftUI environment, so a `.dynamicTypeSize(...)` clamp has no
    /// effect on it and a view that never reads the environment can keep a
    /// stale size until it rebuilds. A view that clamps, or must track
    /// changes live, reads `@Environment(\.dynamicTypeSize)` and passes it
    /// as `dynamicTypeSize`.
    ///
    /// - Parameter textStyle: the ramp the size scales *along*. The default
    ///   (`.body`) is right for labels and row copy; pass `.caption1` for
    ///   badges so they grow more gently, or `.title1` for display numbers.
    /// - Parameter dynamicTypeSize: the size to scale for; `nil` reads
    ///   UIKit's current content-size category.
    static func scaled(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: UIFont.TextStyle = .body,
        in dynamicTypeSize: DynamicTypeSize? = nil
    ) -> Font {
        let pointSize = scaledValue(size, relativeTo: textStyle, in: dynamicTypeSize)
        return .system(size: pointSize, weight: weight, design: design)
    }

    /// `value` scaled exactly as `scaled(_:)` scales a point size, for a
    /// frame that has to grow with the glyph inside it (an icon tile, a
    /// selection circle). Pass the same `textStyle` and `dynamicTypeSize`
    /// as the glyph's font so the two stay in proportion.
    static func scaledValue(
        _ value: CGFloat,
        relativeTo textStyle: UIFont.TextStyle = .body,
        in dynamicTypeSize: DynamicTypeSize? = nil
    ) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        guard let dynamicTypeSize else { return metrics.scaledValue(for: value) }
        return metrics.scaledValue(
            for: value,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        )
    }
}
