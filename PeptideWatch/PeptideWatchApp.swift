import SwiftUI

@main
struct PeptideWatchApp: App {
    @StateObject private var watchStore = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(watchStore)
        }
        .backgroundTask(.watchConnectivity) {
            await WatchStore.shared.drainPendingContent()
        }
    }
}
