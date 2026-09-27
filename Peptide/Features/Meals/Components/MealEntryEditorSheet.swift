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
    @State private var calories: String
    @State private var proteinG: String
    @State private var carbsG: String
    @State private var fatG: String
    @State private var date: Date
    @State private var showDeleteConfirm: Bool = false
    @FocusState private var focusedField: MacroField?

    private enum MacroField: Hashable {
        case calories, protein, carbs, fat
    }

    /// Portion multipliers applied to the entry as originally logged.
    /// ×1 resets a scaled or hand-edited entry.
    private static let portionFactors: [Double] = [0.5, 1, 1.5, 2]

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
        _calories = State(initialValue: String(initial.calories))
        _proteinG = State(initialValue: String(initial.proteinG))
        _carbsG = State(initialValue: String(initial.carbsG))
        _fatG = State(initialValue: String(initial.fatG))
        _date = State(initialValue: initial.date)
    }

    /// The typed macros, or nil while any field is blank or not a
    /// whole number.
    private var editedMacros: LoggableMeal? {
        guard
            let kcal = Self.parse(calories),
            let protein = Self.parse(proteinG),
            let carbs = Self.parse(carbsG),
            let fat = Self.parse(fatG)
        else { return nil }
        return LoggableMeal(calories: kcal, proteinG: protein, carbsG: carbs, fatG: fat)
    }

    private var originalMacros: LoggableMeal {
        LifestyleDataLogic.scaledMacros(of: initial, by: 1)
    }

    private var hasChanges: Bool {
        category != initial.category
            || editedMacros != originalMacros
            || !Calendar.current.isDate(date, equalTo: initial.date, toGranularity: .minute)
    }

    private static func parse(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0 >= 0 ? $0 : nil }
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
                        .disabled(!hasChanges || editedMacros == nil)
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
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
                Text("Subtracts \(initial.calories) kcal from that day's totals. This can't be undone.")
            }
        }
    }

    private var summaryCard: some View {
        GlassCard(padding: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(initial.category.tint.opacity(0.20))
                        .frame(width: 44, height: 44)
                    Image(systemName: initial.category.icon)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(initial.category.tint)
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(initial.name)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: initial.source.icon)
                            .font(AppFont.scaled(11))
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
                portionChips
                macroField(label: "Calories", unit: "kcal", text: $calories, field: .calories)
                macroField(label: "Protein",  unit: "g",    text: $proteinG, field: .protein)
                macroField(label: "Carbs",    unit: "g",    text: $carbsG,   field: .carbs)
                macroField(label: "Fat",      unit: "g",    text: $fatG,     field: .fat)
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

    /// ×0.5 … ×2 of the entry as logged. Scaling always starts from
    /// the original values, so tapping ×2 then ×1.5 means 1.5 portions,
    /// not three. The chip matching the current fields reads as active.
    private var portionChips: some View {
        HStack(spacing: Spacing.xs) {
            Text("Portion")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer(minLength: Spacing.xs)
            ForEach(Self.portionFactors, id: \.self) { factor in
                portionChip(factor)
            }
        }
    }

    private func portionChip(_ factor: Double) -> some View {
        let scaled = LifestyleDataLogic.scaledMacros(of: initial, by: factor)
        let isActive = editedMacros == scaled
        let label = "×" + factor.formatted(.number.precision(.fractionLength(0...1)))
        return Button {
            Haptics.selection()
            apply(scaled)
        } label: {
            Text(label)
                .font(AppFont.scaled(13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isActive ? AppColor.onAccent : AppColor.textPrimary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(isActive ? AppColor.accentPrimary : AppColor.surfaceSecondary.opacity(0.6))
                }
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(label) portion"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func apply(_ macros: LoggableMeal) {
        calories = String(macros.calories)
        proteinG = String(macros.proteinG)
        carbsG = String(macros.carbsG)
        fatG = String(macros.fatG)
    }

    private func macroField(
        label: LocalizedStringKey,
        unit: String,
        text: Binding<String>,
        field: MacroField
    ) -> some View {
        HStack {
            Text(label)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            TextField("0", text: text)
                .accessibilityLabel(Text(label))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: field)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .frame(maxWidth: 100)
                .frame(minHeight: Spacing.minimumHitTarget)
            Text(unit)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 32, alignment: .leading)
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
        guard let macros = editedMacros else { return }
        var updated = initial
        updated.category = category
        updated.calories = macros.calories
        updated.proteinG = macros.proteinG
        updated.carbsG = macros.carbsG
        updated.fatG = macros.fatG
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
