import SwiftUI

/// Method notes on demand. Recap screens lead with the result; how it was
/// counted sits one tap away in a popover instead of in permanent fine
/// print — and never in a share image.
struct RecapInfoButton<Notes: View>: View {
    let title: LocalizedStringKey
    var showsTitle = true
    @ViewBuilder let notes: Notes
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Label(title, systemImage: "info.circle")
                .labelStyle(InfoLabelStyle(showsTitle: showsTitle))
                .font(AppFont.subheadline)
                .frame(minHeight: Spacing.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: Spacing.sm) { notes }
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(idealWidth: 320, alignment: .leading)
                .padding(Spacing.lg)
                .presentationCompactAdaptation(.popover)
        }
    }

    private struct InfoLabelStyle: LabelStyle {
        let showsTitle: Bool
        func makeBody(configuration: Configuration) -> some View {
            if showsTitle {
                HStack(spacing: Spacing.xs) { configuration.icon; configuration.title }
            } else {
                configuration.icon.frame(minWidth: Spacing.minimumHitTarget)
            }
        }
    }
}

/// A one- or two-sentence recap written by the on-device model. The
/// sparkle marks it as generated; every number in it came from the recap.
struct RecapSummaryLine: View {
    let text: String
    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "sparkles").foregroundStyle(AppColor.accentPrimary)
        }
        .font(AppFont.body)
        .foregroundStyle(AppColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Summary written on device: \(text)"))
    }
}

struct RecapAction: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(AppFont.headline)
                .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
                .padding(.vertical, Spacing.xs)
                .foregroundStyle(AppColor.onAccent)
                .background(AppColor.accentFill, in: RoundedRectangle(cornerRadius: Spacing.controlCornerRadius))
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
            guard let seconds = m?.seconds, seconds.isFinite, seconds > 0 else { return String(localized: "Time unavailable") }
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: seconds) ?? String(localized: "Time unavailable")
        case .distance:
            guard let meters = m?.meters, meters.isFinite, meters > 0 else { return String(localized: "Distance unavailable") }
            let distance = unit == .imperial ? meters / 0.3048 : meters
            return distance.formatted(.number.precision(.fractionLength(0...1))) + (unit == .imperial ? " ft" : " m")
        default:
            let reps = String(localized: "\(set.reps) reps")
            guard set.reps >= 0 else { return String(localized: "Repetitions unavailable") }
            guard set.weightKg.isFinite, set.weightKg >= 0 else { return String(localized: "Load unavailable · \(reps)") }
            guard set.weightKg > 0 else { return m?.kind == .bodyweight ? String(localized: "Bodyweight × \(reps)") : reps }
            return loadedSet("\(unit.weightValue(set.weightKg, fractionDigits: 0...2)) \(unit.weightSuffix)", reps: reps, measurement: m)
        }
    }

    /// One whole sentence per role and load convention, so a translation
    /// can put the words in its own order.
    private static func loadedSet(_ weight: String, reps: String, measurement m: SetEntry.Measurement?) -> String {
        switch (m?.kind, m?.load) {
        case (.assisted, .eachPair): String(localized: "\(weight) assistance each · both counted × \(reps)")
        case (.assisted, .total): String(localized: "\(weight) assistance total × \(reps)")
        case (.assisted, .perSide): String(localized: "\(weight) assistance per side · recorded side × \(reps)")
        case (.assisted, _): String(localized: "\(weight) assistance × \(reps)")
        case (.bodyweight, .eachPair): String(localized: "\(weight) added each · both counted × \(reps)")
        case (.bodyweight, .total): String(localized: "\(weight) added total × \(reps)")
        case (.bodyweight, .perSide): String(localized: "\(weight) added per side · recorded side × \(reps)")
        case (.bodyweight, _): String(localized: "\(weight) added × \(reps)")
        case (_, .eachPair): String(localized: "\(weight) each · both counted × \(reps)")
        case (_, .total): String(localized: "\(weight) total × \(reps)")
        case (_, .perSide): String(localized: "\(weight) per side · recorded side × \(reps)")
        default: String(localized: "\(weight) × \(reps)")
        }
    }
}

struct RecapMetrics: View {
    let summary: WorkoutRecapEngine.Summary
    let unit: MeasurementUnit
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        GlassCard {
            ViewThatFits(in: .horizontal) {
                // Equal columns, so the three values sit on one grid
                // instead of hugging their own widths.
                if !typeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: Spacing.md) { metrics(horizontal: true) }
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: Spacing.lg) { metrics(horizontal: false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private func metrics(horizontal: Bool) -> some View {
        metric(String(localized: "Duration"), value: summary.duration.label, icon: "clock")
        if horizontal { Divider().frame(height: 64) }
        metric(String(localized: "Working sets"), value: summary.workingSetLabel, icon: "square.stack")
        if horizontal { Divider().frame(height: 64) }
        metric(String(localized: "Volume"), value: RecapFormat.volume(summary.volumeKg, unit: unit), icon: "dumbbell")
    }
    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: icon).foregroundStyle(AppColor.accentPrimary).accessibilityHidden(true)
            valueText(value).monospacedDigit().contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
            Text(title).font(AppFont.subheadline).foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value.replacingOccurrences(of: " " + unit.weightSuffix, with: " " + unit.weightSpokenUnit))")
    }

    /// Sets a trailing weight suffix ("12,500 kg") smaller than the number.
    /// Anything else, such as a duration of "1h 12m", stays one size.
    private func valueText(_ value: String) -> Text {
        let parts = value.split(separator: " ", maxSplits: 1)
        if parts.count == 2, String(parts[1]) == unit.weightSuffix {
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
                          primaryColor: AppColor.trainingPrimaryMuscleTint,
                          secondaryColor: AppColor.trainingSecondaryMuscleTint,
                          identifiesOnTap: false)
                .accessibilityHidden(true)
        } else {
            Label(muscles.isEmpty ? "No mapped muscles" : "Muscle illustration unavailable", systemImage: "figure.stand")
                .font(AppFont.subheadline).foregroundStyle(AppColor.textSecondary)
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
        let names = muscles.filter { $0.role == role }.map { $0.displayName }
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(role.displayName, systemImage: role == .primary ? "circle.fill" : "circle.lefthalf.filled")
                    .foregroundStyle(role == .primary ? AppColor.trainingPrimaryMuscle : AppColor.trainingSecondaryMuscle)
                Text(names.joined(separator: ", ")).foregroundStyle(AppColor.textPrimary)
            }.font(AppFont.subheadline)
        }
    }
}
