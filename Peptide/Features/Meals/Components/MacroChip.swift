import SwiftUI

/// Compact grams read-out for one macro, tinted with the canonical macro
/// colour. The icon (drumstick / wheat / avocado) keeps the chips telling
/// apart for anyone who can't separate the tints, in any language.
struct MacroChip: View {
    let icon: NutrientIcon
    let name: String
    let grams: Int
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.xs) {
            NutrientIconView(icon: icon, size: 11)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text("\(grams) g")
                .font(AppFont.scaled(11, weight: .semibold, relativeTo: .caption1))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(grams) grams \(name)"))
    }
}

extension MacroChip {
    static func protein(_ grams: Int) -> MacroChip {
        MacroChip(icon: .macro(.protein), name: String(localized: "protein"), grams: grams, tint: AppColor.macroProtein)
    }

    static func carbs(_ grams: Int) -> MacroChip {
        MacroChip(icon: .macro(.carbs), name: String(localized: "carbs"), grams: grams, tint: AppColor.macroCarbs)
    }

    static func fat(_ grams: Int) -> MacroChip {
        MacroChip(icon: .macro(.fat), name: String(localized: "fat"), grams: grams, tint: AppColor.macroFat)
    }
}

/// A nutrient's icon: the drawn glyph for the three macros, an SF Symbol
/// for everything else (fibre, kcal, time).
enum NutrientIcon {
    case macro(MacroKind)
    case symbol(String)
}

/// Draws a `NutrientIcon` to sit beside `size`-point text. The macro
/// glyphs fill their whole frame, so they get one point more to match a
/// symbol's optical size.
struct NutrientIconView: View {
    let icon: NutrientIcon
    let size: CGFloat

    var body: some View {
        switch icon {
        case .macro(let kind):
            MacroIcon(kind, size: size + 1)
        case .symbol(let name):
            Image(systemName: name)
                .font(AppFont.scaled(size, weight: .semibold, relativeTo: .caption1))
                .accessibilityHidden(true)
        }
    }
}
