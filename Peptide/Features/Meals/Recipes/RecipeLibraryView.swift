import SwiftUI

/// "Recipes & meal prep": the bundled recipe library, with a carousel of
/// recipes ranked for the user right now (favourite foods, what is left of
/// today's targets, the time of day, what they ate lately and what is at
/// home), category chips, search and a two-column grid.
struct RecipeLibraryView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pantry = PantryStore.shared
    @State private var searchText = ""
    @State private var filter: RecipeFilter = .all
    @State private var recommendations: [RecipeLibraryEngine.Recommendation] = []

    private let recipes = RecipeLibraryEngine.bundled
    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md, alignment: .top),
        GridItem(.flexible(), spacing: Spacing.md, alignment: .top),
    ]

    private var isBrowsing: Bool {
        searchText.isEmpty && filter == .all
    }

    private var filteredRecipes: [LibraryRecipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return recipes.filter { recipe in
            guard filter.matches(recipe) else { return false }
            guard !query.isEmpty else { return true }
            return recipe.name.lowercased().contains(query)
                || recipe.nameSV.lowercased().contains(query)
                || recipe.ingredients.contains {
                    $0.name.lowercased().contains(query) || $0.nameSV.lowercased().contains(query)
                }
        }
    }

    /// Everything the ranking reads, so it re-runs only when one changes.
    private var rankingKey: RankingKey {
        let profile = dataStore.profile
        return RankingKey(
            pantry: pantry.keys,
            favorites: profile.favoriteFoodIDs,
            meals: profile.mealHistory,
            targets: profile.nutritionTargets
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if isBrowsing && !recommendations.isEmpty {
                    recommendedCarousel
                }
                filterChips
                recipeGrid
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxxl)
            .readableContentWidth()
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Recipes & meal prep")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search recipes or ingredients"
        )
        .scrollDismissesKeyboard(.interactively)
        .task(id: rankingKey) { rank() }
    }

    // MARK: - Recommended

    private var recommendedCarousel: some View {
        // Captured as a value: the scroll-transition closure is @Sendable.
        let shrinks = !reduceMotion
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(eyebrow: "For you", title: "Recommended for you")
                .padding(.horizontal, Spacing.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(recommendations) { recommendation in
                        NavigationLink {
                            RecipeDetailView(recipe: recommendation.recipe)
                        } label: {
                            RecommendedRecipeCard(
                                recipe: recommendation.recipe,
                                reason: RecipeLibraryEngine.reasonText(recommendation.reasons, locale: locale)
                            )
                        }
                        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                        .containerRelativeFrame(.horizontal) { length, _ in length * 0.8 }
                        .scrollTransition { card, phase in
                            card
                                .scaleEffect(shrinks && !phase.isIdentity ? 0.95 : 1)
                                .opacity(phase.isIdentity ? 1 : 0.75)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Spacing.screenPadding, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
        .transition(.opacity)
    }

    // MARK: - Browse

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(RecipeFilter.allCases) { option in
                    GlassChip(option.title, icon: option.icon, isSelected: filter == option) {
                        AppAnimation.with(AppAnimation.springSnappy) { filter = option }
                    }
                }
            }
        }
        .contentMargins(.horizontal, Spacing.screenPadding, for: .scrollContent)
    }

    @ViewBuilder
    private var recipeGrid: some View {
        let shown = filteredRecipes
        if shown.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No recipes match",
                message: "Try another ingredient or clear the filter.",
                action: .init(title: "Clear filters", icon: "xmark.circle.fill") {
                    AppAnimation.with(AppAnimation.springSnappy) {
                        searchText = ""
                        filter = .all
                    }
                },
                style: .compact
            )
            .padding(.horizontal, Spacing.screenPadding)
        } else {
            LazyVGrid(columns: columns, spacing: Spacing.lg) {
                ForEach(shown) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        RecipeGridCard(recipe: recipe)
                    }
                    .buttonStyle(ScalePressStyle(pressedScale: 0.97))
                    .scrollReveal()
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .appAnimation(AppAnimation.springSnappy, value: filter)
        }
    }

    // MARK: - Ranking

    private func rank() {
        let profile = dataStore.profile
        let now = Date()
        let calendar = Calendar.current
        let targets = profile.nutritionTargets ?? .placeholder
        let consumed = dataStore.consumption(for: now)
        let fiberToday = profile.mealHistory
            .filter { calendar.isDate($0.date, inSameDayAs: now) }
            .compactMap(\.fiberG)
            .reduce(0, +)
        let context = RecipeLibraryEngine.Context(
            favoriteFoodNames: RecipeLibraryEngine.favoriteFoodNames(
                favoriteIDs: profile.favoriteFoodIDs,
                customFoods: profile.customFoods,
                mealHistory: profile.mealHistory
            ),
            needs: RecipeLibraryEngine.Needs(
                remainingCalories: targets.calories - consumed.caloriesKcal,
                remainingProteinG: targets.proteinG - consumed.proteinG,
                remainingFiberG: Double(targets.fiberG) - fiberToday
            ),
            now: now,
            calendar: calendar,
            recentMealNames: RecipeLibraryEngine.recentMealNames(in: profile.mealHistory, now: now, calendar: calendar),
            pantry: pantry.keys
        )
        let ranked = RecipeLibraryEngine.recommend(recipes, context: context)
        AppAnimation.with(AppAnimation.settle) { recommendations = ranked }
    }
}

private struct RankingKey: Hashable {
    let pantry: Set<String>
    let favorites: Set<String>
    let meals: [MealEntry]
    let targets: NutritionTargets?
}

/// The library's category chips. Meal prep cuts across lunch and dinner,
/// so it is a filter of its own rather than a fifth meal category.
enum RecipeFilter: String, CaseIterable, Identifiable {
    case all, breakfast, lunch, dinner, snack, mealPrep

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all:       "All"
        case .breakfast: "Breakfast"
        case .lunch:     "Lunch"
        case .dinner:    "Dinner"
        case .snack:     "Snacks"
        case .mealPrep:  "Meal prep"
        }
    }

    var icon: String? {
        switch self {
        case .all:       nil
        case .breakfast: MealCategory.breakfast.icon
        case .lunch:     MealCategory.lunch.icon
        case .dinner:    MealCategory.dinner.icon
        case .snack:     MealCategory.snack.icon
        case .mealPrep:  "shippingbox.fill"
        }
    }

    func matches(_ recipe: LibraryRecipe) -> Bool {
        switch self {
        case .all:       true
        case .breakfast: recipe.category == .breakfast
        case .lunch:     recipe.category == .lunch
        case .dinner:    recipe.category == .dinner
        case .snack:     recipe.category == .snack
        case .mealPrep:  recipe.mealPrep
        }
    }
}

// MARK: - Cards

private struct RecommendedRecipeCard: View {
    let recipe: LibraryRecipe
    let reason: String

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            RecipeImage(recipe: recipe, cornerRadius: Spacing.concentric(in: Spacing.cardCornerRadius, inset: Spacing.sm))
                .frame(height: 190)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(reason)
                    .font(AppFont.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .lineLimit(1)
                Text(recipe.displayName(locale: locale))
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                RecipeMetaLine(recipe: recipe)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.bottom, Spacing.xs)
        }
        .padding(Spacing.sm)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .combine)
    }
}

private struct RecipeGridCard: View {
    let recipe: LibraryRecipe

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            RecipeCutout(recipe: recipe)
                .padding(Spacing.sm)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if recipe.mealPrep {
                        Label("Meal prep", systemImage: "shippingbox.fill")
                            .font(AppFont.badge)
                            .foregroundStyle(AppColor.textPrimary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .glassSurfaceCapsule()
                            .padding(Spacing.sm)
                    }
                }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(recipe.displayName(locale: locale))
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                RecipeMetaLine(recipe: recipe)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.bottom, Spacing.xs)
        }
        .padding(Spacing.sm)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .combine)
    }
}

/// "25 min · 480 kcal · 38 g protein".
struct RecipeMetaLine: View {
    let recipe: LibraryRecipe

    var body: some View {
        Text("\(recipe.minutes) min · \(recipe.calories) kcal · \(Int(recipe.proteinG.rounded())) g protein")
            .font(AppFont.caption2)
            .monospacedDigit()
            .foregroundStyle(AppColor.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

#Preview {
    NavigationStack {
        RecipeLibraryView()
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
