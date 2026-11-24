import SwiftUI

/// Meals tab root. Phase D of the training pivot promotes the
/// nutrition surfaces out of the Today scroll into their own
/// top-level tab so food gets first-class real estate alongside
/// training.
///
/// Composed from the existing `HomeMealsSection` — already a self-
/// contained, sheet-owning view that bubbles its modals up the
/// SwiftUI hierarchy — so mounting it here gives the user a
/// single Meals destination without duplicating logic. Spotlight
/// food taps land here: the router switches to `.meals` and the
/// section opens the food library on the pending deep-link.
///
/// Under today's meals sits the recipe shelf: hearted recipes, each one
/// tap from the diary, with the full library behind "See all".
///
/// "Fridge" heads the tools: what is at home, use-by dates, and recipes
/// that cook from it.
///
/// The fasting tracker, "Plan my day" and Ask Atlas live only
/// here, not on the Today instance of the section — they are nutrition
/// tools, and Today stays curated.
///
/// Progress photos are body-tracking, not nutrition, so they live
/// on the Your Progress screen (`AtlasProgressView`) rather than here.
struct MealsContainerView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var storeService = StoreService.shared
    @State private var fridge = FridgeStore.shared
    @State private var showMealPlan = false
    @State private var showCoach = false
    /// The diary day being viewed, shared by the diary and the recipe shelf.
    @State private var mealDayOffset = 0
    #if DEBUG
    @State private var fixtureRecipe = RecipeFixture.recipe
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    HomeMealsSection(dayOffset: $mealDayOffset)
                    MealsRecipeShelf(logDay: LifestyleDataLogic.mealDay(offset: mealDayOffset))
                        .scrollReveal()
                    FastingCard()
                        .scrollReveal()
                    planningTools
                        .scrollReveal()
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
                .readableContentWidth()
            }
            .pageBackground()
            .overlay { TableSaveToast() }
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.large)
            .solidTopScrollEdge()
            #if DEBUG
            .navigationDestination(item: $fixtureRecipe) { RecipeDetailView(recipe: $0) }
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
            }
            .sheet(isPresented: $showMealPlan) {
                MealPlanSheet()
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
            .sheet(isPresented: $showCoach) {
                AIResearchView(brief: coachBrief)
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
        }
    }

    /// Four tools as a 2×2 grid of icon + title tiles: one glance, one
    /// tap in, and the scroll keeps Log food and the diary as its jobs.
    /// The longer descriptions stay as VoiceOver hints.
    private var planningTools: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(title: "Plan and cook")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
                spacing: Spacing.sm
            ) {
                NavigationLink {
                    FridgeView()
                } label: {
                    PlanningToolTile(icon: "refrigerator.fill", title: "Fridge", badge: fridgeBadge)
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.97))
                .accessibilityHint(fridgeSubtitle)
                NavigationLink {
                    WeeklyPrepView()
                } label: {
                    PlanningToolTile(icon: "shippingbox.fill", title: "Weekly prep")
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.97))
                .accessibilityHint(Text("Two dishes, one shopping list, boxes for the week"))
                Button {
                    showMealPlan = true
                } label: {
                    PlanningToolTile(icon: "wand.and.stars", title: "Plan my day")
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.97))
                .accessibilityHint(Text("Meals from foods you already eat, sized to your targets"))
                Button(action: openCoach) {
                    PlanningToolTile(
                        icon: "sparkles",
                        title: "Ask Atlas",
                        badge: storeService.canAccessAIFeatures ? nil : Badge("Pro")
                    )
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.97))
                .accessibilityHint(Text("Review your last 7 days of meals with AI"))
            }
        }
    }

    private var fridgeSubtitle: Text {
        let count = fridge.items.reduce(0) { $0 + $1.count }
        if count == 0 { return Text("Scan your fridge or shopping, track use-by dates") }
        if count == 1 { return Text("1 item at home, cook from what you have") }
        return Text("\(count) items at home, cook from what you have")
    }

    /// Items at or past their use-by day, flagged so they get eaten.
    private var fridgeBadge: Badge? {
        let soon = fridge.items.filter {
            FridgeEngine.freshness($0.expiresOn, now: .now, calendar: .current).needsUse
        }.count
        guard soon > 0 else { return nil }
        return Badge("\(soon) use soon", icon: "clock.fill", tint: AppColor.warning)
    }

    /// Same Pro gate as the research chat it reuses: free users get the
    /// AI paywall from the root instead of the sheet.
    private func openCoach() {
        if storeService.canAccessAIFeatures {
            showCoach = true
        } else {
            appState.presentedPaywall = .aiResearch
        }
    }

    private var coachBrief: AIResearchService.Brief {
        let profile = dataStore.profile
        let text = NutritionCoachEngine.brief(
            NutritionCoachEngine.summary(of: profile),
            unit: profile.bodyMetrics.unit
        )
        return AIResearchService.Brief(topic: .nutrition, text: text)
    }
}

/// One "Plan and cook" tool: an accent glyph over its name, with an
/// optional badge (use-soon count, Pro) in the corner.
private struct PlanningToolTile: View {
    let icon: String
    let title: LocalizedStringKey
    var badge: Badge?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                IconTile(icon, size: 32)
                Spacer(minLength: Spacing.xs)
                badge
            }
            Text(title)
                .font(AppFont.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MealsContainerView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
