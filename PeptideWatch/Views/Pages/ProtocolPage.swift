import SwiftUI

/// Last page: today's doses, tap to log, with the dose streak and 7-day
/// adherence underneath.
struct ProtocolPage: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        let data = store.watchData
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if data.todayEntries.isEmpty {
                    Text("No doses today.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(data.completedToday) of \(data.totalToday) taken")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(WatchPalette.protocolDose)
                    ForEach(data.todayEntries) { entry in
                        DoseRowView(entry: entry)
                    }
                }
                stats(data)
            }
        }
        .navigationTitle("Protocol")
        .containerBackground(WatchPalette.protocolPage.gradient, for: .tabView)
    }

    @ViewBuilder
    private func stats(_ data: WatchData) -> some View {
        let parts = [
            data.currentStreak.map { String(localized: "\($0)-day streak") },
            data.weeklyCompliance.map { String(localized: "\(Int(($0 * 100).rounded()))% this week") },
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}
