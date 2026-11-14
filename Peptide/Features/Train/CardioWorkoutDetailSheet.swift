import SwiftUI

/// What a workout from Apple Health recorded. Health owns the workout, so
/// the only change made here is the type Atlas shows it as.
struct CardioWorkoutDetailSheet: View {
    let workout: ImportedCardioWorkout
    let unit: MeasurementUnit
    /// The user picked the type; Health recorded something else.
    let isTypeOverridden: Bool
    /// Nil returns to Health's own type.
    let onPickType: (CardioActivity?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    /// The Atlas workout being filled in for this one, until it's saved.
    @State private var loggingSession: WorkoutSession?
    @State private var didLog = false

    private struct Stat {
        let label: String
        let value: String
    }

    private var stats: [Stat] {
        [
            Stat(label: String(localized: "Duration"), value: CardioWorkoutEngine.durationLabel(workout.duration)),
            CardioWorkoutEngine.distanceLabel(meters: workout.distanceMeters, unit: unit)
                .map { Stat(label: String(localized: "Distance"), value: $0) },
            CardioWorkoutEngine.energyLabel(workout.activeKilocalories)
                .map { Stat(label: String(localized: "Active energy"), value: $0) },
            CardioWorkoutEngine.heartRateLabel(workout.averageHeartRate)
                .map { Stat(label: String(localized: "Avg heart rate"), value: $0) },
        ]
        .compactMap { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    typeMenu
                    if CardioWorkoutEngine.canLogExercises(workout.activity) {
                        GlassButton(title: "Log exercises", icon: "plus", isFullWidth: true) {
                            loggingSession = CardioWorkoutEngine.session(loggingExercisesFor: workout)
                        }
                        .accessibilityIdentifier("log-health-workout-exercises")
                    }
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible())],
                        spacing: Spacing.md
                    ) {
                        ForEach(stats, id: \.label) { stat($0) }
                    }
                    Text("The type only changes in Atlas. Edit or delete the workout itself in the Health app.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(Spacing.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(workout.activity.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .sheet(item: $loggingSession, onDismiss: { if didLog { dismiss() } }) { session in
            WorkoutSavedEditor(session: session, unit: unit) { edited in
                try save(edited, startedAs: session)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: workout.activity.symbol)
                .font(AppFont.scaled(28, weight: .semibold, relativeTo: .title1))
                .foregroundStyle(AppColor.accentPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text((workout.start..<workout.end).formatted(.interval.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                if !workout.sourceName.isEmpty {
                    Text("Recorded by \(workout.sourceName)")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Saves the lifts as an Atlas workout. History then shows that
    /// workout in place of this one (`CardioWorkoutEngine.unlogged`).
    private func save(_ edited: WorkoutSession, startedAs original: WorkoutSession) throws {
        guard edited.completedSetCount > 0 else {
            throw WorkoutEditValidation.InvalidDraft(message: String(localized: "Add at least one exercise to log this workout."))
        }
        try WorkoutEditValidation.validate(edited, original: original)
        try SwiftDataRepository.shared.saveWorkoutDurably(edited)
        didLog = true
        dataStore.workoutWasEdited(exerciseIDs: Set(edited.exercises.map(\.exerciseID)))
    }

    /// The sheet's type control. An untyped workout asks for a type in
    /// the accent colour; a typed one shows its type and can be changed.
    private var typeMenu: some View {
        let isUntyped = workout.activity == .other
        return Menu {
            WorkoutTypeMenuItems(current: workout.activity, isOverridden: isTypeOverridden, onPick: onPickType)
        } label: {
            HStack(spacing: Spacing.sm) {
                Text("Workout type")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer(minLength: Spacing.sm)
                Text(isUntyped ? String(localized: "Choose type") : workout.activity.name)
                    .font(AppFont.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(isUntyped ? AppColor.accentLight : AppColor.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: Spacing.minimumHitTarget)
            .contentShape(Rectangle())
            .glassSurface(cornerRadius: Spacing.smallCornerRadius)
        }
        .accessibilityIdentifier("workout-type-menu")
        .accessibilityHint("Changes what this workout is shown as in Atlas")
    }

    private func stat(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(stat.value)
                .font(AppFont.scaled(20, weight: .medium))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
            Text(stat.label)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
        .accessibilityElement(children: .combine)
    }
}
