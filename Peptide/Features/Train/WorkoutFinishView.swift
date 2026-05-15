import SwiftUI

/// Celebration / summary screen presented when the user taps Finish
/// on an active workout. Pulses the muscles the session targeted,
/// surfaces PRs detected on save, lists per-exercise volume, and
/// offers a "Done" button that returns to the Train tab.
struct WorkoutFinishView: View {
    let session: WorkoutSession
    let onClose: () -> Void

    @State private var library = ExerciseLibrary.shared
    @State private var prDetections: [PRDetectionEngine.DetectedPR] = []

    private var muscleHighlights: [AnatomicalMuscle: MuscleHighlight] {
        var primary = Set<AnatomicalMuscle>()
        var secondary = Set<AnatomicalMuscle>()
        for entry in session.exercises {
            guard let ex = library.lookup(id: entry.exerciseID) else { continue }
            primary.formUnion(AnatomicalMuscle.regions(forRawMuscles: ex.primaryMuscles))
            secondary.formUnion(AnatomicalMuscle.regions(forRawMuscles: ex.secondaryMuscles))
        }
        secondary.subtract(primary)
        var map: [AnatomicalMuscle: MuscleHighlight] = [:]
        for m in secondary { map[m] = .secondary }
        for m in primary   { map[m] = .primary }
        return map
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                hero
                MuscleMapView(highlights: muscleHighlights)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 320)
                statsRow
                if !prDetections.isEmpty {
                    prsCard
                }
                exercisesList
                doneButton
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.lg)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Workout complete")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // The active-workout finish path already ran the detection
            // engine; rerun a fresh ingest is idempotent (the engine
            // only writes when values increase) so the finish screen
            // can render PRs even if the user reopened it.
            prDetections = PRDetectionEngine.shared.ingest(session: session)
            if UIAccessibility.isReduceMotionEnabled == false {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color(red: 0.30, green: 0.80, blue: 0.50))
            Text(session.name ?? "Workout complete")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(session.startedAt.formatted(date: .complete, time: .shortened))
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: Spacing.sm) {
            stat(label: "Duration", value: durationFormatted)
            stat(label: "Sets", value: "\(session.completedSetCount)")
            stat(label: "Volume", value: "\(Int(session.totalVolumeKg.rounded())) kg")
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppFont.statValueSmall)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    private var prsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(AppColor.achievement)
                    Text("\(prDetections.count) new \(prDetections.count == 1 ? "PR" : "PRs")")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                }
                ForEach(prDetections, id: \.self) { pr in
                    HStack {
                        Text(library.lookup(id: pr.exerciseID)?.name ?? pr.exerciseID)
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(prSummary(pr))
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(AppColor.achievement)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func prSummary(_ pr: PRDetectionEngine.DetectedPR) -> String {
        switch pr.kind {
        case .estimatedOneRepMax: return "e1RM \(Int(pr.value.rounded())) kg"
        case .absoluteWeight:     return "Top set \(Int(pr.value.rounded())) kg"
        case .sessionVolume:      return "Volume \(Int(pr.value.rounded())) kg"
        }
    }

    private var exercisesList: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Exercises")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                ForEach(session.exercises) { entry in
                    HStack {
                        Text(library.lookup(id: entry.exerciseID)?.name ?? entry.exerciseID)
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        let workingSets = entry.sets.filter { $0.completed && !$0.isWarmup }.count
                        Text("\(workingSets) sets · \(Int(entry.workingVolumeKg.rounded())) kg")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .monospacedDigit()
                    }
                    if entry.id != session.exercises.last?.id {
                        Divider().background(AppColor.glassBorder.opacity(0.5))
                    }
                }
            }
        }
    }

    private var doneButton: some View {
        Button(action: onClose) {
            Text("Done")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.accentPrimary)
                )
        }
        .buttonStyle(.plain)
    }

    private var durationFormatted: String {
        let seconds = session.elapsedSeconds()
        let mins = seconds / 60
        let hrs = mins / 60
        if hrs > 0 {
            return String(format: "%dh %dm", hrs, mins % 60)
        }
        return "\(mins)m"
    }
}
