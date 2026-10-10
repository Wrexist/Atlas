import SwiftUI

/// Brief confirm-and-pick-category sheet between tapping a recipe
/// row and the actual log being persisted. Surfaces:
///
///   • The recipe name + ingredient count.
///   • The composed macros that will land on today.
///   • A `MealCategoryPicker` defaulted to the time-of-day auto-
///     pick so most logs are one extra tap (Confirm), not three.
///
/// Sits between "tap a recipe" and "the macros are committed" so
/// the user can correct the auto-category at a meal boundary
/// without having to undo + re-log.
struct RecipeLogConfirmSheet: View {
    let recipe: Recipe
    let customFoods: [CustomFood]
    let onLog: (MealCategory) -> Bool
    let onCancel: () -> Void
    var logDate: Date = Date()
    var onEdit: (() -> Void)? = nil

    @State private var category: MealCategory = MealCategory.auto(for: Date())
    @State private var didLog = false
    @State private var saveFailed = false

    private var review: RecipeDataLogic.Review {
        RecipeDataLogic.review(for: recipe, customFoods: customFoods)
    }

    private var totals: LoggableMeal {
        RecipeDataLogic.totals(for: recipe, customFoods: customFoods)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    headerCard
                    if review.totals != nil { macrosCard }
                    else {
                        GlassCard {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("Check ingredients before logging").font(AppFont.headline)
                                Text("Some foods or portions are unavailable. Fix them so the full recipe is counted.")
                                    .font(AppFont.callout)
                                ForEach(review.unresolved) { component in
                                    Text(component.cachedName.isEmpty ? "Unknown ingredient" : component.cachedName)
                                }
                                if let onEdit { Button("Edit ingredients", action: onEdit).minimumHitArea() }
                            }
                        }
                    }
                    Text("Logging on \(logDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(AppFont.caption)
                    if saveFailed { Text("Couldn't save the recipe. Retry; nothing was added.").font(AppFont.callout) }
                    MealCategoryPicker(selection: $category)
                    confirmButton
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.background)
            .navigationTitle("Log recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .onAppear { category = MealCategory.auto(for: logDate) }
    }

    private var headerCard: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accentPrimary.opacity(0.55), AppColor.accentLight.opacity(0.30)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                Text("\(recipe.components.count) ingredient\(recipe.components.count == 1 ? "" : "s")")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var macrosCard: some View {
        GlassCard(tinted: true, padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Logs as")
                    .font(AppFont.scaled(11, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight.opacity(0.85))
                Divider().background(AppColor.glassBorder)
                macroRow(label: "Calories", value: "\(totals.calories) kcal")
                macroRow(label: "Protein",  value: "\(totals.proteinG) g")
                macroRow(label: "Carbs",    value: "\(totals.carbsG) g")
                macroRow(label: "Fat",      value: "\(totals.fatG) g")
            }
        }
    }

    private func macroRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
        }
    }

    private var confirmButton: some View {
        GlassButton(
            title: "Log recipe",
            icon: "checkmark.circle.fill",
            style: .primary,
            isFullWidth: true
        ) {
            guard !didLog, review.totals != nil else { return }
            didLog = onLog(category)
            saveFailed = !didLog
        }
        .disabled(review.totals == nil || totals.calories == 0 || didLog)
    }
}
