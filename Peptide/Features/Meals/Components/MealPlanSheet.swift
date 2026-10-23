import SwiftUI

/// "Plan my day": a breakfast / lunch / dinner / snack plan built by
/// `MealPlanEngine` from the user's own foods, with totals against their
/// targets. Each meal logs to today's diary in one tap; Swap replaces
/// one meal, Regenerate the whole day.
struct MealPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @State private var foods: [MealPlanEngine.Food] = []
    @State private var outcome: MealPlanEngine.Outcome?
    /// Foods earlier plans in this sheet used, so Regenerate keeps moving
    /// to new ones until the library is exhausted.
    @State private var seenFoodIDs: Set<String> = []
    @State private var loggedSlots: Set<MealCategory> = []

    private var targets: NutritionTargets {
        dataStore.profile.nutritionTargets ?? .placeholder
    }

    private var plan: MealPlanEngine.Plan? {
        if case .plan(let plan) = outcome { return plan }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let plan {
                        planContent(plan)
                    } else if case .notEnoughFoods(let found) = outcome {
                        notEnoughFoods(found: found)
                    }
                    Text("Built from foods you've logged or saved. General guidance, not medical or dietetic advice.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.lg)
                .readableContentWidth()
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Plan my day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: regenerate) {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .disabled(plan == nil)
                }
            }
            .task { build() }
        }
    }

    // MARK: - Plan

    private func planContent(_ plan: MealPlanEngine.Plan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            totals(plan)
            ForEach(plan.meals) { meal in
                MealPlanRow(
                    meal: meal,
                    isLogged: loggedSlots.contains(meal.slot),
                    onLog: { log(meal) },
                    onSwap: { swap(meal.slot) }
                )
            }
            PrimaryCTAButton(title: "Log whole plan", icon: "checkmark.circle.fill") {
                for meal in plan.meals where !loggedSlots.contains(meal.slot) {
                    log(meal)
                }
            }
            .disabled(plan.meals.allSatisfy { loggedSlots.contains($0.slot) })
        }
    }

    private func totals(_ plan: MealPlanEngine.Plan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            totalRow(
                title: "Calories",
                value: Text("\(plan.calories) / \(plan.targetCalories) kcal"),
                progress: Double(plan.calories) / Double(max(1, plan.targetCalories)),
                gradient: nil
            )
            totalRow(
                title: "Protein",
                value: Text("\(plan.proteinG) / \(plan.targetProteinG) g"),
                progress: Double(plan.proteinG) / Double(max(1, plan.targetProteinG)),
                gradient: [AppColor.macroProtein, AppColor.macroProteinLight]
            )
            Label(statusText(plan), systemImage: isOnTarget(plan) ? "checkmark.seal.fill" : "exclamationmark.circle")
                .font(AppFont.subheadline)
                .foregroundStyle(isOnTarget(plan) ? AppColor.positive : AppColor.warning)
            if dataStore.profile.nutritionTargets == nil {
                Text("Using default targets. Set your own with Edit targets on the Meals tab.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(Spacing.cardPadding)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private func totalRow(title: LocalizedStringKey, value: Text, progress: Double, gradient: [Color]?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer(minLength: 0)
                value
                    .font(AppFont.headline)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
            }
            GlassProgressBar(progress: progress, gradient: gradient)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func isOnTarget(_ plan: MealPlanEngine.Plan) -> Bool {
        plan.isWithinCalorieTolerance && plan.meetsProtein
    }

    private func statusText(_ plan: MealPlanEngine.Plan) -> String {
        if isOnTarget(plan) {
            return String(localized: "On target for calories and protein")
        }
        if !plan.isWithinCalorieTolerance {
            let percent = abs(plan.calorieDeviation).formatted(.percent.precision(.fractionLength(0)))
            return plan.calorieDeviation > 0
                ? String(localized: "\(percent) over your calories — your foods run large")
                : String(localized: "\(percent) under your calories — add bigger meals to My Foods")
        }
        return String(localized: "\(plan.targetProteinG - plan.proteinG) g short on protein — save a protein-rich food to plan around")
    }

    private func notEnoughFoods(found: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: "fork.knife.circle")
                .font(AppFont.scaled(40, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .accessibilityHidden(true)
            Text("Log a few more foods first")
                .font(AppFont.title3)
                .foregroundStyle(AppColor.textPrimary)
            Text("Plans are built from what you already eat. Log or save at least \(MealPlanEngine.minimumFoods) different foods — you have \(found) so far.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    // MARK: - Actions

    private func build() {
        let profile = dataStore.profile
        foods = MealPlanEngine.foods(customFoods: profile.customFoods, mealHistory: profile.mealHistory, now: Date())
        outcome = MealPlanEngine.generate(targets: targets, foods: foods)
        seenFoodIDs = plan?.foodIDs ?? []
        loggedSlots = []
    }

    private func regenerate() {
        guard let current = plan else { return }
        seenFoodIDs.formUnion(current.foodIDs)
        // Every food has had a turn: start the rotation over from here.
        if seenFoodIDs.count >= foods.count { seenFoodIDs = current.foodIDs }
        AppAnimation.with(AppAnimation.springSnappy) {
            outcome = MealPlanEngine.generate(targets: targets, foods: foods, avoiding: seenFoodIDs)
            loggedSlots = []
        }
        Haptics.selection()
    }

    private func swap(_ slot: MealCategory) {
        guard let current = plan else { return }
        AppAnimation.with(AppAnimation.springSnappy) {
            outcome = .plan(MealPlanEngine.swapping(slot, in: current, foods: foods, targets: targets))
            loggedSlots.remove(slot)
        }
        Haptics.selection()
    }

    private func log(_ meal: MealPlanEngine.PlannedMeal) {
        dataStore.logMealEntry(meal.entry(at: Date()))
        loggedSlots.insert(meal.slot)
        Haptics.success()
    }
}

private struct MealPlanRow: View {
    let meal: MealPlanEngine.PlannedMeal
    let isLogged: Bool
    let onLog: () -> Void
    let onSwap: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Label(meal.slot.displayName, systemImage: meal.slot.icon)
                    .font(AppFont.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(meal.slot.tint)
                Text(meal.food.name)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                Text("\(portionText) · \(meal.calories) kcal · \(meal.proteinG) g protein")
                    .font(AppFont.caption2)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: onSwap) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .minimumHitArea()
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.9))
            .accessibilityLabel("Swap \(meal.slot.displayName)")
            GlassButton(
                title: isLogged ? "Logged" : "Log",
                icon: isLogged ? "checkmark" : "plus",
                style: isLogged ? .ghost : .secondary,
                action: onLog
            )
            .disabled(isLogged)
            .accessibilityLabel(isLogged ? "\(meal.food.name) logged" : "Log \(meal.food.name)")
        }
        .padding(Spacing.md)
        .insetRowBackground(cornerRadius: Spacing.smallCornerRadius)
    }

    private var portionText: String {
        let amount = meal.portion.formatted(.number.precision(.fractionLength(0...2)))
        if let serving = meal.food.servingLabel {
            return "\(amount) × \(serving)"
        }
        return meal.portion == 1
            ? String(localized: "usual portion")
            : String(localized: "\(amount) × usual portion")
    }
}
