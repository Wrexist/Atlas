import SwiftUI

/// First page while a workout runs on the phone: the set to do next with
/// its load and reps on the Digital Crown and one button to log it, the
/// rest countdown in its place between sets, and every exercise one tap
/// away. Each tap goes to the phone, which owns the workout.
struct WorkoutPage: View {
    @EnvironmentObject private var store: WatchStore
    let workout: WatchWorkoutSnapshot

    private var unit: WatchWeightUnit { WatchWeightUnit(store.watchData.measurementUnit) }

    /// Re-renders when the rest runs out, so the logger replaces the
    /// countdown without waiting for the phone.
    private var schedule: ExplicitTimelineSchedule<[Date]> {
        .explicit(workout.rest.map { [$0.endsAt] } ?? [])
    }

    var body: some View {
        TimelineView(schedule) { context in
            ScrollView {
                VStack(spacing: 10) {
                    WorkoutClockRow(workout: workout)
                    stage(at: context.date)
                    NavigationLink {
                        WorkoutExerciseList()
                    } label: {
                        Label("Exercises", systemImage: "list.bullet")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .entrance(1)
                }
            }
        }
        .navigationTitle(workout.name.isEmpty ? String(localized: "Workout") : workout.name)
        .pageBackground(WatchPalette.training)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.sendWorkout(.setPaused(!workout.isPaused))
                } label: {
                    Image(systemName: workout.isPaused ? "play.fill" : "pause.fill")
                }
                .accessibilityLabel(workout.isPaused ? "Resume workout" : "Pause workout")
            }
        }
    }

    @ViewBuilder
    private func stage(at now: Date) -> some View {
        if workout.isPaused {
            PausedCard()
        } else if workout.isResting(at: now), let rest = workout.rest {
            RestCard(rest: rest, upNext: workout.upNext, unit: unit)
        } else if let next = workout.upNext {
            SetLogger(exercise: next.exercise, set: next.set, unit: unit)
                .id(next.set.id)
        } else {
            AllSetsDoneCard(exercise: workout.selectedExercise)
        }
    }
}

/// Active time and set count, the two numbers worth a glance mid-set.
private struct WorkoutClockRow: View {
    let workout: WatchWorkoutSnapshot

    var body: some View {
        HStack {
            Group {
                if let paused = workout.pausedElapsedSeconds {
                    Text(Duration.seconds(paused).formatted(.time(pattern: WatchFormat.elapsedPattern(seconds: paused))))
                } else {
                    Text(workout.timerStartedAt, style: .timer)
                }
            }
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(workout.isPaused ? Color.secondary : Color.primary)
            Spacer(minLength: 4)
            Text("\(workout.completedSets)/\(workout.totalSets) sets")
                .accessibilityLabel("\(workout.completedSets) of \(workout.totalSets) sets")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WatchPalette.training)
                .contentTransition(.numericText())
                .animation(WatchMotion.update, value: workout.completedSets)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The set to do next. Tap the load or reps to put it on the Crown, then
/// log it with the button; the values sent are the ones on screen.
private struct SetLogger: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.watchPageIsActive) private var isActive
    let exercise: WatchWorkoutSnapshot.Exercise
    let set: WatchWorkoutSnapshot.SetRow
    let unit: WatchWeightUnit

    private enum Field { case weight, reps }

    @State private var weightKg: Double
    @State private var reps: Double
    @FocusState private var focus: Field?

    init(exercise: WatchWorkoutSnapshot.Exercise, set: WatchWorkoutSnapshot.SetRow, unit: WatchWeightUnit) {
        self.exercise = exercise
        self.set = set
        self.unit = unit
        _weightKg = State(initialValue: set.weightKg)
        _reps = State(initialValue: Double(set.reps))
    }

    /// Same ceilings `SetEntryLimits` enforces on the phone.
    private static let maxWeightKg = 1000.0
    private static let maxReps = 500.0

    private var setLabel: String {
        if set.isWarmup { return String(localized: "Warm-up") }
        let working = exercise.workingSets
        let position = (working.firstIndex { $0.id == set.id } ?? 0) + 1
        return String(localized: "Set \(position) of \(working.count)")
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(exercise.name)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(setLabel.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(set.isWarmup ? Color.secondary : WatchPalette.training)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if set.logsReps {
                HStack(spacing: 6) {
                    weightTile
                    repsTile
                }
            }

            Button(action: complete) {
                Label("Complete set", systemImage: "checkmark")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .tint(WatchPalette.training)
            .buttonStyle(.borderedProminent)
            .disabled(store.isSending)
        }
        .entrance(0)
        .onChange(of: set.weightKg) { weightKg = set.weightKg }
        .onChange(of: set.reps) { reps = Double(set.reps) }
        // Leaving the page hands the Crown back to the pager.
        .onChange(of: isActive) { if !isActive { focus = nil } }
    }

    /// A tap puts a tile on the Crown; a second tap on the same tile hands
    /// the Crown back to scrolling and paging.
    private func toggleFocus(_ field: Field) {
        focus = focus == field ? nil : field
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { unit.display(weightKg) },
            set: { weightKg = min(max(unit.kilograms($0), 0), Self.maxWeightKg) }
        )
    }

    private var weightTile: some View {
        ValueTile(value: unit.format(weightKg), label: unit.symbol, isFocused: focus == .weight)
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .weight)
            .digitalCrownRotation(
                weightBinding,
                from: 0,
                through: unit.display(Self.maxWeightKg),
                by: unit.step,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onTapGesture { toggleFocus(.weight) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weight")
            .accessibilityValue("\(unit.format(weightKg)) \(unit.symbol)")
            // Snapped to the Crown's grid, so a swipe logs the same load
            // a Crown detent would rather than an off-plate weight.
            .accessibilityAdjustableAction { direction in
                let steps = (unit.display(weightKg) / unit.step).rounded() + (direction == .increment ? 1 : -1)
                weightBinding.wrappedValue = steps * unit.step
            }
    }

    private var repsTile: some View {
        ValueTile(value: "\(Int(reps.rounded()))", label: String(localized: "reps"), isFocused: focus == .reps)
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .reps)
            .digitalCrownRotation(
                $reps,
                from: 0,
                through: Self.maxReps,
                by: 1,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onTapGesture { toggleFocus(.reps) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Reps")
            .accessibilityValue("\(Int(reps.rounded()))")
            .accessibilityAdjustableAction { direction in
                reps = min(max(reps + (direction == .increment ? 1 : -1), 0), Self.maxReps)
            }
    }

    private func complete() {
        focus = nil
        store.sendWorkout(.completeSet(
            exerciseID: exercise.id,
            setID: set.id,
            weightKg: weightKg,
            reps: Int(reps.rounded())
        ))
    }
}

/// A number over its unit. The focused tile, the one the Crown turns,
/// takes the training colour.
private struct ValueTile: View {
    let value: String
    let label: String
    let isFocused: Bool

    var body: some View {
        VStack(spacing: -1) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isFocused ? WatchPalette.training.opacity(0.28) : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isFocused ? WatchPalette.training : Color.white.opacity(0.1), lineWidth: isFocused ? 1.5 : 0.5)
        )
        .animation(WatchMotion.press, value: isFocused)
    }
}

/// The countdown between sets, with the next set beneath so the user
/// knows what to load before it ends.
private struct RestCard: View {
    @EnvironmentObject private var store: WatchStore
    let rest: WatchWorkoutSnapshot.Rest
    let upNext: (exercise: WatchWorkoutSnapshot.Exercise, set: WatchWorkoutSnapshot.SetRow)?
    let unit: WatchWeightUnit

    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 40

    private var interval: ClosedRange<Date> {
        rest.endsAt.addingTimeInterval(-max(rest.totalSeconds, 1))...rest.endsAt
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text("REST")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(WatchPalette.training)
                Text(timerInterval: interval, countsDown: true)
                    .font(.system(size: countdownSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                ProgressView(timerInterval: interval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(WatchPalette.training)
                .accessibilityHidden(true)
            }
            .entrance(0)

            HStack(spacing: 6) {
                Button("+30s") { store.sendWorkout(.extendRest(seconds: 30)) }
                    .accessibilityLabel("Add 30 seconds")
                Button("Skip") { store.sendWorkout(.skipRest) }
                    .tint(WatchPalette.training)
                    .accessibilityLabel("Skip rest")
            }
            .font(.system(.footnote, design: .rounded, weight: .bold))

            if let upNext {
                VStack(spacing: 0) {
                    Text("Up next · \(upNext.exercise.name)")
                        .lineLimit(1)
                    if upNext.set.logsReps {
                        Text("\(unit.format(upNext.set.weightKg)) \(unit.symbol) × \(upNext.set.reps)")
                            .monospacedDigit()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct PausedCard: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(WatchPalette.training)
            Text("Workout paused")
                .font(.system(.headline, design: .rounded))
            Button {
                store.sendWorkout(.setPaused(false))
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(WatchPalette.training)
            .buttonStyle(.borderedProminent)
        }
        .entrance(0)
    }
}

/// Every planned set is logged. Another set can go on from here; finishing
/// stays on the phone, where effort and notes are asked for.
private struct AllSetsDoneCard: View {
    @EnvironmentObject private var store: WatchStore
    let exercise: WatchWorkoutSnapshot.Exercise?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(WatchPalette.training)
                .symbolEffect(.bounce, value: exercise?.id)
            Text("All sets logged")
                .font(.system(.headline, design: .rounded))
            if let exercise {
                Button {
                    store.sendWorkout(.addSet(exerciseID: exercise.id, setID: UUID()))
                } label: {
                    Label("Add set", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.isSending)
            }
            Text("Finish the workout on your iPhone.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .entrance(0)
    }
}

/// Every exercise in the workout with its progress. Tapping one makes it
/// the exercise the Workout page logs next.
struct WorkoutExerciseList: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let workout = store.watchData.workout
        List {
            ForEach(workout?.exercises ?? []) { exercise in
                Button {
                    store.sendWorkout(.selectExercise(exerciseID: exercise.id))
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(exercise.name)
                                .font(.system(.body, design: .rounded))
                                .lineLimit(2)
                            Text("\(exercise.completedWorkingSets)/\(exercise.workingSets.count) sets")
                                .accessibilityLabel("\(exercise.completedWorkingSets) of \(exercise.workingSets.count) sets")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if exercise.id == workout?.selectedExercise?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(WatchPalette.training)
                        }
                    }
                }
                .accessibilityAddTraits(exercise.id == workout?.selectedExercise?.id ? .isSelected : [])
            }
        }
        .navigationTitle("Exercises")
        .onChange(of: workout == nil) { _, ended in
            if ended { dismiss() }
        }
    }
}
