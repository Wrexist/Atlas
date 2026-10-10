import SwiftUI

/// Compact grams read-out for one macro, tinted with the canonical macro
/// colour. The lettered glyph (P / C / F) keeps the chips telling apart
/// for anyone who can't separate the tints.
struct MacroChip: View {
    let symbol: String
    let grams: Int
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(AppFont.scaled(11, weight: .semibold, relativeTo: .caption1))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text("\(grams) g")
                .font(AppFont.scaled(11, weight: .semibold, relativeTo: .caption1))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

extension MacroChip {
    static func protein(_ grams: Int) -> MacroChip {
        MacroChip(symbol: "p.circle.fill", grams: grams, tint: AppColor.macroProtein)
    }

    static func carbs(_ grams: Int) -> MacroChip {
        MacroChip(symbol: "c.circle.fill", grams: grams, tint: AppColor.macroCarbs)
    }

    static func fat(_ grams: Int) -> MacroChip {
        MacroChip(symbol: "f.circle.fill", grams: grams, tint: AppColor.macroFat)
    }
}
