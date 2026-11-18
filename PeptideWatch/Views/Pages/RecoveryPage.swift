import SwiftUI

/// Second page, in the shape of the system Heart Rate app: a heart beating
/// at the user's resting rate with a ripple on every beat, a live ECG strip
/// in step with it, the number below, and Recovery and HRV as capsules.
/// Without a resting heart rate the heart holds still and the strip is
/// hidden, rather than beating at an invented rate.
struct RecoveryPage: View {
    let vitals: WatchVitalsSnapshot
    @State private var showsDetail = false

    private static let staleOpacity = 0.55

    private enum HeroKind { case restingHeartRate, recovery, hrv }

    private struct Hero {
        let kind: HeroKind
        let label: String
        let value: Int
        let unit: String
        let spoken: String
    }

    /// Resting heart rate leads when there is one, because it's what the
    /// heart is beating at. Otherwise the best metric that is present. A
    /// stale recovery score is left out, as the complication leaves it
    /// out, rather than shown as today's.
    private func hero(stale: Bool) -> Hero? {
        if let rhr = vitals.restingHeartRate {
            return Hero(kind: .restingHeartRate, label: String(localized: "Resting"), value: rhr,
                        unit: String(localized: "BPM"),
                        spoken: String(localized: "Resting heart rate \(rhr) beats per minute"))
        }
        if !stale, let score = vitals.recoveryScore {
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

    /// Whatever the hero didn't take, as small capsules under the number.
    private func chips(for hero: Hero?, stale: Bool) -> [String] {
        var chips: [String] = []
        if !stale, hero?.kind == .restingHeartRate, let score = vitals.recoveryScore {
            chips.append(String(localized: "Recovery \(WatchFormat.recovery(score))"))
        }
        if hero?.kind != .hrv, let hrv = vitals.hrv {
            chips.append(String(localized: "HRV \(hrv) ms"))
        }
        return chips
    }

    var body: some View {
        // Re-rendered each minute so the age, and whether the readings
        // are too old to pass as today's, keep up with the clock.
        TimelineView(.everyMinute) { context in
            content(stale: vitals.isStale(at: context.date))
        }
        .navigationTitle("Recovery")
        .pageBackground(WatchPalette.heart)
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

    /// Old readings lead with their age, at full weight, and the numbers
    /// below are dimmed, so all of them read as last measured rather
    /// than as this morning's.
    private func content(stale: Bool) -> some View {
        let hero = self.hero(stale: stale)
        let chips = self.chips(for: hero, stale: stale)
        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                PulsingHeart(bpm: vitals.restingHeartRate, size: 50)
                    .frame(maxWidth: .infinity)
                if let bpm = vitals.restingHeartRate {
                    ECGTrace(bpm: bpm)
                        .frame(height: 26)
                        .padding(.bottom, 2)
                }
                if stale {
                    updatedLine
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .entrance(0)
                }

                if let hero {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(hero.label.uppercased())
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        MetricReadout(value: hero.value, unit: hero.unit,
                                      tint: WatchPalette.heart, accessibilityText: hero.spoken)
                    }
                    .opacity(stale ? Self.staleOpacity : 1)
                    .entrance(0)
                }
                if !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(WatchPalette.heart.opacity(0.18)))
                        }
                    }
                    .opacity(stale ? Self.staleOpacity : 1)
                    .entrance(1)
                }
                if !stale {
                    updatedLine
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .entrance(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var updatedLine: Text {
        Text("Updated \(vitals.measuredAt.formatted(.relative(presentation: .named)))")
    }
}

private struct RecoveryDetailView: View {
    let vitals: WatchVitalsSnapshot

    var body: some View {
        List {
            if let score = vitals.recoveryScore {
                row("Recovery", value: WatchFormat.recovery(score), baseline: nil)
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
