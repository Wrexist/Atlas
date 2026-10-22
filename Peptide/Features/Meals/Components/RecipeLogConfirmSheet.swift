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
                    if review.totals != nil {
                        MealScanTotalsCard(
                            calories: totals.calories,
                            proteinG: totals.proteinG,
                            carbsG: totals.carbsG,
                            fatG: totals.fatG
                        )
                    } else {
                        unresolvedCard
                    }
                    Text("Logging on \(logDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                    if saveFailed {
                        warningMessage("Couldn't save the recipe. Retry; nothing was added.")
                    }
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
            Image(systemName: "list.bullet.rectangle.fill")
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 56, height: 56)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                        .fill(AppColor.accentPrimary.opacity(0.18))
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(recipe.name)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                Text("^[\(recipe.components.count) ingredient](inflect: true)")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var unresolvedCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label {
                    Text("Check ingredients before logging")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColor.warning)
                }
                Text("Some foods or portions are unavailable. Fix them so the full recipe is counted.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(review.unresolved) { component in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(AppColor.warning)
                            .accessibilityHidden(true)
                        Text(component.cachedName.isEmpty ? String(localized: "Unknown ingredient") : component.cachedName)
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: Spacing.minimumHitTarget)
                    .accessibilityElement(children: .combine)
                }
                if let onEdit {
                    GlassButton(title: "Edit ingredients", icon: "pencil", style: .secondary, isFullWidth: true, action: onEdit)
                }
            }
        }
    }

    private func warningMessage(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColor.warning)
                .accessibilityHidden(true)
            Text(text)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.warning.opacity(0.12))
        }
        .accessibilityElement(children: .combine)
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
        .appSensoryFeedback(.success, trigger: didLog)
    }
}
