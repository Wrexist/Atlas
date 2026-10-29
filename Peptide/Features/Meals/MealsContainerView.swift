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
/// The fasting tracker, "Plan my day" and the diet coach live only
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    HomeMealsSection()
                    MealsRecipeShelf()
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
            .background(AppColor.background.ignoresSafeArea())
            .overlay { TableSaveToast() }
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.large)
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

    private var planningTools: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(eyebrow: "Tools", title: "Plan ahead")
            NavigationLink {
                FridgeView()
            } label: {
                GlassEntryRowLabel(
                    icon: "refrigerator.fill",
                    title: "Fridge",
                    subtitle: fridgeSubtitle,
                    badge: fridgeBadge
                )
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            NavigationLink {
                WeeklyPrepView()
            } label: {
                GlassEntryRowLabel(
                    icon: "shippingbox.fill",
                    title: "Weekly prep",
                    subtitle: Text("Two dishes, one shopping list, boxes for the week")
                )
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            GlassEntryRow(
                icon: "wand.and.stars",
                title: "Plan my day",
                subtitle: Text("Meals from foods you already eat, sized to your targets"),
                action: { showMealPlan = true }
            )
            GlassEntryRow(
                icon: "sparkles",
                title: "Ask the diet coach",
                subtitle: Text("Review your last 7 days of eating with AI"),
                badge: storeService.canAccessAIFeatures ? nil : Badge("Pro"),
                action: openCoach
            )
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

#Preview {
    MealsContainerView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
