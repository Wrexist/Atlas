import SwiftUI

/// "Cook from your fridge": recipes the fridge can mostly make, the ones
/// that save something about to go off first, each with what is left to
/// buy. A meal-prep recipe goes into this week's prep in one tap, where
/// the shopping list already skips what is at home.
struct FridgeCookCard: View {
    let suggestions: [FridgeEngine.Suggestion]

    @Environment(\.locale) private var locale
    @State private var prep = WeeklyPrepStore.shared
    @State private var addedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(eyebrow: "From your fridge", title: "Cook with what you have")
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 {
                        Divider().overlay(AppColor.glassBorder)
                    }
                    row(suggestion)
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
    }

    private func row(_ suggestion: FridgeEngine.Suggestion) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            NavigationLink {
                RecipeDetailView(recipe: suggestion.recipe)
            } label: {
                HStack(alignment: .top, spacing: Spacing.md) {
                    RecipeImage(recipe: suggestion.recipe, cornerRadius: Spacing.smallCornerRadius)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(suggestion.recipe.displayName(locale: locale))
                            .font(AppFont.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text("You have \(suggestion.have) of \(suggestion.total) ingredients")
                            .font(AppFont.footnote)
                            .monospacedDigit()
                            .foregroundStyle(suggestion.missing.isEmpty ? AppColor.positive : AppColor.textSecondary)
                        if suggestion.rescuesExpiring {
                            Label("Uses food about to go off", systemImage: "leaf.fill")
                                .font(AppFont.caption2.weight(.semibold))
                                .foregroundStyle(AppColor.warning)
                        }
                        if !suggestion.missing.isEmpty {
                            Text("Buy: \(missingText(suggestion))")
                                .font(AppFont.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))

            if suggestion.recipe.mealPrep {
                prepButton(suggestion.recipe)
            }
        }
        .padding(.vertical, Spacing.md)
    }

    private func missingText(_ suggestion: FridgeEngine.Suggestion) -> String {
        ListFormatter.localizedString(byJoining: suggestion.missing.map { $0.displayName(locale: locale).lowercased() })
    }

    @ViewBuilder
    private func prepButton(_ recipe: LibraryRecipe) -> some View {
        let plan = prep.plan()
        let isPlanned = plan.recipeIDs.contains(recipe.id)
        let isFull = plan.dishes.count >= WeeklyPrepEngine.dishesPerWeek || plan.preppedAt != nil
        Button {
            AppAnimation.with(AppAnimation.springSnappy) {
                prep.replace(nil, with: recipe)
                addedID = recipe.id
            }
            Haptics.success()
        } label: {
            Image(systemName: isPlanned ? "checkmark" : "shippingbox.fill")
                .contentTransition(.symbolEffect(.replace))
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(isPlanned ? AppColor.positive : AppColor.accentLight)
                .frame(width: 36, height: 36)
                .glassControl(.circle)
        }
        .buttonStyle(ScalePressStyle())
        .minimumHitArea()
        .disabled(isPlanned || isFull)
        .opacity(!isPlanned && isFull ? 0.4 : 1)
        .symbolEffect(.bounce, value: addedID == recipe.id)
        .accessibilityLabel(isPlanned ? Text("In this week's prep") : Text("Add to this week's prep"))
    }
}
