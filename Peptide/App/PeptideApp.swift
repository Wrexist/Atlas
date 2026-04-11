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
    private var nextDose: ProtocolEntry? {
        let now = Date()
        return MockEntries.todayEntries()
            .filter { !$0.completed && $0.date > now }
            .min(by: { $0.date < $1.date })
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "syringe.fill")
                .font(.caption)
                .foregroundStyle(AppColor.accentPrimary)
            if let dose = nextDose {
                Text("Next: \(dose.peptide.abbreviation) • \(dose.dose)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text(dose.date.formatted(.dateTime.hour().minute()))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accentLight)
            } else {
                Text("All doses completed")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
    }
}
