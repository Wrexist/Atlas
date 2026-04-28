import SwiftUI

/// App typography ramp. All standard styles use `Font.system(_:design:weight:)`
/// with a TextStyle so they participate in Dynamic Type. The hero stat values
/// remain at fixed sizes — they're already very large and bumping them with
/// Larger Accessibility Sizes breaks layout in compact tiles. Treat them as
/// presentational glyphs, not body copy.
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
}
