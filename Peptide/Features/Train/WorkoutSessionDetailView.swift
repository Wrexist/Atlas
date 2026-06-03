import SwiftUI

/// Per-session drill-down from the WorkoutHistoryView list. Shows
/// every logged set, the muscle map for the session, any PRs the
/// engine detected at the time, perceived effort, and the note —
/// the full "what happened in this workout" surface so the history
/// list isn't just a roll-up.
///
/// Pulls PRs from `PRDetectionEngine.recordedPRs(for:)` rather than
/// re-running ingest (which would mutate the records and return
/// empty on re-open — same bug we fixed in WorkoutFinishView).
struct WorkoutSessionDetailView: View {
    let session: WorkoutSession
    @State private var library = ExerciseLibrary.shared

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
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                MuscleMapView(highlights: muscleHighlights)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 320)
                statsRow
                if let effort = session.perceivedEffort {
                    perceivedEffortChip(effort)
                }
                if let note = session.note, !note.isEmpty {
                    noteCard(note)
                }
                exercisesList
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.lg)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle(session.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateLabel)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)
            Text(session.name ?? "Workout")
                .font(AppFont.statHeader)
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: Spacing.md) {
            stat(value: "\(session.exercises.count)", label: "Exercises")
            stat(value: "\(session.completedSetCount)", label: "Sets")
            if let durationLabel {
                stat(value: durationLabel, label: "Duration")
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func perceivedEffortChip(_ effort: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(AppColor.perceivedEffort)
            Text("Perceived effort")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text("\(effort) / 5")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note")
                .font(AppFont.eyebrow)
                .tracking(1.2)
                .foregroundStyle(AppColor.textTertiary)
            Text(note)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
    }

    private var exercisesList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Exercises")
                .font(AppFont.eyebrow)
                .tracking(1.2)
                .foregroundStyle(AppColor.textSecondary)
            ForEach(session.exercises) { entry in
                exerciseCard(entry: entry)
            }
        }
    }

    private func exerciseCard(entry: WorkoutExerciseEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            let exercise = library.lookup(id: entry.exerciseID)
            HStack {
                Text(exercise?.name ?? entry.exerciseID)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("\(entry.sets.filter(\.completed).count) sets")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Divider().background(AppColor.glassBorder)
            ForEach(entry.sets) { set in
                HStack(spacing: Spacing.sm) {
                    Text("\(set.index)")
                        .font(AppFont.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 20, alignment: .leading)
                        .foregroundStyle(AppColor.textTertiary)
                    if set.weightKg > 0 {
                        Text("\(set.weightKg, specifier: "%.1f") kg × \(set.reps)")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textPrimary)
                    } else {
                        Text("\(set.reps) reps")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    if let rpe = set.rpe {
                        Text("RPE \(rpe, specifier: "%.1f")")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    if set.isWarmup {
                        Text("W")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppColor.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColor.surfaceElevated))
                    } else if set.completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.accentPrimary)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    private var dateLabel: String {
        // Use the locale-aware format API instead of a hard-coded
        // `EEEE · MMMM d, yyyy`. Non-Latin locales (ja, zh, ar)
        // render their own canonical week/month strings rather than
        // forcing an English shape onto them (audit Biology L18).
        let date = session.finishedAt ?? session.startedAt
        return date.formatted(
            .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
                .year()
        )
    }

    private var durationLabel: String? {
        guard let finished = session.finishedAt else { return nil }
        let interval = finished.timeIntervalSince(session.startedAt)
        guard interval > 0 else { return nil }
        let totalMinutes = Int(interval / 60)
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
