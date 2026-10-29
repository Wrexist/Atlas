import SwiftUI

/// One-tap heart for a library recipe. It sits on photos, so it brings its
/// own glass disc; the heart fills with a bounce so the tap reads as saved.
struct RecipeFavoriteButton: View {
    let recipe: LibraryRecipe
    var diameter: CGFloat = 36

    @Environment(DataStore.self) private var dataStore

    private var isFavorite: Bool { dataStore.isFavoriteRecipe(id: recipe.id) }

    var body: some View {
        Button {
            dataStore.toggleFavoriteRecipeWithFeedback(recipe)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(AppFont.scaled(diameter * 0.45, weight: .semibold))
                .foregroundStyle(isFavorite ? AppColor.metricHeartRate : AppColor.textPrimary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isFavorite)
                .frame(width: diameter, height: diameter)
                .glassControl(.circle)
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.88))
        .accessibilityLabel(isFavorite ? Text("Remove from favorites") : Text("Add to favorites"))
    }
}

/// Long-press menu shared by every recipe card: heart it without opening it.
struct RecipeFavoriteMenuItem: View {
    let recipe: LibraryRecipe

    @Environment(DataStore.self) private var dataStore

    var body: some View {
        let isFavorite = dataStore.isFavoriteRecipe(id: recipe.id)
        Button {
            dataStore.toggleFavoriteRecipeWithFeedback(recipe)
        } label: {
            Label(
                isFavorite ? LocalizedStringKey("Remove from favorites") : "Add to favorites",
                systemImage: isFavorite ? "heart.slash" : "heart"
            )
        }
    }
}

extension DataStore {
    /// A firmer tap for saving than for un-saving, so the two feel different.
    func toggleFavoriteRecipeWithFeedback(_ recipe: LibraryRecipe) {
        let adding = !isFavoriteRecipe(id: recipe.id)
        AppAnimation.with(AppAnimation.springSnappy) {
            toggleFavoriteRecipe(id: recipe.id)
        }
        if adding { Haptics.impact(.medium) } else { Haptics.selection() }
    }

    /// Logs one serving of a library recipe to today's diary and returns
    /// the meal slot it landed in.
    @discardableResult
    func logServing(of recipe: LibraryRecipe, locale: Locale) -> MealCategory {
        let entry = RecipeLibraryEngine.entry(for: recipe, locale: locale, at: Date(), calendar: .current)
        logMealEntry(entry)
        Haptics.success()
        return entry.category
    }
}
