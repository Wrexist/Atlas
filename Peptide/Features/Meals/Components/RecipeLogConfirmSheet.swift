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
    let onLog: (MealCategory) -> Void
    let onCancel: () -> Void

    @State private var category: MealCategory = MealCategory.auto(for: Date())

    private var totals: LoggableMeal {
        RecipeDataLogic.totals(for: recipe, customFoods: customFoods)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    headerCard
                    macrosCard
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
        .preferredColorScheme(.dark)
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
            title: "Log to today",
            icon: "checkmark.circle.fill",
            style: .primary,
            isFullWidth: true
        ) {
            onLog(category)
        }
        .disabled(totals.calories == 0)
    }
}
