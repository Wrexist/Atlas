import SwiftUI
import UIKit

/// The plated photo of a library recipe, from the asset `recipe-<id>`
/// (`Assets.xcassets/Recipes`). Until a photo is added the recipe gets a
/// plate drawn in its lead ingredient's colour with that ingredient's
/// emoji, so the screens read finished either way. Dropping an image with
/// the right name into the catalog is the whole swap.
struct RecipeImage: View {
    let recipe: LibraryRecipe
    var cornerRadius: CGFloat = Spacing.cardCornerRadius

    var body: some View {
        Color.clear
            .overlay {
                if let photo = UIImage(named: recipe.image) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    RecipePlatePlaceholder(artwork: Self.artwork(for: recipe))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    /// The first ingredient the food artwork recognises; recipes list their
    /// main ingredient first, so that is what the plate shows.
    static func artwork(for recipe: LibraryRecipe) -> FoodArtwork {
        for ingredient in recipe.ingredients {
            let match = FoodArtwork.match(ingredient.name)
            if match != .fallback { return match }
        }
        return FoodArtwork.match(recipe.name)
    }
}

private struct RecipePlatePlaceholder: View {
    let artwork: FoodArtwork

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(
                    colors: [artwork.tint.opacity(0.30), artwork.tint.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(AppColor.surfaceElevated)
                    .overlay {
                        Circle()
                            .strokeBorder(AppColor.glassBorder, lineWidth: 1)
                            .padding(side * 0.08)
                    }
                    .appShadow(AppShadow.glassSubtle)
                    .frame(width: side * 0.68, height: side * 0.68)
                Text(artwork.emoji)
                    .font(AppFont.scaled(max(28, side * 0.26), relativeTo: .largeTitle, in: .large))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
