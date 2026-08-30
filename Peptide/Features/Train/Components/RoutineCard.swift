import SwiftUI

/// Everything a routine card draws that isn't stored on `Routine` —
/// exercise display names, the derived counts, the glyph. Resolved once
/// by the list against `ExerciseLibrary` and held in state, because
/// `body` runs on every scroll frame and an 873-entry lookup per slot
/// per frame is not free.
struct RoutineSummary: Identifiable, Hashable {
    let routine: Routine
    let exerciseNames: [String]
    let totalSets: Int
    let estimatedMinutes: Int
    /// Drives the card's glyph — the group most of the routine's work
    /// lands on.
    let muscleGroup: MuscleGroup

    var id: UUID { routine.id }

    static func make(routine: Routine, lookup: (String) -> Exercise?) -> RoutineSummary {
        let resolved = routine.exercises
            .sorted { $0.index < $1.index }
            .compactMap { lookup($0.exerciseID) }
        return RoutineSummary(
            routine: routine,
            exerciseNames: resolved.map(\.name),
            totalSets: RoutineSeedEngine.totalSets(in: routine),
            estimatedMinutes: RoutineSeedEngine.estimatedMinutes(for: routine),
            muscleGroup: dominantGroup(of: resolved)
        )
    }

    /// The most-represented muscle group, ties broken by routine order so
    /// the glyph is stable across launches.
    private static func dominantGroup(of exercises: [Exercise]) -> MuscleGroup {
        var counts: [MuscleGroup: Int] = [:]
        for exercise in exercises {
            counts[exercise.muscleGroup, default: 0] += 1
        }
        let best = counts.values.max() ?? 0
        return exercises.map(\.muscleGroup).first { counts[$0] == best } ?? .fullBody
    }
}

/// One routine in the library.
///
/// Transplanted from the Music playlist row: artwork, title, a metadata
/// line, the first few track names, and a play button that starts the
/// thing without opening it. The mapping —
///
///     artwork  -> muscle-group glyph
///     title    -> routine.name
///     subtitle -> "5 exercises · 18 sets · ~45 min"
///     tracks   -> first three exercise names
///     play     -> start a workout seeded from this routine
///
/// The row and the play button are siblings rather than nested buttons,
/// so each owns its own hit region.
struct RoutineCard: View {
    let summary: RoutineSummary
    let onOpen: () -> Void
    let onStart: () -> Void

    private var routine: Routine { summary.routine }

    var body: some View {
        GlassCard {
            HStack(spacing: Spacing.md) {
                Button(action: onOpen) {
                    HStack(spacing: Spacing.md) {
                        glyph
                        details
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Opens the routine to edit it")

                startButton
            }
        }
    }

    private var glyph: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColor.accentPrimary.opacity(0.45),
                            AppColor.accentLight.opacity(0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
            Image(systemName: summary.muscleGroup.symbolName)
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(AppColor.onAccent)
        }
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(routine.name)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)

            Text(metaLine)
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)

            if !exerciseLine.isEmpty {
                Text(exerciseLine)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Start is the point of the card, so it gets the accent fill and a
    /// full 44pt target rather than living behind a context menu.
    private var startButton: some View {
        Button {
            Haptics.impact(.medium)
            onStart()
        } label: {
            Image(systemName: "play.fill")
                .font(AppFont.scaled(16, weight: .bold))
                .foregroundStyle(AppColor.onAccent)
                .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                .background(Circle().fill(AppColor.accentFill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start \(routine.name)")
        .disabled(routine.exercises.isEmpty)
        .opacity(routine.exercises.isEmpty ? 0.4 : 1)
    }

    private var metaLine: String {
        guard !routine.exercises.isEmpty else { return "No exercises yet" }
        let count = routine.exercises.count
        let exercises = count == 1 ? "1 exercise" : "\(count) exercises"
        return "\(exercises) · \(summary.totalSets) sets · ~\(summary.estimatedMinutes) min"
    }

    private var exerciseLine: String {
        summary.exerciseNames.prefix(3).joined(separator: ", ")
    }

    private var accessibilityLabel: String {
        [routine.name, metaLine].joined(separator: ", ")
    }
}

#Preview("Routine card") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.md) {
            RoutineCard(
                summary: RoutineSummary(
                    routine: Routine(name: "Push day", exercises: [
                        RoutineExercise(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", index: 0),
                        RoutineExercise(exerciseID: "Standing_Military_Press", index: 1),
                    ]),
                    exerciseNames: ["Barbell Bench Press", "Standing Military Press"],
                    totalSets: 6,
                    estimatedMinutes: 35,
                    muscleGroup: .chest
                ),
                onOpen: {},
                onStart: {}
            )
            RoutineCard(
                summary: RoutineSummary(
                    routine: Routine(name: "Empty draft"),
                    exerciseNames: [],
                    totalSets: 0,
                    estimatedMinutes: 0,
                    muscleGroup: .fullBody
                ),
                onOpen: {},
                onStart: {}
            )
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
