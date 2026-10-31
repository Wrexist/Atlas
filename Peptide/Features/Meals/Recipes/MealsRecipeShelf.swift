import SwiftUI

/// The Meals tab's recipe row: the user's hearted recipes, each one tap
/// from today's diary. Until something is hearted it shows recipes for
/// the meal of the hour, with a hint on how to keep one here.
struct MealsRecipeShelf: View {
    @Environment(DataStore.self) private var dataStore

    private var favorites: [LibraryRecipe] {
        let ids = dataStore.profile.favoriteRecipeIDs
        return RecipeLibraryEngine.bundled.filter { ids.contains($0.id) }
    }

    private var forNow: [LibraryRecipe] {
        let slot = MealCategory.auto(for: Date())
        return Array(RecipeLibraryEngine.bundled.filter { $0.category == slot }.prefix(8))
    }

    var body: some View {
        let favorites = self.favorites
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(
                eyebrow: "Recipes",
                title: favorites.isEmpty ? "Picked for now" : "Your favorites"
            ) {
                NavigationLink {
                    RecipeLibraryView()
                } label: {
                    Text("See all")
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.accentLight)
                        .minimumHitArea()
                }
            }
            if favorites.isEmpty {
                Label("Tap the heart on a recipe to keep it here.", systemImage: "heart")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(favorites.isEmpty ? forNow : favorites) { recipe in
                        RecipeShelfCard(recipe: recipe)
                    }
                }
                .scrollTargetLayout()
            }
            // Full-bleed: cards run to the screen edge instead of being
            // cut at the content padding.
            .padding(.horizontal, -Spacing.screenPadding)
            .contentMargins(.horizontal, Spacing.screenPadding, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .appAnimation(AppAnimation.springSnappy, value: favorites.map(\.id))
    }
}

/// Photo card with a heart in the corner and, for logging without opening
/// the recipe, a plus that adds one serving to today.
private struct RecipeShelfCard: View {
    let recipe: LibraryRecipe

    @Environment(DataStore.self) private var dataStore
    @Environment(\.locale) private var locale
    @State private var justLogged = false

    private static let width: CGFloat = 196
    private static let photoHeight: CGFloat = 148

    var body: some View {
        NavigationLink {
            RecipeDetailView(recipe: recipe)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                RecipeImage(
                    recipe: recipe,
                    cornerRadius: Spacing.concentric(in: Spacing.cardCornerRadius, inset: Spacing.sm)
                )
                .frame(height: Self.photoHeight)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(recipe.displayName(locale: locale))
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Text("\(recipe.calories) kcal · \(Int(recipe.proteinG.rounded())) g protein")
                        .font(AppFont.caption2)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2, reservesSpace: true)
                }
                // Room for the log button, which floats over this corner.
                .padding(.trailing, Spacing.minimumHitTarget)
                .padding(.leading, Spacing.xs)
                .padding(.bottom, Spacing.xs)
            }
            .padding(Spacing.sm)
            .frame(width: Self.width)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
        .overlay(alignment: .topTrailing) {
            RecipeFavoriteButton(recipe: recipe, diameter: 32)
                .padding(Spacing.md)
        }
        .overlay(alignment: .bottomTrailing) {
            logButton
                .padding(Spacing.md)
        }
        .contextMenu { RecipeFavoriteMenuItem(recipe: recipe) }
    }

    private var logButton: some View {
        Button {
            guard !justLogged else { return }
            dataStore.logServing(of: recipe, locale: locale)
            AppAnimation.with(AppAnimation.springBouncy) { justLogged = true }
            Task {
                try? await Task.sleep(for: AppAnimation.logSuccessAutoCloseDelay)
                AppAnimation.with(AppAnimation.settle) { justLogged = false }
            }
        } label: {
            Image(systemName: justLogged ? "checkmark" : "plus")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(justLogged ? AppColor.onAccent : AppColor.accentLight)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .background(Circle().fill(justLogged ? AppColor.positive : AppColor.accentPrimary.opacity(0.18)))
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.88))
        .accessibilityLabel(justLogged ? Text("Logged") : Text("Log 1 serving"))
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            MealsRecipeShelf()
                .padding(.horizontal, Spacing.screenPadding)
        }
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
