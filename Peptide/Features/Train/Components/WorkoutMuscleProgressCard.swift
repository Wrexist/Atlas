import SwiftUI

/// The live workout's muscles on the Train overview's heat scale: each
/// completed working set warms the muscles it trained, and a bar per
/// muscle shows the sets done against the sets planned.
struct WorkoutMuscleProgressCard: View {
    let session: WorkoutSession

    @State private var library = ExerciseLibrary.shared
    @State private var facing: BodyFacing = .both
    @State private var inspectedMuscle: AnatomicalMuscle?

    private var progress: WorkoutMuscleProgressEngine.Progress {
        WorkoutMuscleProgressEngine.progress(of: session) { library.lookup(id: $0) }
    }

    private var highlights: [AnatomicalMuscle: MuscleHighlight] {
        MuscleMapView.intensityHighlights(from: WorkoutMuscleProgressEngine.frequencies(of: session, library: library))
    }

    var body: some View {
        let progress = progress
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header(progress)
                TrainingBodyExplorer(
                    highlights: highlights,
                    side: $facing,
                    legend: .intensity(low: String(localized: "Less"), high: String(localized: "Most")),
                    onIdentify: { inspectedMuscle = $0 }
                )
                .frame(maxWidth: .infinity)
                if !progress.rows.isEmpty {
                    VStack(spacing: Spacing.md) {
                        ForEach(progress.rows) { row in
                            WorkoutMuscleProgressRow(row: row, maxDone: progress.maxDone)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("workout-muscle-progress")
        .task { await library.load() }
        .sheet(item: $inspectedMuscle) { muscle in
            MuscleHistorySheet(
                muscle: muscle,
                history: WeeklyMuscleHeatmap.history(for: muscle, from: [session], library: library, days: nil),
                periodLabel: String(localized: "This workout")
            )
        }
    }

    private func header(_ progress: WorkoutMuscleProgressEngine.Progress) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Muscles this workout")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(caption(progress))
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(progress.doneSets)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if progress.plannedSets > 0 {
                Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                    .font(AppFont.statHeader)
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: progress.fraction))
                    .accessibilityLabel(Text("\(Int((progress.fraction * 100).rounded())) percent of the workout done"))
            }
            if !highlights.isEmpty {
                BodyFacingButton(facing: $facing)
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: progress.doneSets)
    }

    private func caption(_ progress: WorkoutMuscleProgressEngine.Progress) -> LocalizedStringKey {
        guard progress.plannedSets > 0 else { return "Add sets to see your muscles fill in." }
        if progress.doneSets == 0 { return "Complete a working set to light up your muscles." }
        return "\(progress.doneSets) of \(progress.plannedSets) sets"
    }
}

/// "Chest · 3 of 8 sets" with a bar in the map's colour for that muscle,
/// so the warmest muscle on the figure is also the warmest bar.
private struct WorkoutMuscleProgressRow: View {
    let row: WorkoutMuscleProgressEngine.Row
    let maxDone: Int

    private var intensity: Double { maxDone > 0 ? Double(row.done) / Double(maxDone) : 0 }
    private var filled: Double { Double(row.done) / Double(max(row.planned, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(row.target.displayName)
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: Spacing.sm)
                HStack(spacing: Spacing.xxs) {
                    Text("\(row.done) of \(row.planned) sets")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(row.done)))
                    if row.isComplete {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(AppColor.accentPrimary)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.track)
                    Capsule()
                        .fill(MuscleMapView.heatColor(for: intensity).opacity(MuscleMapView.heatStrength(for: intensity)))
                        .frame(width: proxy.size.width * min(filled, 1))
                }
            }
            .frame(height: Spacing.sm)
            .accessibilityHidden(true)
        }
        .appAnimation(AppAnimation.springSnappy, value: row.done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(row.target.displayName), \(row.done) of \(row.planned) sets"))
    }
}
