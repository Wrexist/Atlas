import SwiftUI
import UIKit

/// App typography ramp. All standard styles use `Font.system(_:design:weight:)`
/// with a TextStyle so they participate in Dynamic Type. The hero stat values
/// remain at fixed sizes — they're already very large and bumping them with
/// Larger Accessibility Sizes breaks layout in compact tiles. Treat them as
/// presentational glyphs, not body copy.
///
/// For the many one-off sizes the design calls for (badges, chips, dense row
/// labels), use `AppFont.scaled(_:weight:design:)` rather than a bare
/// `.font(.system(size:))` — see its documentation. A SwiftLint rule
/// (`fixed_font_size`) enforces this outside this file.
enum AppFont {
    static let largeTitle  = Font.system(.largeTitle,  design: .rounded, weight: .bold)
    static let title       = Font.system(.title,       design: .rounded, weight: .bold)
    static let title2      = Font.system(.title2,                        weight: .semibold)
    static let title3      = Font.system(.title3,                        weight: .semibold)
    static let headline    = Font.system(.headline,                      weight: .semibold)
    static let body        = Font.system(.body,                          weight: .regular)
    static let callout     = Font.system(.callout,                       weight: .regular)
    static let subheadline = Font.system(.subheadline,                   weight: .regular)
    static let footnote    = Font.system(.footnote,                      weight: .regular)
    static let caption     = Font.system(.caption2,                      weight: .regular)

    // Hero stats — fixed size on purpose. Use `@ScaledMetric` at the callsite
    // if you need them to scale within a specific layout.
    static let statValue      = Font.system(size: 48, weight: .bold, design: .rounded)
    static let statValueSmall = Font.system(size: 32, weight: .bold, design: .rounded)
    static let scoreLarge     = Font.system(size: 64, weight: .bold, design: .rounded)

    // Badges / chips — fixed sizes for dense iconography that would feel
    // oversized at the standard Dynamic Type ramp. Use sparingly and only
    // for tightly-constrained UI like count pills, status chips, and the
    // little flags inside list rows.
    static let badge          = Font.system(size: 11, weight: .bold)
    static let badgeSmall     = Font.system(size: 10, weight: .semibold)
    static let chipText       = Font.system(size: 12, weight: .semibold)

    /// Tiny heavy uppercase-style eyebrow label used above stats and in
    /// dense list rows. Fixed size so it stays a crisp glyph at the
    /// standard ramp.
    static let eyebrow        = Font.system(size: 11, weight: .heavy)
    /// Section/stat header that sits between `title2` and `statValueSmall`
    /// — used for the headline number on detail screens.
    static let statHeader     = Font.system(size: 28, weight: .bold, design: .rounded)

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
    /// composes inside `Text(…) + Text(…)` concatenations. The metrics are
    /// read during `body` evaluation, which SwiftUI re-runs when the
    /// content-size category changes, so the value stays current.
    ///
    /// - Parameter textStyle: the ramp the size scales *along*. The default
    ///   (`.body`) is right for labels and row copy; pass `.caption1` for
    ///   badges so they grow more gently, or `.title1` for display numbers.
    static func scaled(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: UIFont.TextStyle = .body
    ) -> Font {
        .system(
            size: UIFontMetrics(forTextStyle: textStyle).scaledValue(for: size),
            weight: weight,
            design: design
        )
    }
}
