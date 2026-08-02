import SwiftUI

/// Edit-or-delete sheet for an existing `MealEntry`. Reached from
/// `TodaysMealsCard` by tapping a row. Allows full edit of every
/// field that matters — category, macros, time. Previously only the
/// category was editable, with footer copy that told the user to
/// delete + re-log for macro fixes; but the re-log lands in *today's*
/// bucket (audit Meals MED 9), so a user trying to fix yesterday's
/// entry would silently move it to today. Full edit closes that loop.
struct MealEntryEditorSheet: View {
    let initial: MealEntry
    let onSave: (MealEntry) -> Void
    let onDelete: (UUID) -> Void
    let onCancel: () -> Void

    @State private var category: MealCategory
    @State private var calories: Int
    @State private var proteinG: Int
    @State private var carbsG: Int
    @State private var fatG: Int
    @State private var date: Date
    @State private var showDeleteConfirm: Bool = false

    init(
        initial: MealEntry,
        onSave: @escaping (MealEntry) -> Void,
        onDelete: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initial = initial
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _category = State(initialValue: initial.category)
        _calories = State(initialValue: initial.calories)
        _proteinG = State(initialValue: initial.proteinG)
        _carbsG = State(initialValue: initial.carbsG)
        _fatG = State(initialValue: initial.fatG)
        _date = State(initialValue: initial.date)
    }

    private var hasChanges: Bool {
        category != initial.category
            || calories != initial.calories
            || proteinG != initial.proteinG
            || carbsG != initial.carbsG
            || fatG != initial.fatG
            || !Calendar.current.isDate(date, equalTo: initial.date, toGranularity: .minute)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    summaryCard
                    MealCategoryPicker(selection: $category)
                    macrosCard
                    deleteButton
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.background)
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                        .disabled(!hasChanges)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete(initial.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Subtracts \(initial.calories) kcal from today's totals. This can't be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var summaryCard: some View {
        GlassCard(padding: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(initial.category.tint.opacity(0.20))
                        .frame(width: 44, height: 44)
                    Image(systemName: initial.category.icon)
                        .font(AppFont.scaled(18, weight: .semibold))
                        .foregroundStyle(initial.category.tint)
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(initial.name)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: initial.source.icon)
                            .font(AppFont.scaled(10))
                            .foregroundStyle(AppColor.textSecondary)
                        Text(Self.timeFormatter.string(from: initial.date))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        // `sourceID` may point to a custom food the
                        // user has since deleted, or an OFF barcode
                        // that's been evicted from the cache. The
                        // entry remains valid — we just rely on
                        // `entry.name` for display rather than trying
                        // to dereference the source. No "Re-log this"
                        // shortcut here for the same reason.
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var macrosCard: some View {
        GlassCard(tinted: true, padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Macros & time")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Divider().background(AppColor.glassBorder)
                macroStepper(label: "Calories", unit: "kcal", value: $calories, step: 10, range: 0...10000)
                macroStepper(label: "Protein",  unit: "g",   value: $proteinG, step: 1,  range: 0...500)
                macroStepper(label: "Carbs",    unit: "g",   value: $carbsG,   step: 1,  range: 0...1000)
                macroStepper(label: "Fat",      unit: "g",   value: $fatG,     step: 1,  range: 0...500)
                Divider().background(AppColor.glassBorder)
                DatePicker("Logged at", selection: $date, in: dateRange, displayedComponents: [.date, .hourAndMinute])
                    .font(AppFont.subheadline)
            }
        }
    }

    /// Bounds the date picker so a fat-fingered scroll can't backdate an
    /// entry to 1900 and pollute all-time aggregates. Floors at one year
    /// ago, or the entry's own date if it's somehow older (so editing an
    /// old entry doesn't clamp its selection out of range).
    private var dateRange: ClosedRange<Date> {
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? initial.date
        return min(oneYearAgo, initial.date)...Date()
    }

    private func macroStepper(
        label: LocalizedStringKey,
        unit: String,
        value: Binding<Int>,
        step: Int,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(label)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text("\(value.wrappedValue) \(unit)")
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
            }
        }
    }

    private var deleteButton: some View {
        GlassButton(
            title: "Delete this entry",
            icon: "trash",
            style: .destructive,
            isFullWidth: true
        ) {
            showDeleteConfirm = true
        }
    }

    private func commit() {
        var updated = initial
        updated.category = category
        updated.calories = calories
        updated.proteinG = proteinG
        updated.carbsG = carbsG
        updated.fatG = fatG
        updated.date = date
        onSave(updated)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}
