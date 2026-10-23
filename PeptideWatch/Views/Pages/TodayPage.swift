import SwiftUI

/// First page: today's habits and doses as Activity-style rings, a stat
/// column under each ring's colour, and the Atlas Score. The page blooms
/// in the user's tier colour.
struct TodayPage: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.watchPageIsActive) private var isActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    ActivityRings(rings: rings.map(\.spec), lineWidth: rings.count > 2 ? 14 : 17, spacing: 3)
                        .frame(maxWidth: 132)
                        .accessibilityHidden(true)
                    statLayout {
                        ForEach(rings) { stat($0) }
                    }
                    .entrance(0)
                }
                atlasScore
                    .entrance(1)
            }
        }
        .navigationTitle("Today")
        .pageBackground(WatchPalette.tier(store.watchData.atlasTier))
    }

    /// Side by side, or stacked at accessibility text sizes where even a
    /// shrunk label no longer fits a third of the screen.
    private var statLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 4))
    }

    private func stat(_ ring: Ring) -> some View {
        StatColumn(
            value: "\(ring.done)/\(ring.total)",
            label: ring.label,
            color: ring.color,
            spoken: String(localized: "\(ring.label), \(ring.done) of \(ring.total) done")
        )
    }

    @ViewBuilder
    private var atlasScore: some View {
        let data = store.watchData
        if let score = data.atlasScore {
            let tint = WatchPalette.tier(data.atlasTier)
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, options: .repeating.speed(0.4), isActive: isActive && !reduceMotion)
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
            .accessibilityLabel(spokenScore(score, level: data.atlasLevel, earned: data.atlasTodayEarned))
        }
    }

    /// Everything the capsule shows, not just the score.
    private func spokenScore(_ score: Int, level: Int?, earned: Int?) -> String {
        var parts = [String(localized: "Atlas Score \(score)")]
        if let level { parts.append(String(localized: "level \(level)")) }
        if let earned, earned > 0 { parts.append(String(localized: "\(earned) points today")) }
        return parts.joined(separator: ", ")
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
