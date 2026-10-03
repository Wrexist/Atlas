import SwiftUI

/// The reference's logging and rest screens are two states of this one view.
/// All mutations go through the existing session service.
struct WorkoutFocusView: View {
    let session: WorkoutSession
    let unit: MeasurementUnit
    let onAddExercise: () -> Void
    let onFinish: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var service = WorkoutSessionService.shared
    @State private var library = ExerciseLibrary.shared
    @State private var showDetails = false

    private var entry: WorkoutExerciseEntry? { session.selectedExercise }
    private var exercise: Exercise? { entry.flatMap { library.lookup(id: $0.exerciseID) } }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Spacing.md) {
                    if let entry {
                        ExerciseHeroView(exercise: exercise)
                            .frame(height: heroHeight(available: geometry.size.height))
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
        .sheet(isPresented: $showDetails) {
            if let exercise {
                NavigationStack {
                    ExerciseDetailView(exerciseID: exercise.id)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showDetails = false }
                            }
                        }
                }
            }
        }
    }

    private func heroHeight(available: CGFloat) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 120 }
        let expandedHeader = session.isPaused || session.focus?.rest != nil
        return max(120, min(expandedHeader ? 190 : 250, available * (expandedHeader ? 0.23 : 0.30)))
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
                if let id { proxy.scrollTo(id, anchor: .center) }
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
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(exercise?.name ?? item.exerciseID))
        .accessibilityValue(complete ? "Complete" : "In progress")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setPanel(_ entry: WorkoutExerciseEntry) -> some View {
        let hints = PreviousSetEngine.hints(
            for: entry.sets, previous: service.previousSessionSets(forExerciseID: entry.exerciseID)
        )
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                Text(exercise?.name ?? entry.exerciseID)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer(minLength: Spacing.xs)
                Button { showDetails = true } label: {
                    Image(systemName: "info.circle").minimumHitArea()
                }
                .accessibilityLabel("Exercise instructions")
                .disabled(exercise == nil)
            }
            if session.isPaused {
                Text("Workout paused").font(AppFont.title2)
                Text("Resume when you are ready. Your sets are saved.")
                    .font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                GlassButton(title: "Resume workout", icon: "play.fill", isFullWidth: true) {
                    service.togglePause()
                }
            } else if let rest = session.focus?.rest {
                WorkoutFocusRestHeader(
                    rest: rest, target: restTitle(rest),
                    onSkip: { service.skipRest() }, onAdjust: { service.adjustRest(by: $0) }
                )
            } else {
                Text(progressTitle(entry)).font(AppFont.statValueSmall)
                    .foregroundStyle(AppColor.textPrimary)
            }
            Divider()
            if exercise?.equipmentKind == .dumbbell {
                Text("Weight per dumbbell · Reps")
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            } else {
                Text("Weight · Reps").font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(entry.sets) { set in
                    SetEditorRow(
                        set: Binding(get: { set }, set: { service.updateSet($0, inExerciseEntryID: entry.id) }),
                        previousSet: hints[set.id], unit: unit,
                        onDelete: { service.removeSet(setID: set.id, fromExerciseEntryID: entry.id) },
                        focusStyle: true, isCurrent: entry.sets.first(where: { !$0.completed })?.id == set.id,
                        isPaused: session.isPaused
                    )
                }
            }
            HStack {
                Button {
                    service.addSet(toExerciseID: entry.id)
                } label: {
                    Label("Add set", systemImage: "plus").minimumHitArea()
                }
                Spacer()
                Menu {
                    ForEach(RestTimeOptions.choices(including: entry.restSeconds), id: \.self) { seconds in
                        Button(RestTimeOptions.label(for: seconds)) {
                            service.setRestSeconds(seconds, forExerciseEntryID: entry.id)
                        }
                    }
                } label: {
                    Label("Rest time", systemImage: "timer").minimumHitArea()
                }
            }
            .font(AppFont.callout)
            if !entry.sets.isEmpty && entry.sets.allSatisfy(\.completed) && session.focus?.rest == nil {
                if let next = session.nextPendingSet(after: entry.id) {
                    GlassButton(title: "Next exercise", icon: "arrow.right", isFullWidth: true) {
                        service.selectExercise(next.entry)
                    }
                } else {
                    GlassButton(title: "Finish workout", icon: "checkmark", isFullWidth: true, action: onFinish)
                }
            }
            Divider()
            WorkoutFocusMetrics(session: session, unit: unit)
        }
        .padding(Spacing.xl)
        .foregroundStyle(AppColor.textPrimary)
        .background(AppColor.trainingPanel, in: RoundedRectangle(cornerRadius: Spacing.sheetCornerRadius))
    }

    private func progressTitle(_ entry: WorkoutExerciseEntry) -> String {
        if let next = entry.sets.first(where: { !$0.completed }) { return "Set \(next.index) of \(entry.sets.count)" }
        return entry.sets.isEmpty ? "Add your first set" : "Exercise complete"
    }

    private func restTitle(_ rest: WorkoutRestContext) -> String {
        guard let target = session.exercises.first(where: { $0.id == rest.targetEntryID }),
              let set = target.sets.first(where: { $0.id == rest.targetSetID }) else { return "Rest" }
        if target.id == entry?.id { return "Rest before set \(set.index)" }
        let name = library.lookup(id: target.exerciseID)?.name ?? target.exerciseID
        return "Up next: \(name) · Set \(set.index)"
    }
}

private struct WorkoutFocusRestHeader: View {
    let rest: WorkoutRestContext
    let target: String
    let onSkip: () -> Void
    let onAdjust: (TimeInterval) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(target).font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                HStack {
                    Text(WorkoutClock.label(Int(ceil(rest.remaining(at: context.date)))))
                        .font(AppFont.statValueSmall).monospacedDigit()
                        .accessibilityLabel("Rest remaining")
                    Spacer()
                    Button(action: onSkip) {
                        Label("Skip", systemImage: "forward.end.fill")
                            .font(AppFont.callout).padding(.horizontal, Spacing.md).minimumHitArea()
                            .background(AppColor.trainingInput, in: Capsule())
                    }
                }
                ProgressView(value: rest.remainingFraction(at: context.date))
                    .tint(AppColor.trainingSelection).accessibilityHidden(true)
                HStack {
                    Button("−15 sec") { onAdjust(-15) }.minimumHitArea()
                    Spacer()
                    Button("+15 sec") { onAdjust(15) }.minimumHitArea()
                }
                .font(AppFont.caption)
            }
        }
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

    @ViewBuilder private var metrics: some View {
        Label(session.completedSetCount == 1 ? "1 set" : "\(session.completedSetCount) sets", systemImage: "checkmark.circle")
        Label("\(Int(unit.weightForDisplay(session.totalVolumeKg).rounded())) \(unit.weightSuffix)", systemImage: "scalemass")
            .accessibilityLabel(Text("Volume: \(Int(unit.weightForDisplay(session.totalVolumeKg).rounded())) \(unit.weightSuffix)"))
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label(WorkoutClock.label(session.elapsedSeconds(now: context.date)), systemImage: "clock")
                .monospacedDigit()
                .accessibilityLabel(Text("Active duration \(WorkoutClock.label(session.elapsedSeconds(now: context.date)))"))
        }
    }
}

enum WorkoutClock {
    static func label(_ seconds: Int) -> String {
        let value = max(0, seconds)
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
