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
    let schedule: HabitSchedule = .daily

    /// Builds the habit; `sortIndex` 0 lets `DataStore.addHabit` append it
    /// to the bottom.
    func makeHabit() -> Habit {
        Habit(
            name: name,
            iconSymbol: iconSymbol,
            tintHex: tintHex,
            schedule: schedule,
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
                HStack(spacing: Spacing.chipSpacing) {
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
            HStack(spacing: Spacing.xs) {
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
            .padding(.vertical, Spacing.sm)
            .glassSurfaceCapsule()
            .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.95))
        .accessibilityLabel("Add habit: \(template.name)")
    }
}

/// Vertical "quick start" list for the Habits tab's empty state: one row per
/// starter with its schedule and an add glyph, so every option is visible
/// without a sideways scroll. Presentational — the parent supplies `onPick`.
struct StarterHabitList: View {
    /// Five rows fill the empty tab without scrolling; the supplement starter
    /// stays one tap in, in the editor.
    var templates: [HabitTemplate] = Array(HabitTemplate.starters.prefix(5))
    let onPick: (HabitTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Quick start")
                .font(AppFont.eyebrow)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(AppColor.textTertiary)
                .padding(.leading, Spacing.xs)

            VStack(spacing: 0) {
                ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                    if index > 0 {
                        Divider()
                            .overlay(AppColor.glassBorder)
                            .padding(.leading, Spacing.cardPadding)
                    }
                    row(template)
                }
            }
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
    }

    private func row(_ template: HabitTemplate) -> some View {
        Button {
            AppAnimation.with(AppAnimation.springSnappy) { onPick(template) }
        } label: {
            HStack(spacing: Spacing.md) {
                IconTile(template.iconSymbol)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(template.name)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(template.schedule.displayName)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: "plus.circle.fill")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.vertical, Spacing.md)
            .contentShape(.rect)
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("Add habit: \(template.name)")
    }
}

/// A ghosted week of habit rings shown before the first habit exists — a
/// preview of what checking in fills. Today's ring carries the accent so the
/// strip reads as "this week starts now". Decorative.
struct HabitWeekPreview: View {
    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        let letters = Array(symbols[offset...]) + Array(symbols[..<offset])
        let todayIndex = (calendar.component(.weekday, from: .now) - calendar.firstWeekday + 7) % 7

        HStack(spacing: 0) {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                let isToday = index == todayIndex
                VStack(spacing: Spacing.xs) {
                    Circle()
                        .strokeBorder(isToday ? AppColor.accentPrimary : AppColor.glassBorder, lineWidth: 3)
                        .frame(width: 32, height: 32)
                    Text(letter)
                        .font(AppFont.caption2)
                        .foregroundStyle(isToday ? AppColor.textPrimary : AppColor.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}
