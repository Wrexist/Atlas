import SwiftUI

@main
struct PeptideWatchApp: App {
    @StateObject private var watchStore = WatchStore()

    var body: some Scene {
        WindowGroup {
            DoseListView()
                .environmentObject(watchStore)
        }
    }
}
