import SwiftUI

/// Last page: today's adherence as a filling bar, the doses to tap, and
/// the dose streak and 7-day adherence underneath.
struct ProtocolPage: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.watchPageIsActive) private var isActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        let data = store.watchData
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if data.todayEntries.isEmpty {
                    Text(data.awaitsToday(at: .now)
                         ? LocalizedStringKey("Open Atlas on your iPhone to load today.")
                         : LocalizedStringKey("No doses today."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    header(data)
                    ForEach(Array(data.todayEntries.enumerated()), id: \.element.id) { index, entry in
                        DoseRowView(entry: entry)
                            .entrance(index)
                    }
                }
                stats(data)
                    .entrance(data.todayEntries.count)
            }
        }
        .navigationTitle("Protocol")
        .pageBackground(WatchPalette.protocolDose)
        .onAppear { filled = isActive }
        .onChange(of: isActive) { filled = isActive }
    }

    /// "2 of 3 taken" over a bar that fills to today's adherence each time
    /// the page comes on screen.
    private func header(_ data: WatchData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(data.completedToday) of \(data.totalToday) taken")
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(WatchPalette.protocolDose)
                .contentTransition(.numericText())
                .animation(WatchMotion.update, value: data.completedToday)
            GeometryReader { proxy in
                Capsule()
                    .fill(WatchPalette.protocolDose.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(WatchPalette.protocolDose)
                            .frame(width: proxy.size.width * (filled ? data.compliance : 0))
                    }
            }
            .frame(height: 5)
            .animation(reduceMotion ? nil : WatchMotion.entrance, value: filled)
            .animation(WatchMotion.update, value: data.compliance)
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(data.completedToday) of \(data.totalToday) doses taken")
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
