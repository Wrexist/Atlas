import SwiftUI

/// Second page, in the shape of the system Heart Rate app: a heart beating
/// at the user's resting rate on deep red, the number below it, and HRV
/// and Recovery on one line underneath.
struct RecoveryPage: View {
    let vitals: WatchVitalsSnapshot
    @State private var showsDetail = false

    private enum HeroKind { case restingHeartRate, recovery, hrv }

    private struct Hero {
        let kind: HeroKind
        let label: String
        let value: Int
        let unit: String
        let spoken: String
    }

    /// Resting heart rate leads when there is one, because it's what the
    /// heart is beating at. Otherwise the best metric that is present.
    private var hero: Hero? {
        if let rhr = vitals.restingHeartRate {
            return Hero(kind: .restingHeartRate, label: String(localized: "Resting"), value: rhr,
                        unit: String(localized: "BPM"),
                        spoken: String(localized: "Resting heart rate \(rhr) beats per minute"))
        }
        if let score = vitals.recoveryScore {
            return Hero(kind: .recovery, label: String(localized: "Recovery"), value: score, unit: "%",
                        spoken: String(localized: "Recovery \(score) percent"))
        }
        if let hrv = vitals.hrv {
            return Hero(kind: .hrv, label: String(localized: "HRV"), value: hrv,
                        unit: String(localized: "MS"),
                        spoken: String(localized: "Heart rate variability \(hrv) milliseconds"))
        }
        return nil
    }

    /// Whatever the hero didn't take.
    private var supporting: String {
        var parts: [String] = []
        if hero?.kind == .restingHeartRate, let score = vitals.recoveryScore {
            parts.append(String(localized: "Recovery \(score)"))
        }
        if hero?.kind != .hrv, let hrv = vitals.hrv {
            parts.append(String(localized: "HRV \(hrv) ms"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                PulsingHeart(bpm: vitals.restingHeartRate ?? 60, size: 56)
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)

                if let hero {
                    Text(hero.label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    MetricReadout(value: "\(hero.value)", unit: hero.unit,
                                  tint: WatchPalette.heart, accessibilityText: hero.spoken)
                }
                if !supporting.isEmpty {
                    Text(supporting)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .monospacedDigit()
                }
                Text("Updated \(vitals.measuredAt, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Recovery")
        .containerBackground(WatchPalette.heartPage.gradient, for: .tabView)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsDetail = true
                } label: {
                    Image(systemName: "waveform.path.ecg")
                }
                .accessibilityLabel("Recovery details")
            }
        }
        .sheet(isPresented: $showsDetail) {
            RecoveryDetailView(vitals: vitals)
        }
    }
}

private struct RecoveryDetailView: View {
    let vitals: WatchVitalsSnapshot

    var body: some View {
        List {
            if let score = vitals.recoveryScore {
                row("Recovery", value: "\(score)", baseline: nil)
            }
            if let hrv = vitals.hrv {
                row("HRV", value: "\(hrv) ms", baseline: vitals.hrvBaseline.map { "\($0) ms" })
            }
            if let rhr = vitals.restingHeartRate {
                row("Resting heart rate", value: "\(rhr) bpm",
                    baseline: vitals.restingHeartRateBaseline.map { "\($0) bpm" })
            }
            if let sleep = vitals.sleep {
                row("Sleep", value: WatchFormat.duration(minutes: sleep.asleepMinutes), baseline: nil)
            }
            Text("Recovery weighs your 3-day HRV and resting heart rate against your 30-day baseline, plus last night's sleep.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        .navigationTitle("Recovery")
    }

    private func row(_ title: LocalizedStringKey, value: String, baseline: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(WatchPalette.heart)
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            if let baseline {
                Text("30-day average \(baseline)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
