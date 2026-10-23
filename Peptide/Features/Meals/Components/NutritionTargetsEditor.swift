import SwiftUI

/// Standalone NavigationStack-wrapped editor for the user's daily
/// calorie + macro targets. Mounted from the Meals tab's
/// `HomeMealsSection` and the Today tab's "see calorie target" tap.
///
/// The editor folds in everything the profile knows — body metrics +
/// the user's stated goal — to surface a one-tap "Recommended for you"
/// target via `NutritionMath.recommendedTargets`, plus three goal presets
/// (Lose fat / Maintain / Build muscle) for users who'd rather just pick a
/// goal than reason about numbers. The recommendation always renders — when
/// body stats are missing it falls back to the matching preset's sensible
/// default, so the screen is never a wall of zeros and never hides the help.
/// On first open with no saved targets the recommendation auto-fills. The
/// whole surface uses the app's Liquid Glass language: a live calorie hero,
/// a proportional macro bar, and glass input cards.
///
/// Two preset extensions on `NutritionTargets` live alongside this view
/// because they're its closest collaborators — `.placeholder` for "user
/// hasn't computed targets yet, render with sensible bounds", and
/// `.zero` as the initial seed when the editor opens without values.
struct NutritionTargetsEditor: View {
    // Number fields and unit labels hold scaling text, so their widths
    // scale with Dynamic Type instead of clipping "kcal" or "2500".
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 90
    @ScaledMetric(relativeTo: .caption2) private var unitWidth: CGFloat = 28
    let initial: NutritionTargets
    /// Body metrics + goal used to compute the recommendation. Passed in
    /// from the call site's `dataStore.profile` so the editor stays free
    /// of a DataStore dependency.
    var bodyMetrics: BodyMetrics = .unspecified
    var goalRaw: String? = nil
    /// Expenditure estimate from `DataStore.expenditureEstimate()` —
    /// adaptive when enough intake + weigh-ins are logged, else formula.
    var expenditure: AdaptiveTDEEEngine.Estimate? = nil
    let onSave: (NutritionTargets) -> Void
    let onCancel: () -> Void

    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var fiber: String = ""
    /// The fields as the editor opened, so only real edits ask before
    /// being discarded.
    @State private var openedFields: [String] = []
    @FocusState private var focusedField: Field?
    @AppStorage(AdaptiveTDEESettings.enabledKey) private var useAdaptive = true

    private enum Field: Hashable { case calories, protein, carbs, fat, fiber }

    /// Calories per gram, for the live macro→calorie readout.
    private static let kcalProtein = 4, kcalCarbs = 4, kcalFat = 9

    /// Personalised recommendation for the user's stated goal. Falls back to
    /// the matching preset's fixed default when body metrics are incomplete,
    /// so the editor always leads with a usable target instead of zeros.
    private var recommended: NutritionTargets {
        NutritionMath.recommendedTargets(for: bodyMetrics, goalRaw: goalRaw, maintenanceKcal: adaptiveMaintenance)
            ?? NutritionMath.Preset.matching(goalRaw: goalRaw).fallback
    }

    /// Measured maintenance calories when adaptive targets are on and the
    /// estimate rests on logged data; nil means "use the formula".
    private var adaptiveMaintenance: Double? {
        guard useAdaptive, let expenditure, expenditure.source == .adaptive else { return nil }
        return Double(expenditure.kcal)
    }

    /// True once full body stats exist — decides whether the recommendation
    /// is personalised or a generic starting point.
    private var hasPersonalStats: Bool { bodyMetrics.isComplete }

    /// Preset that matches the user's stated goal, flagged in the chip row.
    private var recommendedPreset: NutritionMath.Preset {
        NutritionMath.Preset.matching(goalRaw: goalRaw)
    }

    private var goalLabel: String {
        NutritionMath.GoalIntent(goalRaw: goalRaw).shortLabel
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        summaryCard
                        if let expenditure {
                            expenditureCard(expenditure)
                        }
                        recommendedCard(recommended)
                        presetsCard
                        caloriesCard
                        macrosCard
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.xxxxl)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Daily targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DiscardChangesCancelButton(hasChanges: hasChanges, onCancel: onCancel)
                        .foregroundStyle(AppColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .onAppear {
            hydrate()
            openedFields = fields
        }
    }

    // MARK: - Live summary

    /// Hero card: the entered calories big, with a proportional macro
    /// bar underneath that animates as the user edits. Reads live from
    /// the parsed fields so the screen always reflects the current draft.
    private var summaryCard: some View {
        GlassCard(tinted: true) {
            VStack(spacing: Spacing.md) {
                VStack(spacing: 2) {
                    Text("\(intValue(calories))")
                        .font(AppFont.scaled(48, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                    Text("kcal per day")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                macroBar
                macroSumCheck

                HStack(spacing: Spacing.lg) {
                    macroLegend("Protein", grams: intValue(protein), tint: AppColor.macroProtein)
                    macroLegend("Carbs", grams: intValue(carbs), tint: AppColor.macroCarbs)
                    macroLegend("Fat", grams: intValue(fat), tint: AppColor.macroFat)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var macroBar: some View {
        let p = Double(intValue(protein) * Self.kcalProtein)
        let c = Double(intValue(carbs) * Self.kcalCarbs)
        let f = Double(intValue(fat) * Self.kcalFat)
        let total = max(p + c + f, 1)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                segment(width: geo.size.width * p / total, tint: AppColor.macroProtein)
                segment(width: geo.size.width * c / total, tint: AppColor.macroCarbs)
                segment(width: geo.size.width * f / total, tint: AppColor.macroFat)
            }
            .appAnimation(AppAnimation.springSmooth, value: total)
        }
        .frame(height: 10)
        .background(Capsule().fill(AppColor.surfaceSecondary.opacity(0.6)))
        .clipShape(Capsule())
    }

    private var macroCalories: Int {
        intValue(protein) * Self.kcalProtein + intValue(carbs) * Self.kcalCarbs + intValue(fat) * Self.kcalFat
    }

    /// Macros rarely land exactly on the calorie target, so this only
    /// turns to warning when they're more than 10% apart.
    private var macroSumCheck: some View {
        let target = intValue(calories)
        let isOff = target > 0 && Double(abs(macroCalories - target)) > Double(target) * 0.10
        return Text("Macros = \(macroCalories) kcal")
            .font(AppFont.caption2)
            .monospacedDigit()
            .foregroundStyle(isOff ? AppColor.warning : AppColor.textSecondary)
            .contentTransition(.numericText())
    }

    private func segment(width: CGFloat, tint: Color) -> some View {
        Capsule().fill(tint.opacity(0.9)).frame(width: max(0, width))
    }

    private func macroLegend(_ label: LocalizedStringKey, grams: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(label)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Text("\(grams) g")
                .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recommended

    private func recommendedCard(_ rec: NutritionTargets) -> some View {
        let isApplied = matchesDraft(rec)
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Recommended for you")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        recommendationSubtitle
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: Spacing.sm) {
                    recChip("\(rec.calories)", "kcal", tint: AppColor.accentLight)
                    recChip("\(rec.proteinG)", "P", tint: AppColor.macroProtein)
                    recChip("\(rec.carbsG)", "C", tint: AppColor.macroCarbs)
                    recChip("\(rec.fatG)", "F", tint: AppColor.macroFat)
                }

                GlassButton(
                    title: isApplied ? "Applied" : "Use these targets",
                    icon: isApplied ? "checkmark.circle.fill" : "sparkles",
                    style: isApplied ? .secondary : .primary,
                    isFullWidth: true
                ) {
                    Haptics.impact(.soft)
                    apply(rec)
                }
                .disabled(isApplied)
            }
        }
    }

    private var recommendationSubtitle: Text {
        if adaptiveMaintenance != nil {
            return Text("Based on your measured expenditure + \(goalLabel) goal")
        }
        return hasPersonalStats
            ? Text("Based on your stats + \(goalLabel) goal")
            : Text("A \(goalLabel) starting point — add stats in Profile to personalize")
    }

    // MARK: - Expenditure

    /// What the recommendation is built on — the measured (adaptive) or
    /// formula expenditure — plus the switch that lets targets follow it.
    private func expenditureCard(_ estimate: AdaptiveTDEEEngine.Estimate) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Estimated expenditure: \(estimate.kcal) kcal")
                        .font(AppFont.headline)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                    expenditureSourceText(estimate)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                rowDivider

                Toggle(isOn: $useAdaptive) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(AppColor.accentLight)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Adaptive targets")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                            Text("Targets follow what you actually burn once there's enough data")
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .tint(AppColor.accentPrimary)
            }
        }
    }

    private func expenditureSourceText(_ estimate: AdaptiveTDEEEngine.Estimate) -> Text {
        switch estimate.source {
        case .adaptive:
            return Text("Adaptive, based on \(estimate.intakeDays) days of logged meals and weigh-ins")
        case .formula:
            return Text("Formula — log meals and weigh in for 2 weeks to switch to adaptive")
        }
    }

    private func recChip(_ value: String, _ unit: LocalizedStringKey, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
            Text(unit)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(tint.opacity(0.12))
        }
    }

    // MARK: - Goal presets

    /// Three one-tap goal presets. Each applies a ready-made calorie + macro
    /// split so a user who doesn't want to think about numbers can pick a
    /// goal and be done. The chip matching their stated goal is marked.
    private var presetsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Or pick a goal")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                HStack(spacing: Spacing.sm) {
                    ForEach(NutritionMath.Preset.allCases) { preset in
                        presetChip(preset)
                    }
                }
            }
        }
    }

    private func presetChip(_ preset: NutritionMath.Preset) -> some View {
        let targets = NutritionMath.presetTargets(preset, for: bodyMetrics, maintenanceKcal: adaptiveMaintenance)
        let isSelected = matchesDraft(targets)
        let isRecommended = preset == recommendedPreset
        return Button {
            Haptics.impact(.soft)
            apply(targets)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.accentLight)
                Text(preset.title)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(targets.calories)")
                    .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AppColor.onAccent.opacity(0.8) : AppColor.textSecondary)
                if isRecommended {
                    Text("Recommended")
                        .font(AppFont.badge)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? AppColor.onAccent.opacity(0.8) : AppColor.accentLight)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(isSelected ? AppColor.accentPrimary : AppColor.accentPrimary.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(
                                isRecommended && !isSelected
                                    ? AppColor.accentLight.opacity(0.5)
                                    : .clear,
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input cards

    private var caloriesCard: some View {
        GlassCard {
            inputRow(
                icon: "flame.fill",
                tint: AppColor.accentLight,
                title: "Calories",
                unit: "kcal",
                text: $calories,
                field: .calories
            )
        }
    }

    private var macrosCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                inputRow(icon: "p.circle.fill", tint: AppColor.macroProtein, title: "Protein", unit: "g", text: $protein, field: .protein)
                rowDivider
                inputRow(icon: "c.circle.fill", tint: AppColor.macroCarbs, title: "Carbs", unit: "g", text: $carbs, field: .carbs)
                rowDivider
                inputRow(icon: "f.circle.fill", tint: AppColor.macroFat, title: "Fat", unit: "g", text: $fat, field: .fat)
                rowDivider
                inputRow(icon: "leaf.fill", tint: AppColor.accentPrimary, title: "Fiber", unit: "g", text: $fiber, field: .fiber)
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .overlay(AppColor.glassBorder)
            .padding(.vertical, Spacing.xs)
    }

    private func inputRow(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        unit: LocalizedStringKey,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .trailing, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                        .fill(tint.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: Spacing.sm)
                TextField("0", text: text)
                    .accessibilityLabel(Text(title))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(AppFont.scaled(16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                    .focused($focusedField, equals: field)
                    .frame(maxWidth: fieldWidth)
                Text(unit)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: unitWidth, alignment: .leading)
            }
            if value(for: field) == nil {
                Text(field == .calories ? "Enter 800–10,000 kcal" : "Enter 0–1,000 g")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.warning)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
    }

    // MARK: - Logic

    private func hydrate() {
        // First open with no targets yet → seed the recommendation so the
        // screen opens pre-filled instead of all zeros.
        if initial == .zero {
            apply(recommended)
            return
        }
        calories = String(initial.calories)
        protein = String(initial.proteinG)
        carbs = String(initial.carbsG)
        fat = String(initial.fatG)
        fiber = String(initial.fiberG)
    }

    private func apply(_ targets: NutritionTargets) {
        AppAnimation.with(AppAnimation.springSmooth) {
            calories = String(targets.calories)
            protein = String(targets.proteinG)
            carbs = String(targets.carbsG)
            fat = String(targets.fatG)
            fiber = String(targets.fiberG)
        }
    }

    private func matchesDraft(_ t: NutritionTargets) -> Bool {
        intValue(calories) == t.calories
            && intValue(protein) == t.proteinG
            && intValue(carbs) == t.carbsG
            && intValue(fat) == t.fatG
            && intValue(fiber) == t.fiberG
    }

    /// Lenient parse — an empty or mid-edit field reads as 0 for the live
    /// summary without blocking the keyboard.
    private func intValue(_ s: String) -> Int { Int(s) ?? 0 }

    /// The field's target, or nil when it is blank or out of range. A 0 kcal
    /// target would leave every ring permanently empty. Fiber is optional,
    /// so blank reads as no target.
    private func value(for field: Field) -> Int? {
        let text = switch field {
        case .calories: calories
        case .protein: protein
        case .carbs: carbs
        case .fat: fat
        case .fiber: fiber
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if field == .fiber && trimmed.isEmpty { return 0 }
        let range = field == .calories ? 800...10_000 : 0...1_000
        return Int(trimmed).flatMap { range.contains($0) ? $0 : nil }
    }

    private var fields: [String] { [calories, protein, carbs, fat, fiber] }

    private var hasChanges: Bool { fields != openedFields }

    private var isValid: Bool {
        [Field.calories, .protein, .carbs, .fat, .fiber].allSatisfy { value(for: $0) != nil }
    }

    private func save() {
        guard
            let kcal = value(for: .calories),
            let p = value(for: .protein),
            let c = value(for: .carbs),
            let f = value(for: .fat),
            let fib = value(for: .fiber)
        else { return }
        // Remember an accepted recommendation so `refreshAdaptiveTargets`
        // may move it later; custom numbers opt out of auto-updates.
        let targets = NutritionTargets(calories: kcal, proteinG: p, carbsG: c, fatG: f, fiberG: fib)
        AdaptiveTDEESettings.followedTargets = matchesDraft(recommended) ? targets : nil
        onSave(targets)
    }
}

extension NutritionTargets {
    /// Soft default when the user hasn't computed or entered macro
    /// targets yet — the rings still render with sensible bounds
    /// instead of dividing by zero. Consumed by the meal-logging
    /// flow's "calories remaining" math and by the macro summary row.
    static let placeholder = NutritionTargets(
        calories: 2000,
        proteinG: 120,
        carbsG: 220,
        fatG: 60,
        fiberG: 30
    )

    /// Empty seed for the editor when no existing targets are stored.
    /// `fileprivate` would be tighter, but the editor's caller (now
    /// `HomeMealsSection`) lives in a different file, so this needs
    /// internal visibility.
    static let zero = NutritionTargets(
        calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0
    )
}
