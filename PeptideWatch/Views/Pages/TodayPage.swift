import SwiftUI

/// First page: today's habits and doses as Activity-style rings, with the
/// Atlas Score beneath. The page is tinted with the user's tier colour.
struct TodayPage: View {
    @EnvironmentObject private var store: WatchStore

    private struct Ring: Identifiable {
        let id: String
        let label: String
        let done: Int
        let total: Int
        let color: Color

        var spec: RingSpec {
            RingSpec(id: id, progress: Double(done) / Double(max(total, 1)), color: color)
        }
    }

    private var rings: [Ring] {
        let data = store.watchData
        var rings: [Ring] = []
        if let total = data.healthHabitsTotal, total > 0 {
            rings.append(Ring(id: "health", label: String(localized: "Health"),
                              done: data.healthHabitsDone ?? 0, total: total, color: WatchPalette.health))
        }
        if let total = data.trainingHabitsTotal, total > 0 {
            rings.append(Ring(id: "training", label: String(localized: "Training"),
                              done: data.trainingHabitsDone ?? 0, total: total, color: WatchPalette.training))
        }
        if data.totalToday > 0 {
            rings.append(Ring(id: "protocol", label: String(localized: "Protocol"),
                              done: data.completedToday, total: data.totalToday, color: WatchPalette.protocolDose))
        }
        return rings
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if rings.isEmpty {
                    emptyState
                } else {
                    ActivityRings(rings: rings.map(\.spec), lineWidth: rings.count > 2 ? 12 : 15)
                        .frame(maxWidth: 112)
                        .accessibilityHidden(true)
                    VStack(spacing: 4) {
                        ForEach(rings) { legendRow($0) }
                    }
                }
                atlasScore
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Today")
        .containerBackground(WatchPalette.tier(store.watchData.atlasTier).opacity(0.35).gradient, for: .tabView)
    }

    private func legendRow(_ ring: Ring) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ring.color)
                .frame(width: 7, height: 7)
            Text(ring.label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text("\(ring.done)/\(ring.total)")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ring.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.label), \(ring.done) of \(ring.total) done")
    }

    @ViewBuilder
    private var atlasScore: some View {
        let data = store.watchData
        if let score = data.atlasScore {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Atlas \(score)")
                    .monospacedDigit()
                if let level = data.atlasLevel {
                    Text("· Lv \(level)")
                }
                if let earned = data.atlasTodayEarned, earned > 0 {
                    Text("· +\(earned)")
                        .monospacedDigit()
                }
            }
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(WatchPalette.tier(data.atlasTier))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Atlas Score \(score)")
        }
    }

    private var emptyState: some View {
        let neverSynced = store.watchData.lastUpdated == .distantPast
        return VStack(spacing: 8) {
            Image(systemName: neverSynced ? "iphone.and.arrow.forward" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(neverSynced ? Color.secondary : WatchPalette.health)
            Text(neverSynced ? LocalizedStringKey("Open Atlas on your iPhone to sync.") : LocalizedStringKey("Nothing due today."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}
