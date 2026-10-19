import SwiftUI

struct RecapCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.recapCard, in: RoundedRectangle(cornerRadius: Spacing.cardCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius)
                .stroke(AppColor.recapBorder, lineWidth: 1))
    }
}

struct RecapAction: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(AppFont.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(AppColor.recapButtonInk)
                .background(AppColor.recapButton, in: RoundedRectangle(cornerRadius: Spacing.controlCornerRadius))
        }
        .buttonStyle(.plain)
    }
}

enum RecapFormat {
    static func volume(_ kg: Double?, unit: MeasurementUnit) -> String {
        guard let kg else { return "—" }
        return unit.weightForDisplay(kg).formatted(.number.precision(.fractionLength(0))) + " " + unit.weightSuffix
    }
    static func set(_ set: SetEntry, unit: MeasurementUnit) -> String {
        let m = set.measurement
        switch m?.kind {
        case .timed:
            guard let seconds = m?.seconds, seconds.isFinite, seconds > 0 else { return "Time unavailable" }
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: seconds) ?? "Time unavailable"
        case .distance:
            guard let meters = m?.meters, meters.isFinite, meters > 0 else { return "Distance unavailable" }
            let distance = unit == .imperial ? meters / 0.3048 : meters
            return distance.formatted(.number.precision(.fractionLength(0...1))) + (unit == .imperial ? " ft" : " m")
        default:
            let reps = set.reps.formatted() + " reps"
            guard set.reps >= 0 else { return "Repetitions unavailable" }
            guard set.weightKg.isFinite, set.weightKg >= 0 else { return "Load unavailable · " + reps }
            guard set.weightKg > 0 else { return m?.kind == .bodyweight ? "Bodyweight × " + reps : reps }
            let load = unit.weightForDisplay(set.weightKg).formatted(.number.precision(.fractionLength(0...1)))
            let convention: String
            switch m?.load {
            case .eachPair: convention = " each · both counted"
            case .total: convention = " total"
            case .perSide: convention = " per side · recorded side"
            default: convention = " recorded"
            }
            let role = m?.kind == .assisted ? " assistance" : (m?.kind == .bodyweight ? " added" : "")
            return "\(load) \(unit.weightSuffix)\(role)\(convention) × \(reps)"
        }
    }
}

struct RecapNewPRs: View {
    let prs: [PRDetectionEngine.DetectedPR]
    let entries: [WorkoutRecapEngine.Entry]
    let unit: MeasurementUnit
    @State private var celebrated = false

    var body: some View {
        if !prs.isEmpty {
            RecapCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Label {
                        Text(prs.count == 1 ? "New PR" : "\(prs.count) new PRs").font(AppFont.headline)
                    } icon: {
                        Image(systemName: "trophy.fill").foregroundStyle(AppColor.recapSuccess)
                            .symbolEffect(.bounce, value: celebrated)
                    }
                    ForEach(prs, id: \.self) { pr in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(name(for: pr)).font(AppFont.subheadline)
                                Text(title(for: pr.kind)).font(AppFont.caption)
                                    .foregroundStyle(AppColor.recapSecondary)
                            }
                            Spacer()
                            Text(value(for: pr)).font(AppFont.headline).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .onAppear { celebrated = true }
        }
    }

    private func name(for pr: PRDetectionEngine.DetectedPR) -> String {
        entries.first { $0.exerciseID == pr.exerciseID }?.name ?? pr.exerciseID
    }

    private func title(for kind: PRDetectionEngine.DetectedPR.Kind) -> String {
        switch kind {
        case .estimatedOneRepMax: String(localized: "Estimated 1RM")
        case .absoluteWeight: String(localized: "Heaviest set")
        case .sessionVolume: String(localized: "Exercise volume")
        case .bodyweightReps: String(localized: "Most reps")
        }
    }

    private func value(for pr: PRDetectionEngine.DetectedPR) -> String {
        guard pr.kind != .bodyweightReps else { return Int(pr.value).formatted() + " reps" }
        return unit.weightForDisplay(pr.value).formatted(.number.precision(.fractionLength(0...1)))
            + " " + unit.weightSuffix
    }
}

struct RecapMetrics: View {
    let summary: WorkoutRecapEngine.Summary
    let unit: MeasurementUnit
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        RecapCard {
            ViewThatFits(in: .horizontal) {
                if !typeSize.isAccessibilitySize {
                    HStack(spacing: Spacing.md) { metrics(horizontal: true) }
                        .fixedSize(horizontal: true, vertical: true)
                }
                VStack(alignment: .leading, spacing: Spacing.lg) { metrics(horizontal: false) }
            }
        }
    }
    @ViewBuilder private func metrics(horizontal: Bool) -> some View {
        metric("Duration", value: summary.duration.label, icon: "clock")
        if horizontal { Divider().frame(height: 64) }
        metric("Working sets", value: summary.workingSetLabel, icon: "square.stack")
        if horizontal { Divider().frame(height: 64) }
        metric("Volume", value: RecapFormat.volume(summary.volumeKg, unit: unit), icon: "dumbbell")
    }
    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: icon).foregroundStyle(AppColor.recapAction).accessibilityHidden(true)
            valueText(value).monospacedDigit().contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
            Text(title).font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value.replacingOccurrences(of: " " + unit.weightSuffix, with: " " + unit.weightSpokenUnit))")
    }

    private func valueText(_ value: String) -> Text {
        let parts = value.split(separator: " ", maxSplits: 1)
        // Split only "1,240 kg" — a duration like "1h 12m" is one value.
        if parts.count == 2, parts[1] == unit.weightSuffix {
            return Text(String(parts[0])).font(AppFont.title)
                + Text(" " + String(parts[1])).font(AppFont.subheadline)
        }
        return Text(value).font(AppFont.title)
    }
}

enum RecapMuscles {
    static func highlights(_ muscles: [WorkoutRecapEngine.Muscle]) -> [AnatomicalMuscle: MuscleHighlight] {
        var result: [AnatomicalMuscle: MuscleHighlight] = [:]
        // Raw catalog groups only. No exercise-name guesses about muscle heads.
        for muscle in muscles {
            for region in AnatomicalMuscle.headWeights(forRawMuscle: muscle.name).keys {
                if muscle.role == .primary { result[region] = .primary }
                else if result[region] != .primary { result[region] = .secondary }
            }
        }
        return result
    }
}

struct RecapAnatomy: View {
    let muscles: [WorkoutRecapEngine.Muscle]
    /// Ignite the figure on appear. Off for snapshot renders (share card).
    var animatesReveal = false
    var body: some View {
        if TrainingAnatomy.isAvailable, !muscles.isEmpty, animatesReveal {
            StagedMuscleMap(highlights: RecapMuscles.highlights(muscles), identifiesOnTap: false)
                .accessibilityHidden(true)
        } else if TrainingAnatomy.isAvailable, !muscles.isEmpty {
            MuscleMapView(highlights: RecapMuscles.highlights(muscles),
                          primaryColor: AppColor.trainingPrimaryMuscle,
                          secondaryColor: AppColor.trainingSecondaryMuscle,
                          identifiesOnTap: false)
                .accessibilityHidden(true)
        } else {
            Label(muscles.isEmpty ? "No mapped muscles" : "Muscle illustration unavailable", systemImage: "figure.stand")
                .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
        }
    }
}

struct RecapMuscleNames: View {
    let muscles: [WorkoutRecapEngine.Muscle]
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            names(.primary)
            names(.supporting)
        }
    }
    @ViewBuilder private func names(_ role: WorkoutRecapEngine.Role) -> some View {
        let names = muscles.filter { $0.role == role }.map { $0.name.capitalized }
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(role.rawValue, systemImage: role == .primary ? "circle.fill" : "circle.lefthalf.filled")
                    .foregroundStyle(role == .primary ? AppColor.trainingPrimaryMuscle : AppColor.trainingSecondaryMuscle)
                Text(names.joined(separator: ", ")).foregroundStyle(AppColor.recapText)
            }.font(AppFont.subheadline)
        }
    }
}
