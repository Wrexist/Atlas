import SwiftUI

/// Second page of the Watch app. Surfaces the same streak / weekly
/// compliance / lifetime-dose stats the Profile tab shows on the
/// phone, scaled down for a 41-44 mm screen. Values come over the
/// existing WatchConnectivity pipeline as optional fields on
/// `WatchData`; an older phone build that doesn't write them yet
/// renders dashes rather than zeros so the user can tell "no data
/// synced" apart from "you really have zero".
struct WatchStatsView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                weeklyRing
                streakRow
                totalRow
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Weekly compliance ring

    private var weeklyRing: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: weeklyComplianceFraction)
                    .stroke(
                        AngularGradient(
                            colors: [.green, .mint, .green],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(weeklyComplianceDisplay)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("7d")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 90, height: 90)

            Text("Weekly compliance")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var weeklyComplianceFraction: Double {
        store.watchData.weeklyCompliance ?? 0
    }

    private var weeklyComplianceDisplay: String {
        guard let value = store.watchData.weeklyCompliance else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    // MARK: - Streak

    private var streakRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(streakDisplay)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Current streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var streakDisplay: String {
        guard let value = store.watchData.currentStreak else { return "—" }
        return value == 1 ? "1 day" : "\(value) days"
    }

    // MARK: - Total doses logged

    private var totalRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(totalDisplay)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Doses logged")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var totalDisplay: String {
        guard let value = store.watchData.totalDosesLogged else { return "—" }
        return "\(value)"
    }
}
