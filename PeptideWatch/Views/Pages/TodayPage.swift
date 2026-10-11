import SwiftUI

/// First page: today's habits and doses as Activity-style rings, a stat
/// column under each ring's colour, and the Atlas Score. The page blooms
/// in the user's tier colour.
struct TodayPage: View {
    @EnvironmentObject private var store: WatchStore

    private struct Ring: Identifiable {
        let id: String
        let label: String
        let symbol: String
        let done: Int
        let total: Int
        let color: Color

        var spec: RingSpec {
            RingSpec(id: id, progress: Double(done) / Double(max(total, 1)), color: color, symbol: symbol)
        }
    }

    private var rings: [Ring] {
        let data = store.watchData
        var rings: [Ring] = []
        if let total = data.healthHabitsTotal, total > 0 {
            rings.append(Ring(id: "health", label: String(localized: "Health"), symbol: "heart.fill",
                              done: data.healthHabitsDone ?? 0, total: total, color: WatchPalette.health))
        }
        if let total = data.trainingHabitsTotal, total > 0 {
            rings.append(Ring(id: "training", label: String(localized: "Training"), symbol: "figure.run",
                              done: data.trainingHabitsDone ?? 0, total: total, color: WatchPalette.training))
        }
        if data.totalToday > 0 {
            rings.append(Ring(id: "protocol", label: String(localized: "Protocol"), symbol: "pills.fill",
                              done: data.completedToday, total: data.totalToday, color: WatchPalette.protocolDose))
        }
        return rings
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if rings.isEmpty {
                    emptyState
                } else {
                    ActivityRings(rings: rings.map(\.spec), lineWidth: rings.count > 2 ? 15 : 18)
                        .frame(maxWidth: 132)
                        .accessibilityHidden(true)
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(rings) { stat($0) }
                    }
                }
                atlasScore
            }
        }
        .navigationTitle("Today")
        .pageBackground(WatchPalette.tier(store.watchData.atlasTier))
    }

    private func stat(_ ring: Ring) -> some View {
        VStack(spacing: 0) {
            Text("\(ring.done)/\(ring.total)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(ring.color)
                .contentTransition(.numericText())
                .animation(.snappy, value: ring.done)
            Text(ring.label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.label), \(ring.done) of \(ring.total) done")
    }

    @ViewBuilder
    private var atlasScore: some View {
        let data = store.watchData
        if let score = data.atlasScore {
            let tint = WatchPalette.tier(data.atlasTier)
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, options: .repeating.speed(0.4))
                RollingNumber(value: score)
                if let level = data.atlasLevel {
                    Text("Lv \(level)")
                        .foregroundStyle(tint.opacity(0.7))
                }
                if let earned = data.atlasTodayEarned, earned > 0 {
                    Text("+\(earned)")
                        .monospacedDigit()
                        .foregroundStyle(WatchPalette.health)
                }
            }
            .font(.system(.footnote, design: .rounded, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.16)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Atlas Score \(score)")
        }
    }

    private var emptyState: some View {
        let neverSynced = store.watchData.lastUpdated == .distantPast
        return VStack(spacing: 8) {
            Image(systemName: neverSynced ? "iphone.and.arrow.forward" : "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(neverSynced ? Color.secondary : WatchPalette.health)
                .symbolEffect(.bounce, value: neverSynced)
            Text(neverSynced ? LocalizedStringKey("Open Atlas on your iPhone to sync.") : LocalizedStringKey("Nothing due today."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}
