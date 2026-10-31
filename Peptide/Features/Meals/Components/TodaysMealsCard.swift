import SwiftUI

/// Per-meal log shown under the macro rings on the Lifestyle tab.
/// Renders the day's `MealEntry` rows grouped under Breakfast, Lunch,
/// Dinner and Snack, each with its calorie subtotal, in the order eaten.
/// Tap a row to edit it; long-press for Edit, Log again and Delete.
/// A meal the previous day had and this day lacks offers a one-tap
/// copy; each meal's menu (and the header's, for the whole day) can
/// copy from any other day.
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
    /// Meals logged on the day before the viewed one. Each of them that
    /// this day lacks offers a one-tap copy.
    var previousDayCategories: Set<MealCategory> = []
    /// Mid-sentence name of that previous day: "yesterday", "Mon, Sep 21".
    var previousDayName: String = ""
    /// Copies one meal (or the whole day when nil) from the previous day.
    var onCopyFromPreviousDay: (MealCategory?) -> Void = { _ in }
    /// Opens the day picker to copy one meal (or the whole day when nil).
    var onCopyFromAnotherDay: (MealCategory?) -> Void = { _ in }

    @State private var pendingDelete: MealEntry?

    var body: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                if entries.isEmpty {
                    emptyState
                }
                if !entries.isEmpty || !previousDayCategories.isEmpty {
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
            copyMenu(for: nil)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
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
            if !previousDayCategories.isEmpty {
                Button {
                    onCopyFromPreviousDay(nil)
                } label: {
                    Label(String(localized: "Copy all meals from \(previousDayName)"), systemImage: "doc.on.doc")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    /// Logged meals in breakfast-to-snack order, with a copy offer in
    /// the slot of each meal the previous day had and this day lacks.
    private var rows: some View {
        let sections = MealDiarySection.sections(of: entries)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(MealCategory.allCases, id: \.self) { category in
                if let section = sections.first(where: { $0.category == category }) {
                    loggedSection(section)
                } else if previousDayCategories.contains(category) {
                    copySuggestion(category)
                        .transition(.opacity)
                }
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: entries.map(\.id))
    }

    private func loggedSection(_ section: MealDiarySection) -> some View {
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

    /// Names the meal and what it added up to, so the diary reads the
    /// way the day went instead of as one undivided list.
    private func sectionHeader(_ section: MealDiarySection) -> some View {
        HStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                categoryLabel(section.category)
                Spacer(minLength: 0)
                Text("\(section.calories) kcal")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textSecondary)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            copyMenu(for: section.category)
        }
        .padding(.horizontal, Spacing.xs)
    }

    /// An empty meal slot the previous day filled: one tap copies it.
    private func copySuggestion(_ category: MealCategory) -> some View {
        HStack(spacing: Spacing.xs) {
            categoryLabel(category)
                .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button {
                onCopyFromPreviousDay(category)
            } label: {
                Label(String(localized: "Copy from \(previousDayName)"), systemImage: "doc.on.doc")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
            copyMenu(for: category)
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func categoryLabel(_ category: MealCategory) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: category.icon)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(category.tint)
                .accessibilityHidden(true)
            Text(category.displayName)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    /// Copy options for one meal, or for the whole day when `category`
    /// is nil.
    private func copyMenu(for category: MealCategory?) -> some View {
        Menu {
            if category.map({ previousDayCategories.contains($0) }) ?? !previousDayCategories.isEmpty {
                Button {
                    onCopyFromPreviousDay(category)
                } label: {
                    Label(
                        category == nil
                            ? String(localized: "Copy all meals from \(previousDayName)")
                            : String(localized: "Copy from \(previousDayName)"),
                        systemImage: "doc.on.doc"
                    )
                }
            }
            Button {
                onCopyFromAnotherDay(category)
            } label: {
                Label("Copy from another day…", systemImage: "calendar")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .minimumHitArea()
        }
        .accessibilityLabel(category.map { String(localized: "Copy options for \($0.displayName)") } ?? String(localized: "Copy meals"))
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

    @Environment(DataStore.self) private var dataStore
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 44

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                FoodThumbnail(
                    name: entry.name,
                    imageURL: entry.pictureURL(in: dataStore.profile.customFoods),
                    barcode: entry.productBarcode,
                    size: tileSize
                )
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(entry.name)
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Text("\(entry.calories) kcal")
                            .font(AppFont.scaled(13, weight: .semibold))
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
