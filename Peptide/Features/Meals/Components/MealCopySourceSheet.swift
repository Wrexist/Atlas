import SwiftUI

/// Picks the day to copy meals from — one meal (`category`) or the
/// whole day when nil — onto `targetDay`. Shows what that day holds so
/// the user sees what Copy will add before tapping it.
struct MealCopySourceSheet: View {
    let targetDay: Date
    let category: MealCategory?
    let onCopy: (Date) -> Void
    let onCancel: () -> Void

    @Environment(DataStore.self) private var dataStore
    @State private var sourceDay: Date

    init(
        targetDay: Date,
        category: MealCategory?,
        onCopy: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.targetDay = targetDay
        self.category = category
        self.onCopy = onCopy
        self.onCancel = onCancel
        _sourceDay = State(initialValue: Calendar.current.date(byAdding: .day, value: -1, to: targetDay) ?? targetDay)
    }

    private var copies: [MealEntry] {
        LifestyleDataLogic.copiedMeals(
            from: sourceDay,
            to: targetDay,
            category: category,
            in: dataStore.profile.mealHistory
        )
    }

    private var isTargetDay: Bool {
        Calendar.current.isDate(sourceDay, inSameDayAs: targetDay)
    }

    private var selectableDays: ClosedRange<Date> {
        LifestyleDataLogic.mealDay(offset: -LifestyleDataLogic.maxMealDayLookback)...Date()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    GlassCard(padding: Spacing.md) {
                        DatePicker("Copy from", selection: $sourceDay, in: selectableDays, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(AppColor.accentPrimary)
                    }
                    GlassCard(padding: Spacing.md) {
                        summary
                    }
                }
                .padding(Spacing.screenPadding)
            }
            .background(AppColor.background)
            .navigationTitle("Copy meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { onCopy(sourceDay) }
                        .disabled(isTargetDay || copies.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: category?.icon ?? "fork.knife")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(category?.tint ?? AppColor.accentLight)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(category?.displayName ?? String(localized: "All meals"))
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                summaryDetail
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var summaryDetail: some View {
        let found = copies
        if isTargetDay {
            Text("Pick another day to copy from.")
        } else if found.isEmpty {
            Text("Nothing logged that day.")
        } else {
            HStack(spacing: Spacing.xs) {
                Text("^[\(found.count) entry](inflect: true)")
                Text(verbatim: "·")
                Text("\(found.reduce(0) { $0 + $1.calories }) kcal")
                    .monospacedDigit()
            }
        }
    }
}
