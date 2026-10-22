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

    private struct Cell: Identifiable {
        let id: String
        let icon: String
        let label: LocalizedStringKey
        let value: String
        let unit: String
        let spokenUnit: LocalizedStringKey
        let sample: HealthRangeService.Sample
    }

    private var cells: [Cell] {
        var cells: [Cell] = []
        if let hrv = snapshot.hrv {
            cells.append(Cell(id: "hrv", icon: "waveform.path.ecg", label: "HRV",
                              value: hrv.latest.formatted(.number.precision(.fractionLength(0))),
                              unit: "ms", spokenUnit: "milliseconds", sample: hrv))
        }
        if let rhr = snapshot.rhr {
            cells.append(Cell(id: "rhr", icon: "heart.fill", label: "RHR",
                              value: rhr.latest.formatted(.number.precision(.fractionLength(0))),
                              unit: "bpm", spokenUnit: "beats per minute", sample: rhr))
        }
        if let sleep = snapshot.sleep {
            cells.append(Cell(id: "sleep", icon: "bed.double.fill", label: "Sleep",
                              value: sleep.latest.formatted(.number.precision(.fractionLength(1))),
                              unit: "h", spokenUnit: "hours", sample: sleep))
        }
        return cells
    }

    /// Cells in rows of two. An odd last cell gets a row to itself and
    /// spans the full width instead of leaving a half-width orphan.
    private var rows: [[Cell]] {
        stride(from: 0, to: cells.count, by: 2).map { Array(cells[$0..<min($0 + 2, cells.count)]) }
    }

    var body: some View {
        if hasAnyCard {
            VStack(spacing: Spacing.sm) {
                HomeSectionHeader(eyebrow: "Biometrics", title: "Health Monitor")

                ForEach(rows, id: \.first?.id) { row in
                    HStack(spacing: Spacing.sm) {
                        ForEach(row) { cell in
                            BiometricCard(
                                icon: cell.icon,
                                label: cell.label,
                                value: cell.value,
                                unit: cell.unit,
                                spokenUnit: cell.spokenUnit,
                                sample: cell.sample
                            )
                        }
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
}
