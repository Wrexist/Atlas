import SwiftUI

@main
struct PeptideApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            TabView(selection: $appState.selectedTab) {
                Tab("Home", systemImage: "house.fill", value: .home) {
                    HomeView()
                }

                Tab("Peptides", systemImage: "flask.fill", value: .database) {
                    PeptideListView()
                }

                Tab("Protocols", systemImage: "list.clipboard.fill", value: .protocols) {
                    ProtocolListView()
                }

                Tab("Analytics", systemImage: "chart.bar.fill", value: .analytics) {
                    AnalyticsView()
                }

                Tab("Profile", systemImage: "person.fill", value: .profile) {
                    ProfileView()
                }
            }
            .tabViewBottomAccessory {
                NextDoseAccessoryView()
            }
            .environment(appState)
            .preferredColorScheme(.dark)
            .tint(AppColor.accentPrimary)
        }
    }
}

struct NextDoseAccessoryView: View {
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "syringe.fill")
                .font(.caption)
                .foregroundStyle(AppColor.accentPrimary)

            Text("Next: BPC-157 \u2022 250mcg")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)

            Spacer()

            Text("2:00 PM")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.accentLight)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
    }
}
