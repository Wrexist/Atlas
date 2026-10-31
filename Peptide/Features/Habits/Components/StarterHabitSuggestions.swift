import SwiftUI

/// A curated habit the user can create in one tap from an empty state, so
/// the first win (and first streak) is seconds away instead of a trip
/// through the full editor. Icons + tints are drawn from
/// `HabitIconCatalog` / `HabitTintCatalog` so a starter habit opens
/// cleanly in the editor afterward.
struct HabitTemplate: Identifiable {
    let id = UUID()
    let name: String
    let iconSymbol: String
    let tintHex: UInt32
    let targetValue: Int?
    let category: HabitCategory

    /// Builds the habit; `sortIndex` 0 lets `DataStore.addHabit` append it
    /// to the bottom.
    func makeHabit() -> Habit {
        Habit(
            name: name,
            iconSymbol: iconSymbol,
            tintHex: tintHex,
            schedule: .daily,
            targetValue: targetValue,
            category: category
        )
    }

    static let starters: [HabitTemplate] = [
        HabitTemplate(name: String(localized: "Drink water"), iconSymbol: "drop.fill", tintHex: 0x6B8AFF, targetValue: 8, category: .health),
        HabitTemplate(name: String(localized: "10-min walk"), iconSymbol: "shoeprints.fill", tintHex: 0x5BC489, targetValue: nil, category: .fitness),
        HabitTemplate(name: String(localized: "Read"), iconSymbol: "book.fill", tintHex: 0xC59FFF, targetValue: nil, category: .learning),
        HabitTemplate(name: String(localized: "Stretch"), iconSymbol: "figure.cooldown", tintHex: 0x4CB8C4, targetValue: nil, category: .fitness),
        HabitTemplate(name: String(localized: "Meditate"), iconSymbol: "leaf.fill", tintHex: 0x9B72CF, targetValue: nil, category: .mindfulness),
        HabitTemplate(name: String(localized: "Vitamins"), iconSymbol: "pills.fill", tintHex: 0xD4A844, targetValue: nil, category: .health),
    ]
}

/// Horizontal row of one-tap "quick start" habit chips for the habits
/// empty state. Presentational — the parent supplies `onPick` (which
/// creates the habit via `DataStore.addHabit`).
struct StarterHabitSuggestions: View {
    var templates: [HabitTemplate] = HabitTemplate.starters
    let onPick: (HabitTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Quick start")
                .font(AppFont.eyebrow)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(AppColor.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(templates) { template in
                        chip(template)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func chip(_ template: HabitTemplate) -> some View {
        Button {
            AppAnimation.with(AppAnimation.springSnappy) { onPick(template) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: template.iconSymbol)
                    .font(AppFont.scaled(11, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityHidden(true)
                Text(template.name)
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
                Image(systemName: "plus")
                    .font(AppFont.scaled(11, weight: .medium))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 8)
            .glassSurfaceCapsule()
            .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.95))
        .accessibilityLabel("Add habit: \(template.name)")
    }
}
