import SwiftUI

@main
struct PeptideWatchApp: App {
    @StateObject private var watchStore = WatchStore()

    var body: some Scene {
        WindowGroup {
            // Page TabView: Today's dose list → Stats → Nutrition
            // (when the phone has nutrition to surface). The
            // nutrition slot is hidden when `WatchData.nutrition` is
            // nil so an older phone build (pre-food-library) or a
            // fresh install doesn't show an empty third page.
            TabView {
                DoseListView()
                    .environmentObject(watchStore)
                // Stats / Nutrition need their own NavigationStack —
                // their `.navigationTitle` modifiers render nothing
                // without an enclosing navigation container, which
                // left those two pages title-less and inconsistent
                // with the Today page.
                NavigationStack {
                    WatchStatsView()
                        .environmentObject(watchStore)
                }
                if watchStore.watchData.nutrition != nil {
                    NavigationStack {
                        WatchNutritionView()
                            .environmentObject(watchStore)
                    }
                }
            }
            .tabViewStyle(.page)
        }
    }
}
