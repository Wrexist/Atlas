import SwiftUI

@main
struct PeptideWatchApp: App {
    @StateObject private var watchStore = WatchStore()

    var body: some Scene {
        WindowGroup {
            // Two-page TabView: swipe left from Today's dose list to the
            // Stats page (weekly ring + streak + lifetime doses). The
            // page-indicator dots make the additional surface
            // discoverable without taking persistent screen real estate.
            TabView {
                DoseListView()
                    .environmentObject(watchStore)
                WatchStatsView()
                    .environmentObject(watchStore)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
}
