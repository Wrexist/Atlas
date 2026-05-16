import SwiftUI

/// 2-column grid of BiometricCards under the Today scroll. Pulls
/// HRV / RHR / Sleep snapshots from HealthRangeService — each cell
/// shows latest value + personal-range indicator. Cards hide
/// individually when they don't have at least 7 days of data, so a
/// new user with one day of HealthKit sees an empty grid (or
/// nothing) rather than three misleading "at the midpoint" tiles.
struct HealthMonitorGrid: View {
    let snapshot: HealthRangeService.Snapshot

    private var hasAnyCard: Bool {
        snapshot.hrv != nil || snapshot.rhr != nil || snapshot.sleep != nil
    }

    var body: some View {
        if hasAnyCard {
            VStack(spacing: Spacing.sm) {
                HomeSectionHeader(eyebrow: "BIOMETRICS", title: "Health Monitor")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Spacing.sm),
                        GridItem(.flexible(), spacing: Spacing.sm),
                    ],
                    spacing: Spacing.sm
                ) {
                    if let hrv = snapshot.hrv {
                        BiometricCard(
                            icon: "waveform.path.ecg",
                            label: "HRV",
                            value: hrv.latest.formatted(.number.precision(.fractionLength(0))),
                            unit: "ms",
                            sample: hrv
                        )
                    }
                    if let rhr = snapshot.rhr {
                        BiometricCard(
                            icon: "heart.fill",
                            label: "RHR",
                            value: rhr.latest.formatted(.number.precision(.fractionLength(0))),
                            unit: "bpm",
                            sample: rhr
                        )
                    }
                    if let sleep = snapshot.sleep {
                        BiometricCard(
                            icon: "bed.double.fill",
                            label: "Sleep",
                            value: sleep.latest.formatted(.number.precision(.fractionLength(1))),
                            unit: "h",
                            sample: sleep
                        )
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
}
