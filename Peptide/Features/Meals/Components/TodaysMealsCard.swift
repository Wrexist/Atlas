import SwiftUI

/// Per-meal log shown under the macro rings on the Lifestyle tab.
/// Renders the day's `MealEntry` rows grouped under Breakfast, Lunch,
/// Dinner and Snack, each with its calorie subtotal, in the order eaten.
/// Tap a row to edit it; long-press for Edit, Log again and Delete.
///
/// Fills the visibility gap the auto-close success screens leave —
/// once those dismiss, users had no way to see (or fix) what got
/// logged. This card is the canonical "what did I eat today" surface.
struct TodaysMealsCard: View {
    let entries: [MealEntry]
    /// Name of the day being shown when it isn't today ("Yesterday",
    /// "Mon, Sep 21"); nil keeps the "Today's meals" heading.
    var dayTitle: String? = nil
    let onEdit: (MealEntry) -> Void
    let onLogAgain: (MealEntry) -> Void
    let onDelete: (UUID) -> Void

    @State private var pendingDelete: MealEntry?

    var body: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                if entries.isEmpty {
                    emptyState
                } else {
                    rows
                }
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { entry in
            Button("Delete \(entry.name)", role: .destructive) {
                onDelete(entry.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { entry in
            Text("Subtracts \(entry.calories) kcal from that day's totals.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(dayTitle.map { String(localized: "Meals · \($0)") } ?? String(localized: "Today's meals"))
                    .font(AppFont.eyebrow)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight)
                Text(entries.isEmpty ? LocalizedStringKey("Nothing logged yet") : "^[\(entries.count) entry](inflect: true)")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "fork.knife.circle")
                .font(AppFont.scaled(24, weight: .light))
                .foregroundStyle(AppColor.textSecondary)
            Text("Log a meal to see it here. Tap any entry afterwards to edit or remove it.")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.sm)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(MealDiarySection.sections(of: entries)) { section in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    sectionHeader(section)
                    ForEach(section.entries) { entry in
                        MealEntryRow(entry: entry) {
                            onEdit(entry)
                        } onLogAgain: {
                            onLogAgain(entry)
                        } onDelete: {
                            pendingDelete = entry
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                    }
                }
                .transition(.opacity)
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: entries.map(\.id))
    }

    /// Names the meal and what it added up to, so the diary reads the
    /// way the day went instead of as one undivided list.
    private func sectionHeader(_ section: MealDiarySection) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: section.category.icon)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(section.category.tint)
                .accessibilityHidden(true)
            Text(section.category.displayName)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 0)
            Text("\(section.calories) kcal")
                .font(AppFont.scaled(11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppColor.textSecondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One meal of the day in the diary: its category and the entries
/// logged under it.
struct MealDiarySection: Identifiable {
    let category: MealCategory
    let entries: [MealEntry]

    var id: MealCategory { category }
    var calories: Int { entries.reduce(0) { $0 + $1.calories } }

    /// Breakfast through snack, each meal's entries oldest first, with
    /// meals that have nothing logged left out.
    static func sections(of entries: [MealEntry]) -> [MealDiarySection] {
        MealCategory.allCases.compactMap { category in
            let logged = entries
                .filter { $0.category == category }
                .sorted { $0.date < $1.date }
            return logged.isEmpty ? nil : MealDiarySection(category: category, entries: logged)
        }
    }
}

/// Single-row read-out for a `MealEntry`. Compact enough for the
/// stack on the Lifestyle tab without becoming a separate detail
/// screen. Long-press surfaces Edit, Log again and Delete.
struct MealEntryRow: View {
    let entry: MealEntry
    let onTap: () -> Void
    let onLogAgain: () -> Void
    let onDelete: () -> Void

    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 44

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                // `MealEntry` stores no photo, so the row leads with the
                // picture its name points to.
                FoodThumbnail(name: entry.name, size: tileSize)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(entry.name)
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(entry.calories) kcal")
                            .font(AppFont.scaled(13, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textPrimary)
                            .fixedSize()
                    }
                    HStack(spacing: Spacing.xs) {
                        // The section header names the meal, so the row
                        // keeps only how and when it was logged.
                        Image(systemName: entry.source.icon)
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                        Text(entry.date, format: .dateTime.hour().minute())
                            .font(AppFont.scaled(11))
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    // At large Dynamic Type sizes three chips overflow one
                    // line; stack them rather than truncating the grams.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.xs) { macroChips }
                        VStack(alignment: .leading, spacing: Spacing.xs) { macroChips }
                    }
                }
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.35))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            // `.swipeActions` is list-only; a context menu works in
            // any container and matches the long-press pattern users
            // already know from elsewhere in the app (My Foods rows
            // in the food library use the same affordance).
            Button {
                onTap()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: onLogAgain) {
                Label("Log again", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: entry))
        .accessibilityHint("Opens the entry to edit or delete it.")
        .accessibilityAction(named: Text("Log again"), onLogAgain)
        .accessibilityAction(named: Text("Delete"), onDelete)
    }

    @ViewBuilder
    private var macroChips: some View {
        MacroChip.protein(entry.proteinG)
        MacroChip.carbs(entry.carbsG)
        MacroChip.fat(entry.fatG)
    }

    private static func accessibilityLabel(for entry: MealEntry) -> String {
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        return String(
            localized: "\(entry.name), \(entry.category.displayName) at \(time), \(entry.calories) kilocalories, \(entry.proteinG) grams protein, \(entry.carbsG) grams carbohydrate, \(entry.fatG) grams fat",
            comment: "VoiceOver readout for one meal entry in Today's meals list."
        )
    }
}
