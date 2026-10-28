import SwiftUI

/// One library recipe: hero photo, servings, nutrition for the chosen
/// servings, an ingredient list the user ticks off against what is at home,
/// numbered steps, and one tap to log a serving to today's diary.
struct RecipeDetailView: View {
    let recipe: LibraryRecipe

    @Environment(DataStore.self) private var dataStore
    @Environment(\.locale) private var locale
    @State private var pantry = PantryStore.shared
    @State private var servings: Int
    @State private var loggedSlot: MealCategory?

    init(recipe: LibraryRecipe) {
        self.recipe = recipe
        _servings = State(initialValue: recipe.servings)
    }

    private static let servingRange = 1...12

    private var coverage: (have: Int, total: Int) {
        RecipeLibraryEngine.pantryCoverage(recipe, pantry: pantry.keys)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                hero
                header
                nutritionCard
                ingredientsCard
                stepsCard
                Text("General guidance, not medical or dietetic advice.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xl)
            .readableContentWidth()
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle(recipe.displayName(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .pinnedFooter {
            logButton
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)
        }
    }

    // MARK: - Header

    private var hero: some View {
        RecipeImage(recipe: recipe)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                LinearGradient(
                    colors: [AppColor.background.opacity(0), AppColor.background.opacity(0.35)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
                .allowsHitTesting(false)
            }
            .scrollReveal()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(recipe.category.displayName, systemImage: recipe.category.icon)
                .font(AppFont.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(recipe.category.tint)
            Text(recipe.displayName(locale: locale))
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.lg) {
                Label("\(recipe.minutes) min", systemImage: "clock")
                if let fridgeDays = recipe.fridgeDays, recipe.mealPrep {
                    Label("Makes \(recipe.servings) servings · keeps \(fridgeDays) days in the fridge", systemImage: "shippingbox")
                }
            }
            .font(AppFont.subheadline)
            .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Nutrition

    private var nutritionCard: some View {
        let factor = Double(servings)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Servings")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Text("\(recipe.calories * servings) kcal")
                        .font(AppFont.statValueSmall)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(AppColor.textPrimary)
                }
                Spacer(minLength: Spacing.sm)
                servingsStepper
            }
            HStack(spacing: Spacing.sm) {
                MacroChip.protein(Int((recipe.proteinG * factor).rounded()))
                MacroChip.carbs(Int((recipe.carbsG * factor).rounded()))
                MacroChip.fat(Int((recipe.fatG * factor).rounded()))
                MacroChip(
                    symbol: "leaf.circle.fill",
                    name: String(localized: "fibre"),
                    grams: Int((recipe.fiberG * factor).rounded()),
                    tint: AppColor.positive
                )
            }
            .contentTransition(.numericText())
            if servings != 1 {
                Text("Per serving: \(recipe.calories) kcal · \(Int(recipe.proteinG.rounded())) g protein")
                    .font(AppFont.caption2)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(Spacing.cardPadding)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private var servingsStepper: some View {
        HStack(spacing: Spacing.sm) {
            stepButton(icon: "minus", label: "Fewer servings", delta: -1)
                .disabled(servings <= Self.servingRange.lowerBound)
            Text("\(servings)")
                .font(AppFont.title3)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(AppColor.textPrimary)
                .frame(minWidth: Spacing.xl)
                .accessibilityHidden(true)
            stepButton(icon: "plus", label: "More servings", delta: 1)
                .disabled(servings >= Self.servingRange.upperBound)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text("\(servings) servings"))
    }

    private func stepButton(icon: String, label: LocalizedStringKey, delta: Int) -> some View {
        Button {
            AppAnimation.with(AppAnimation.springSnappy) {
                servings = min(Self.servingRange.upperBound, max(Self.servingRange.lowerBound, servings + delta))
            }
            Haptics.selection()
        } label: {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 36, height: 36)
                .glassControl(.circle)
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.9))
        .accessibilityLabel(label)
    }

    // MARK: - Ingredients

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Ingredients")
                    .font(AppFont.title3)
                    .foregroundStyle(AppColor.textPrimary)
                Text("You have \(coverage.have) of \(coverage.total) ingredients")
                    .font(AppFont.subheadline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(coverage.have == coverage.total ? AppColor.positive : AppColor.textSecondary)
            }
            .accessibilityElement(children: .combine)
            GlassProgressBar(
                progress: Double(coverage.have) / Double(max(1, coverage.total)),
                gradient: nil
            )
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                    if index > 0 {
                        Divider().overlay(AppColor.glassBorder)
                    }
                    IngredientRow(
                        name: ingredient.displayName(locale: locale),
                        grams: RecipeLibraryEngine.displayGrams(RecipeLibraryEngine.grams(ingredient, servings: servings)),
                        isAtHome: pantry.has(ingredient.pantryKey),
                        toggle: { toggle(ingredient) }
                    )
                }
            }
            Text("Tap what you have at home.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(Spacing.cardPadding)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private func toggle(_ ingredient: LibraryRecipe.Ingredient) {
        AppAnimation.with(AppAnimation.springSnappy) {
            pantry.toggle(ingredient.pantryKey)
        }
        Haptics.impact(.light)
    }

    // MARK: - Steps

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Method")
                .font(AppFont.title3)
                .foregroundStyle(AppColor.textPrimary)
            ForEach(Array(recipe.displaySteps(locale: locale).enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    Text("\(index + 1)")
                        .font(AppFont.chipText)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.accentInkOnWash)
                        .frame(width: 26, height: 26)
                        .background(AppColor.accentPrimary.opacity(0.18), in: Circle())
                        .accessibilityHidden(true)
                    Text(step)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Step \(index + 1): \(step)"))
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    // MARK: - Log

    @ViewBuilder
    private var logButton: some View {
        if let loggedSlot {
            HStack(spacing: Spacing.sm) {
                RecipeCutout(recipe: recipe)
                    .frame(width: 32, height: 32)
                Label("Logged to \(loggedSlot.displayName)", systemImage: "checkmark.circle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.positive)
            }
            .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
            .glassSurfaceCapsule()
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        } else {
            PrimaryCTAButton(title: "Log 1 serving", icon: "plus.circle.fill", action: log)
                .transition(.opacity)
        }
    }

    private func log() {
        let now = Date()
        let entry = RecipeLibraryEngine.entry(for: recipe, locale: locale, at: now, calendar: .current)
        dataStore.logMealEntry(entry)
        Haptics.success()
        AppAnimation.with(AppAnimation.toast) { loggedSlot = entry.category }
        Task {
            try? await Task.sleep(for: AppAnimation.logSuccessAutoCloseDelay)
            AppAnimation.with(AppAnimation.toast) { loggedSlot = nil }
        }
    }
}

private struct IngredientRow: View {
    let name: String
    let grams: Int
    let isAtHome: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.md) {
                Image(systemName: isAtHome ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(isAtHome ? AppColor.positive : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(name)
                    .font(AppFont.body)
                    .foregroundStyle(isAtHome ? AppColor.textSecondary : AppColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Spacing.sm)
                Text("\(grams) g")
                    .font(AppFont.subheadline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: Spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), \(grams) g"))
        .accessibilityValue(isAtHome ? Text("At home") : Text("Not at home"))
        .accessibilityAddTraits(isAtHome ? .isSelected : [])
        .accessibilityHint(Text("Marks whether you have it at home"))
    }
}

#Preview {
    NavigationStack {
        if let recipe = RecipeLibraryEngine.bundled.first {
            RecipeDetailView(recipe: recipe)
        }
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
