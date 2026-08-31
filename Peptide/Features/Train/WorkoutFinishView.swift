import SwiftUI

/// Celebration / summary screen presented when the user taps Finish
/// on an active workout. Pulses the muscles the session targeted,
/// surfaces PRs detected on save, lists per-exercise volume, and
/// offers a "Done" button that returns to the Train tab.
struct WorkoutFinishView: View {
    let session: WorkoutSession
    /// PRs detected at finish-time, passed in by the caller. The
    /// PRDetectionEngine mutates record state on first ingest and
    /// returns [] on every subsequent call — re-running ingest in
    /// .onAppear (the previous behaviour) meant the celebrations
    /// row was always empty because the engine had already run in
    /// WorkoutSessionService.finishWorkout. Audit Train H4.
    let detectedPRs: [PRDetectionEngine.DetectedPR]
    /// Session volume and PR values are stored in kilograms; this is
    /// what turns them back into the unit the user logs in.
    let unit: MeasurementUnit
    /// Count of workout sessions in the trailing 7 days, this one
    /// included — computed by the caller (`ActiveWorkoutView`, the same
    /// window `WeeklyMuscleHeatmap` uses) and turned into copy by
    /// `WorkoutConsistencyEngine`. `nil` suppresses the callout for a
    /// caller that hasn't computed it.
    var weeklySessionCount: Int? = nil
    let onClose: () -> Void

    @State private var library = ExerciseLibrary.shared

    private var muscleHighlights: [AnatomicalMuscle: MuscleHighlight] {
        let exercises = session.exercises.compactMap { library.lookup(id: $0.exerciseID) }
        return MuscleMapView.highlights(forExercises: exercises)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                hero
                MuscleMapView(highlights: muscleHighlights)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 320)
                statsRow
                if !detectedPRs.isEmpty {
                    prsCard
                }
                exercisesList
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.lg)
        }
        // Done was the last item inside the scroll view, so after a long
        // session you scrolled past the muscle map, the stats, the PR card
        // and every exercise to reach the only way out of the screen.
        .pinnedFooter {
            doneButton
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Workout complete")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Haptic on landing; the PR list comes from the caller's
            // detectedPRs param (we no longer re-ingest here).
            // Reduce-motion guards the *visual* bounce — haptics
            // should fire regardless, so this guard now wraps
            // animation hooks only (audit Train M7).
            Haptics.success()
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(AppColor.positive)
            Text(session.name ?? "Workout complete")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(session.startedAt.formatted(date: .complete, time: .shortened))
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            if let consistencyCallout {
                Text(consistencyCallout)
                    .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.top, 2)
            }
        }
    }

    /// "3rd workout this week — you're building consistency." Shown at
    /// the single highest-motivation moment in the training loop, right
    /// alongside PRs rather than only in the Train tab's retrospective
    /// heatmap.
    private var consistencyCallout: String? {
        guard let weeklySessionCount else { return nil }
        return WorkoutConsistencyEngine.callout(sessionsInTrailingWeek: weeklySessionCount)
    }

    /// One card, not three loose tiles.
    ///
    /// These are peers — no one of them is "the" number — so they keep equal
    /// weight rather than being given a headline. What changes is that they
    /// now read as a single summary of the session instead of three separate
    /// boxes that happen to sit in a row.
    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(label: "Duration", value: durationFormatted)
            divider
            stat(label: "Sets", value: "\(session.completedSetCount)")
            divider
            stat(label: "Volume", value: unit.weightLabel(session.totalVolumeKg))
        }
        .padding(.vertical, Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColor.glassBorder)
            .frame(width: 0.5)
            .frame(maxHeight: .infinity)
            .padding(.vertical, Spacing.xs)
    }

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppFont.statValueSmall)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.sm)
    }

    private var prsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(AppColor.achievement)
                    Text("\(detectedPRs.count) new \(detectedPRs.count == 1 ? "PR" : "PRs")")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                }
                ForEach(detectedPRs, id: \.self) { pr in
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
        case .estimatedOneRepMax: return "e1RM \(unit.weightLabel(pr.value))"
        case .absoluteWeight:     return "Top set \(unit.weightLabel(pr.value))"
        case .sessionVolume:      return "Volume \(unit.weightLabel(pr.value))"
        case .bodyweightReps:     return "\(Int(pr.value)) reps"
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
                        Text("\(workingSets) sets · \(unit.weightLabel(entry.workingVolumeKg))")
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

    /// `GlassButton`, not a hand-rolled one. This was a bare `Button` with its
    /// own rounded rectangle and `AppColor.background` used as the ink on an
    /// accent fill — every token legal on its own, which is why no lint rule
    /// caught it, but the wrong ink (`onAccent` is the token for that) and a
    /// second implementation of the primary button.
    private var doneButton: some View {
        GlassButton(title: "Done", style: .primary, isFullWidth: true) { onClose() }
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
