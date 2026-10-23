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
    @State private var showMealPlan = false
    @State private var showCoach = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    HomeMealsSection()
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
                AIResearchView(coachBrief: coachBrief)
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
        }
    }

    private var planningTools: some View {
        VStack(spacing: Spacing.sm) {
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

    /// Same Pro gate as the research chat it reuses: free users get the
    /// AI paywall from the root instead of the sheet.
    private func openCoach() {
        if storeService.canAccessAIFeatures {
            showCoach = true
        } else {
            appState.presentedPaywall = .aiResearch
        }
    }

    private var coachBrief: String {
        let profile = dataStore.profile
        return NutritionCoachEngine.brief(
            NutritionCoachEngine.summary(of: profile),
            unit: profile.bodyMetrics.unit
        )
    }
}

#Preview {
    MealsContainerView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
