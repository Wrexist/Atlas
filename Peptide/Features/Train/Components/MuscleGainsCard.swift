import SwiftUI

/// "Muscle gains" card — the long-horizon sibling of the weekly
/// heatmap. Shows the same anatomical figure driven by the user's
/// whole training history, switchable between two reads:
///
/// - **Regular** — how consistently each muscle gets trained: the
///   fraction of the last 12 weeks it received stimulus, mapped
///   straight onto the load ramp (purple = trained every week,
///   green = only just picked up).
/// - **Total** — accumulated working-set volume per muscle over all
///   logged sessions, normalised so the most-built muscle reads
///   purple and the least-touched green.
///
/// Both maps come precomputed from `MuscleGainsEngine` so the card
/// stays a dumb renderer and the parent controls when the expensive
/// history scan reruns.
struct MuscleGainsCard: View {

    let totals: [AnatomicalMuscle: Double]
    let regularity: [AnatomicalMuscle: Double]
    /// Weeks window behind the `regularity` map, for the stat copy.
    var regularityWeeks: Int = 12
    var onIdentify: ((AnatomicalMuscle) -> Void)? = nil

    private enum Mode: String, CaseIterable {
        case regular = "Regular"
        case total = "Total"
    }

    @State private var mode: Mode = .regular

    private var hasHistory: Bool { !totals.isEmpty }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Muscle gains")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if hasHistory {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                MuscleMapView(
                    highlights: highlights,
                    onIdentify: onIdentify
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 320)
                .animation(.easeInOut(duration: 0.4), value: mode)

                if hasHistory {
                    MuscleHeatLegend(
                        lowLabel: mode == .regular ? "Rarely" : "Least",
                        highLabel: mode == .regular ? "Every week" : "Most"
                    )
                    topGroupsRow
                }
            }
        }
    }

    private var subtitle: String {
        guard hasHistory else {
            return "Your full training history will build up here."
        }
        switch mode {
        case .regular:
            return "How consistently you've hit each muscle over the last \(regularityWeeks) weeks."
        case .total:
            return "Where you've put in the most total work, across every session."
        }
    }

    private var highlights: [AnatomicalMuscle: MuscleHighlight] {
        switch mode {
        case .regular:
            // Regularity is already a 0…1 fraction of weeks trained, so
            // it maps onto the ramp without normalising — every-week
            // work reads purple even when nothing else comes close.
            return regularity.reduce(into: [:]) { acc, pair in
                acc[pair.key] = .intensity(pair.value)
            }
        case .total:
            return MuscleMapView.intensityHighlights(from: totals)
        }
    }

    // MARK: - Top groups

    private var topGroupsRow: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(topGroups(), id: \.muscle) { item in
                statPill(for: item.muscle, value: item.value)
            }
            Spacer(minLength: 0)
        }
    }

    /// Collapse per-head values into per-group standouts. Totals sum
    /// across a group's heads (volume adds up); regularity takes the
    /// group's best head (training one quad head weekly *is* weekly
    /// quad work).
    private func topGroups() -> [(muscle: AnatomicalMuscle, value: Double)] {
        let source = mode == .regular ? regularity : totals
        var byGroup: [String: (muscle: AnatomicalMuscle, value: Double)] = [:]
        for (muscle, value) in source {
            if let existing = byGroup[muscle.displayName] {
                let merged = mode == .regular
                    ? max(existing.value, value)
                    : existing.value + value
                byGroup[muscle.displayName] = (existing.muscle, merged)
            } else {
                byGroup[muscle.displayName] = (muscle, value)
            }
        }
        return byGroup.values
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value
                                       : lhs.muscle.displayName < rhs.muscle.displayName
            }
            .prefix(3)
            .map { (muscle: $0.muscle, value: $0.value) }
    }

    private func statPill(for muscle: AnatomicalMuscle, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(muscle.displayName)
                .font(AppFont.chipText)
                .foregroundStyle(AppColor.textPrimary)
            Text(statLabel(for: value))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    private func statLabel(for value: Double) -> String {
        switch mode {
        case .regular:
            let weeks = Int((value * Double(regularityWeeks)).rounded())
            return "\(weeks)/\(regularityWeeks) weeks"
        case .total:
            let sets = Int(value.rounded())
            return "\(sets) \(sets == 1 ? "set" : "sets")"
        }
    }
}

#Preview {
    MuscleGainsCard(
        totals: [
            .pecSternal: 220, .pecClavicular: 140, .deltAnterior: 120,
            .lats: 250, .biceps: 90, .tricepsLong: 80,
            .quadRectus: 180, .glutes: 160, .hamstringMedial: 60,
            .gastrocnemius: 25, .abdominals: 40,
        ],
        regularity: [
            .pecSternal: 1.0, .pecClavicular: 0.85, .deltAnterior: 0.7,
            .lats: 0.9, .biceps: 0.5, .tricepsLong: 0.45,
            .quadRectus: 0.6, .glutes: 0.55, .hamstringMedial: 0.3,
            .gastrocnemius: 0.1, .abdominals: 0.25,
        ]
    )
    .padding()
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
