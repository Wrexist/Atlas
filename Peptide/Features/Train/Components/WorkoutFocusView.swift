import SwiftUI

/// The reference's logging and rest screens are two states of this one view.
/// All mutations go through the existing session service.
struct WorkoutFocusView: View {
    let session: WorkoutSession
    let unit: MeasurementUnit
    let onAddExercise: () -> Void
    let onFinish: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(DataStore.self) private var dataStore
    @State private var service = WorkoutSessionService.shared
    @State private var library = ExerciseLibrary.shared
    @State private var detailExercise: Exercise?

    private var entry: WorkoutExerciseEntry? { session.selectedExercise }
    private var defaultRestSeconds: Int { dataStore.profile.trainingPreferences?.restTimerDefault ?? 90 }
    private var exercise: Exercise? { entry.flatMap { library.lookup(id: $0.exerciseID) } }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Spacing.md) {
                    if let entry {
                        ExerciseHeroView(exercise: exercise)
                            .id(exercise?.id)
                            .transition(.opacity)
                            .frame(height: heroHeight(available: geometry.size.height))
                            .appAnimation(AppAnimation.quick, value: exercise?.id)
                            .padding(.top, Spacing.sm)
                        exerciseStrip
                        setPanel(entry)
                    } else {
                        EmptyStateView(
                            icon: "dumbbell", title: "Your workout starts here",
                            message: "Choose your first exercise to start logging sets.",
                            action: .init(title: "Add exercise", icon: "plus", perform: onAddExercise)
                        )
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColor.trainingBackground.ignoresSafeArea())
        .task { await library.load() }
        .sheet(item: $detailExercise) { exercise in
                NavigationStack {
                    ExerciseDetailView(exerciseID: exercise.id)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { detailExercise = nil }
                            }
                        }
                }
        }
    }

    private func heroHeight(available: CGFloat) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 120 }
        // Completing a set must not resize the artwork and move the next tap.
        return max(120, min(210, available * 0.26))
    }

    private var exerciseStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(session.exercises) { item in
                        exerciseButton(item)
                            .id(item.id)
                    }
                    GlassIconButton(icon: "plus", accessibilityLabel: "Add exercise", action: onAddExercise)
                }
                .padding(Spacing.xs)
            }
            .onChange(of: entry?.id, initial: true) { _, id in
                guard let id else { return }
                AppAnimation.with(AppAnimation.springSnappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func exerciseButton(_ item: WorkoutExerciseEntry) -> some View {
        let exercise = library.lookup(id: item.exerciseID)
        let selected = entry?.id == item.id
        let complete = !item.sets.isEmpty && item.sets.allSatisfy(\.completed)
        return Button {
            service.selectExercise(item.id)
            Haptics.selection()
        } label: {
            ExerciseImageView(
                exercise: exercise
            )
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .padding(Spacing.xs)
            .background(Circle().fill(AppColor.trainingPanel))
            .overlay(Circle().stroke(selected ? AppColor.trainingSelection : AppColor.glassBorder, lineWidth: selected ? 3 : 1))
            .overlay(alignment: .bottomTrailing) {
                if complete {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(AppColor.onAccent, AppColor.trainingComplete)
                        .background(Circle().fill(AppColor.trainingPanel))
                        .symbolEffect(.bounce, value: complete)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .appAnimation(AppAnimation.springBouncy, value: complete)
            .appAnimation(AppAnimation.springSnappy, value: selected)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(Text(library.displayName(for: item.exerciseID)))
        .accessibilityValue(complete ? "Complete" : "In progress")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setPanel(_ entry: WorkoutExerciseEntry) -> some View {
        let hints = PreviousSetEngine.hints(
            for: entry.sets, previous: service.previousSessionSets(forExerciseID: entry.exerciseID)
        )
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                Text(exercise?.name ?? "Unknown exercise")
                    .font(AppFont.title3)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: Spacing.xs)
                Button { detailExercise = exercise } label: {
                    Image(systemName: "info.circle").minimumHitArea()
                }
                .accessibilityLabel("Exercise instructions")
                .disabled(exercise == nil)
            }
            if let letter = session.supersetLetter(for: entry.id) {
                Label(supersetCaption(letter: letter, entryID: entry.id), systemImage: "link")
                    .font(AppFont.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            statusHeader(entry)
            Divider()
            if let progression = service.progression(for: entry) {
                ProgressionHint(
                    suggestion: progression, unit: unit,
                    canApply: ProgressionEngine.isPending(progression, in: entry.sets)
                ) {
                    service.applyProgression(toExerciseEntryID: entry.id)
                }
            }
            if exercise?.equipmentKind == .dumbbell {
                Text("Weight per dumbbell · Reps")
                    .font(AppFont.caption2).foregroundStyle(AppColor.textSecondary)
            } else {
                Text("Weight · Reps").font(AppFont.caption2).foregroundStyle(AppColor.textSecondary)
            }
            if let bar = exercise?.equipmentKind.bar, let set = entry.setToLoad, set.isWholeBarLoad {
                PlateLoadStrip(weightKg: set.weightKg, unit: unit, bar: bar)
            }
            VStack(spacing: 0) {
                ForEach(entry.sets) { set in
                    SetEditorRow(
                        set: Binding(
                            get: { service.currentSet(id: set.id, inExerciseEntryID: entry.id) ?? set },
                            set: { service.updateSet($0, inExerciseEntryID: entry.id) }
                        ),
                        previousSet: hints[set.id], unit: unit,
                        onDelete: { service.removeSet(setID: set.id, fromExerciseEntryID: entry.id) },
                        focusStyle: true, isCurrent: entry.sets.first(where: { !$0.completed })?.id == set.id,
                        isPaused: session.isPaused
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .appAnimation(AppAnimation.springSnappy, value: entry.sets.count)
            HStack {
                Button {
                    Haptics.impact(.light)
                    service.addSet(toExerciseID: entry.id)
                } label: {
                    Label("Add set", systemImage: "plus").minimumHitArea()
                }
                Spacer()
                RestTimeMenu(overrideSeconds: entry.restSeconds, defaultSeconds: defaultRestSeconds) { seconds in
                    service.setRestSeconds(seconds, forExerciseEntryID: entry.id)
                }
                .minimumHitArea()
            }
            .font(AppFont.callout)
            Group {
                if exerciseDone(entry) && session.focus?.rest == nil {
                    if let next = session.nextPendingSet(after: entry.id) {
                        GlassButton(title: "Next exercise", icon: "arrow.right", isFullWidth: true) {
                            service.selectExercise(next.entry)
                        }
                    } else if session.completedSetCount > 0 {
                        GlassButton(title: "Finish workout", icon: "checkmark", isFullWidth: true, action: onFinish)
                    } else {
                        Text("Log a working set to finish")
                            .font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .appAnimation(AppAnimation.springSnappy, value: exerciseDone(entry))
            .onChange(of: DoneState(entryID: entry.id, done: exerciseDone(entry))) { old, new in
                // Selecting an already-finished exercise isn't a completion.
                if old.entryID == new.entryID, !old.done, new.done { Haptics.success() }
            }
            Divider()
            WorkoutFocusMetrics(session: session, unit: unit)
        }
        .padding(Spacing.xl)
        .foregroundStyle(AppColor.textPrimary)
        .background(AppColor.trainingPanel, in: RoundedRectangle(cornerRadius: Spacing.sheetCornerRadius))
    }

    /// "Superset A · with Incline Dumbbell Press".
    private func supersetCaption(letter: String, entryID: UUID) -> String {
        let partners = session.supersetPartners(of: entryID)
            .map { library.displayName(for: $0.exerciseID) }
            .formatted(.list(type: .and))
        return String(localized: "Superset \(letter) · with \(partners)")
    }

    private func statusHeader(_ entry: WorkoutExerciseEntry) -> some View {
        // Reserve the same height at ordinary sizes; allow natural reflow at
        // accessibility sizes. Only status content transitions, never the rows.
        ZStack(alignment: .topLeading) {
          Group {
            if session.isPaused {
              VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Workout paused").font(AppFont.title2)
                Text("Resume when you are ready. Your sets are saved.")
                    .font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                GlassButton(title: "Resume workout", icon: "play.fill", isFullWidth: true) {
                    service.togglePause()
                }
              }
            } else if let rest = session.focus?.rest {
                WorkoutFocusRestHeader(
                    rest: rest, target: restTitle(rest),
                    onSkip: { Haptics.selection(); service.skipRest() },
                    onAdjust: { Haptics.selection(); service.adjustRest(by: $0) },
                    onUndo: { Haptics.selection(); service.undoRestSourceSet() }
                )
            } else {
              VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(progressTitle(entry)).font(AppFont.statValueSmall)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Check a set when you finish. Tap its check again to undo.")
                    .font(AppFont.subheadline).foregroundStyle(AppColor.textSecondary)
              }
            }
          }
          .transition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 148, alignment: .topLeading)
        .appAnimation(AppAnimation.quick, value: session.focus?.rest == nil)
        .appAnimation(AppAnimation.quick, value: session.isPaused)
    }

    private func exerciseDone(_ entry: WorkoutExerciseEntry) -> Bool {
        !entry.sets.isEmpty && entry.sets.allSatisfy(\.completed)
    }

    /// Numbers working sets only, matching the Live Activity's totals.
    private func progressTitle(_ entry: WorkoutExerciseEntry) -> String {
        guard let next = entry.sets.first(where: { !$0.completed }) else {
            return entry.sets.isEmpty ? String(localized: "Add your first set") : String(localized: "Exercise complete")
        }
        if next.isWarmup { return String(localized: "Warm-up") }
        let working = entry.sets.filter { !$0.isWarmup }
        let position = (working.firstIndex { $0.id == next.id } ?? 0) + 1
        return String(localized: "Set \(position) of \(working.count)")
    }

    private func restTitle(_ rest: WorkoutRestContext) -> String {
        guard let target = session.exercises.first(where: { $0.id == rest.targetEntryID }),
              let set = target.sets.first(where: { $0.id == rest.targetSetID }) else { return String(localized: "Rest") }
        if target.id == entry?.id { return String(localized: "Rest before set \(set.index)") }
        let name = library.displayName(for: target.exerciseID)
        return String(localized: "Up next: \(name) · Set \(set.index)")
    }
}

private struct DoneState: Equatable {
    let entryID: UUID
    let done: Bool
}

private struct WorkoutFocusRestHeader: View {
    let rest: WorkoutRestContext
    let target: String
    let onSkip: () -> Void
    let onAdjust: (TimeInterval) -> Void
    let onUndo: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: rest.frozenSeconds != nil)) { context in
            let seconds = Int(ceil(rest.remaining(at: context.date)))
            let remaining = WorkoutClock.label(seconds)
            let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
            let headerLayout = isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Spacing.lg))
            VStack(alignment: .leading, spacing: Spacing.sm) {
                headerLayout {
                    RestCountdownRing(rest: rest)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(target)
                            .font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                            .lineLimit(isAccessibilitySize ? nil : 2)
                        Text(remaining)
                            .font(AppFont.statValueSmall).monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .appAnimation(AppAnimation.quick, value: remaining)
                            .accessibilityLabel("Rest remaining")
                            .accessibilityValue(WorkoutClock.spoken(seconds))
                    }
                    Spacer(minLength: Spacing.xs)
                    GlassButton(title: "Skip", icon: "forward.end.fill", style: .secondary, action: onSkip)
                        .fixedSize()
                }
                HStack(spacing: Spacing.sm) {
                    Button(action: onUndo) {
                        Label("Undo set", systemImage: "arrow.uturn.backward")
                            .minimumHitArea()
                    }
                    .accessibilityLabel("Undo last completed set")
                    .accessibilityIdentifier("workout-undo-rest-set")
                    Spacer()
                    adjustButton("−15s", seconds: -15, label: "Remove 15 seconds")
                    adjustButton("+15s", seconds: 15, label: "Add 15 seconds")
                }
                .font(AppFont.subheadline)
            }
        }
    }

    private func adjustButton(_ title: String, seconds: TimeInterval, label: LocalizedStringKey) -> some View {
        Button { onAdjust(seconds) } label: {
            Text(title)
                .monospacedDigit()
                .padding(.horizontal, Spacing.md)
                .minimumHitArea()
                .background(AppColor.trainingInput, in: Capsule())
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(label)
    }
}

/// Drains continuously rather than stepping once a second, so the rest
/// reads as time running out instead of a number changing.
private struct RestCountdownRing: View {
    let rest: WorkoutRestContext

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: rest.frozenSeconds != nil)) { context in
            ZStack {
                Circle()
                    .stroke(AppColor.trainingInput, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: rest.remainingFraction(at: context.date))
                    .stroke(AppColor.trainingSelection, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct WorkoutFocusMetrics: View {
    let session: WorkoutSession
    let unit: MeasurementUnit

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.lg) { metrics }
            VStack(alignment: .leading, spacing: Spacing.sm) { metrics }
        }
        .font(AppFont.callout.weight(.semibold))
        .frame(maxWidth: .infinity)
    }

    private var volume: String { Int(unit.weightForDisplay(session.totalVolumeKg).rounded()).formatted() }

    @ViewBuilder private var metrics: some View {
        Label(session.completedSetCount == 1 ? "1 set" : "\(session.completedSetCount) sets", systemImage: "checkmark.circle")
        Label("\(volume) \(unit.weightSuffix)", systemImage: "scalemass")
            .accessibilityLabel(Text("Volume: \(volume) \(unit.weightSuffix)"))
        TimelineView(.animation(minimumInterval: 1, paused: session.isPaused)) { context in
            Label(WorkoutClock.label(session.elapsedSeconds(now: context.date)), systemImage: "clock")
                .monospacedDigit()
                .accessibilityLabel("Active duration")
                .accessibilityValue(WorkoutClock.spoken(session.elapsedSeconds(now: context.date)))
        }
    }
}

enum WorkoutClock {
    static func label(_ seconds: Int) -> String {
        let value = max(0, seconds)
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    /// "12 minutes, 34 seconds" — VoiceOver reads the `label` form as a
    /// time of day.
    static func spoken(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
