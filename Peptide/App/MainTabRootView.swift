import SwiftUI
import UIKit

/// iPad: single navigation stack with sidebar tab picker. iPhone: tab bar only (each tab owns `NavigationStack`).
struct MainTabRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        if UIDevice.current.userInterfaceIdiom == .pad {
            NavigationSplitView {
                List(selection: $appState.selectedTab) {
                    tabRow(.home, title: "Home", systemImage: "house.fill")
                    tabRow(.database, title: "Peptides", systemImage: "flask.fill")
                    tabRow(.protocols, title: "Protocols", systemImage: "list.clipboard.fill")
                    tabRow(.analytics, title: "Analytics", systemImage: "chart.bar.fill")
                    tabRow(.profile, title: "Profile", systemImage: "person.fill")
                }
                .navigationTitle("PeptideX")
                .tint(AppColor.accentPrimary)
            } detail: {
                tabDetail(for: appState.selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            TabView(selection: $appState.selectedTab) {
                Tab("Home", systemImage: "house.fill", value: .home) {
                    HomeRootView()
                }
                Tab("Peptides", systemImage: "flask.fill", value: .database) {
                    PeptideListRootView()
                }
                Tab("Protocols", systemImage: "list.clipboard.fill", value: .protocols) {
                    ProtocolListRootView()
                }
                Tab("Analytics", systemImage: "chart.bar.fill", value: .analytics) {
                    AnalyticsRootView()
                }
                Tab("Profile", systemImage: "person.fill", value: .profile) {
                    ProfileRootView()
                }
            }
        }
    }

    @ViewBuilder
    private func tabRow(_ tab: AppTab, title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .tag(tab)
    }

    @ViewBuilder
    private func tabDetail(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeRootView()
        case .database: PeptideListRootView()
        case .protocols: ProtocolListRootView()
        case .analytics: AnalyticsRootView()
        case .profile: ProfileRootView()
        }
    }

}
