import SwiftUI

/// One library recipe: an edge-to-edge hero photo with a heart (or a
/// double tap) to save it, per-serving facts, nutrition for the servings
/// being cooked, an ingredient list the user ticks off against what is at
/// home, numbered steps, and one tap to log a serving to today's diary.
struct RecipeDetailView: View {
    let recipe: LibraryRecipe

    @Environment(DataStore.self) private var dataStore
    @Environment(\.locale) private var locale
    @State private var pantry = PantryStore.shared
    @State private var servings: Int
    @State private var loggedSlot: MealCategory?
    @State private var showsTitle = false
    @State private var heartBurst = false

    init(recipe: LibraryRecipe) {
        self.recipe = recipe
        _servings = State(initialValue: recipe.servings)
    }

    private static let servingRange = 1...12
    private static let heroHeight: CGFloat = 360

    private var coverage: (have: Int, total: Int) {
        RecipeLibraryEngine.pantryCoverage(recipe, pantry: pantry.keys)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                hero
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    quickFacts
                    nutritionCard
                    ingredientsCard
                    stepsCard
                    Text("General guidance, not medical or dietetic advice.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .readableContentWidth()
            }
            .padding(.bottom, Spacing.xl)
        }
        .ignoresSafeArea(edges: .top)
        .background(AppColor.background.ignoresSafeArea())
        // The big title under the photo names the screen; the bar only
        // repeats it once that title has scrolled away.
        .onScrollGeometryChange(for: Bool.self) { [heroHeight = Self.heroHeight] geometry in
            geometry.contentOffset.y > heroHeight
        } action: { _, pastHero in
            AppAnimation.with(AppAnimation.quick) { showsTitle = pastHero }
        }
        .navigationTitle(showsTitle ? recipe.displayName(locale: locale) : "")
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
        // Captured as a value: the visual-effect closure is @Sendable.
        let heroHeight = Self.heroHeight
        return RecipeImage(recipe: recipe, cornerRadius: 0)
            .frame(height: Self.heroHeight)
            .frame(maxWidth: .infinity)
            .overlay {
                // Top: keeps the status bar and back button legible on a
                // bright photo. Bottom: melts the photo into the page.
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [AppColor.background.opacity(0.55), AppColor.background.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [AppColor.background.opacity(0), AppColor.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                }
                .allowsHitTesting(false)
            }
            .overlay { heartBurstView }
            .overlay(alignment: .bottomTrailing) {
                // Clear of the title, which overlaps the photo's bottom edge.
                RecipeFavoriteButton(recipe: recipe, diameter: 44)
                    .padding(.trailing, Spacing.screenPadding)
                    .padding(.bottom, Spacing.xxxxl + Spacing.sm)
            }
            // Pulling down past the top stretches the photo instead of
            // showing a gap above it.
            .visualEffect { content, proxy in
                let pull = max(0, proxy.frame(in: .scrollView).minY)
                return content
                    .scaleEffect(1 + pull / heroHeight, anchor: .bottom)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: doubleTapFavorite)
    }

    private var heartBurstView: some View {
        Image(systemName: "heart.fill")
            .font(AppFont.scaled(96, weight: .bold, relativeTo: .largeTitle))
            .foregroundStyle(AppColor.metricHeartRate)
            .scaleEffect(heartBurst ? 1 : 0.4)
            .opacity(heartBurst ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Double tap only ever saves, like a photo app: un-saving stays on the
    /// heart button so a stray double tap can't drop a favourite.
    private func doubleTapFavorite() {
        if !dataStore.isFavoriteRecipe(id: recipe.id) {
            dataStore.toggleFavoriteRecipeWithFeedback(recipe)
        } else {
            Haptics.selection()
        }
        AppAnimation.with(AppAnimation.springBouncy) { heartBurst = true }
        Task {
            try? await Task.sleep(for: AppAnimation.confirmationHold)
            AppAnimation.with(AppAnimation.fadeIn) { heartBurst = false }
        }
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
            if let fridgeDays = recipe.fridgeDays, recipe.mealPrep {
                Label("Makes \(recipe.servings) servings · keeps \(fridgeDays) days in the fridge", systemImage: "shippingbox")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        // Pulls the title up onto the photo's faded edge.
        .padding(.top, -Spacing.xxxl)
        .accessibilityElement(children: .combine)
    }

    /// Time and one serving's energy and protein: the three things people
    /// scan a recipe for before reading it.
    private var quickFacts: some View {
        HStack(spacing: Spacing.sm) {
            RecipeFact(icon: "clock.fill", value: "\(recipe.minutes)", unit: "min", tint: AppColor.accentLight)
            RecipeFact(icon: "flame.fill", value: "\(recipe.calories)", unit: "kcal", tint: AppColor.warning)
            RecipeFact(
                icon: "bolt.heart.fill",
                value: "\(Int(recipe.proteinG.rounded()))",
                unit: String(localized: "g protein"),
                tint: AppColor.macroProtein
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Per serving: \(recipe.minutes) min, \(recipe.calories) kcal, \(Int(recipe.proteinG.rounded())) g protein"))
    }

    // MARK: - Nutrition

    private var nutritionCard: some View {
        let factor = Double(servings)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("\(recipe.calories * servings) kcal")
                        .font(AppFont.statValueSmall)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(AppColor.textPrimary)
                    Group {
                        if servings == 1 {
                            Text("For 1 serving")
                        } else {
                            Text("For \(servings) servings")
                        }
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: Spacing.sm)
                VStack(spacing: Spacing.xxs) {
                    Text("Cooking for")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                    servingsStepper
                }
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
        let slot = dataStore.logServing(of: recipe, locale: locale)
        AppAnimation.with(AppAnimation.toast) { loggedSlot = slot }
        Task {
            try? await Task.sleep(for: AppAnimation.logSuccessAutoCloseDelay)
            AppAnimation.with(AppAnimation.toast) { loggedSlot = nil }
        }
    }
}

private struct RecipeFact: View {
    let icon: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(AppFont.headline)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                Text(unit)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .glassSurface(cornerRadius: Spacing.controlCornerRadius)
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
