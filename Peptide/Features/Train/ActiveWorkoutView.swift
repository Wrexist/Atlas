import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Focused workout presentation with an overview for managing every exercise.
/// Session data, selection, rest and pause state belong to WorkoutSessionService.
struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DataStore.self) private var dataStore
    @Environment(\.requestReview) private var requestReview
    @State private var sessionService = WorkoutSessionService.shared
    @State private var library = ExerciseLibrary.shared
    @State private var showExercisePicker = false
    @State private var showFinishSheet = false
    @State private var showDiscardConfirm = false
    @State private var finishedSession: WorkoutSession?
    @State private var finishedPRs: [PRDetectionEngine.DetectedPR] = []
    /// Set at finish when this workout earns a review prompt (a new PR or
    /// the third workout); consumed once the finish screen has landed.
    @State private var isReviewMoment = false
    @State private var workoutName: String = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var showOverview = false
    @State private var showOverviewPicker = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var pendingEffort: Int?
    @State private var pendingNote: String?

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }

    private var defaultRestSeconds: Int {
        dataStore.profile.trainingPreferences?.restTimerDefault ?? 90
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if saving || saveError != nil {
                    WorkoutSaveStatusView(saving: saving, error: saveError,
                        retry: { finish(perceivedEffort: pendingEffort, note: pendingNote) },
                        returnToWorkout: { sessionService.cancelFinishAttempt(); saveError = nil })
                        .transition(Self.phaseTransition)
                } else if let session = sessionService.activeSession {
                    content(for: session)
                        .transition(Self.phaseTransition)
                } else if let finished = finishedSession {
                    WorkoutFinishView(
                        session: finished,
                        detectedPRs: finishedPRs,
                        unit: unit,
                        weeklySessionCount: weeklySessionCount(asOf: finished),
                        onClose: { dismiss() }
                    )
                    .task { await requestReviewIfEarned() }
                    .transition(Self.phaseTransition)
                } else {
                    noActiveSession
                        .transition(Self.phaseTransition)
                }
            }
            .appAnimation(AppAnimation.springSmooth, value: saving)
            .appAnimation(AppAnimation.springSmooth, value: finishedSession?.id)
        }
        .interactiveDismissDisabled(saving || saveError != nil)
        // Keep the presenter alive when finishing replaces the active content
        // with the summary. A sheet attached to content(for:) vanished with
        // that branch and its dismiss action could close the workout cover.
        .sheet(isPresented: $showFinishSheet) {
            FinishWorkoutSheet { effort, note in
                finish(perceivedEffort: effort, note: note)
            }
        }
        .onAppear { syncNameFromSession(); sessionService.reconcileRest() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sessionService.reconcileRest() }
        }
        .task(id: sessionService.activeSession?.focus?.rest?.endsAt) {
            guard let end = sessionService.activeSession?.focus?.rest?.endsAt else { return }
            let remaining = max(0, end.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(remaining)) }
            catch { return }
            if scenePhase == .active, sessionService.activeSession?.isPaused == false,
               sessionService.activeSession?.focus?.rest?.endsAt == end {
                // Strong enough to feel with the phone face-down on a bench.
                Haptics.success()
                AccessibilityNotification.Announcement("Rest finished. Your next set is ready.").post()
            }
            sessionService.reconcileRest()
        }
        .onChange(of: sessionService.activeSession?.id) { _, _ in syncNameFromSession() }
    }

    /// Saving → summary (or back to the workout) settles in rather than
    /// cutting.
    private static var phaseTransition: AnyTransition { .opacity.combined(with: .scale(scale: 0.98)) }

    /// Lets the finish screen's celebration play before iOS decides
    /// whether to show its review sheet. `ReviewPromptService` still
    /// applies its own engagement and cooldown gates.
    private func requestReviewIfEarned() async {
        guard isReviewMoment else { return }
        isReviewMoment = false
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        ReviewPromptService.shared.requestReviewIfEligible(using: requestReview)
    }

    /// Saves an in-progress name edit. The field only commits on Return,
    /// so anything that leaves the screen has to commit it explicitly.
    private func commitWorkoutName() {
        let trimmed = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != sessionService.activeSession?.name else { return }
        sessionService.renameWorkout(trimmed)
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    /// Leaves the workout running; the Train tab's "Workout in progress"
    /// banner brings it back.
    private func minimize() {
        commitWorkoutName()
        dismissKeyboard()
        dismiss()
    }

    private func finish(perceivedEffort: Int?, note: String?) {
        guard !saving else { return }
        // Persist the latest workout-name edit FIRST — the .onSubmit-only
        // binding meant a user who typed "Push Day A" then tapped Finish
        // without hitting Return saved the session with a nil name (audit
        // Train C3).
        commitWorkoutName()
        pendingEffort = perceivedEffort
        pendingNote = note
        showFinishSheet = false
        saveError = nil
        saving = true
        Task { @MainActor in
            await Task.yield()
            if let finished = sessionService.finishWorkout(perceivedEffort: perceivedEffort, note: note) {
                finishedSession = finished.session
                finishedPRs = finished.detectedPRs
                isReviewMoment = ReviewPromptService.isWorkoutReviewMoment(
                    detectedPRCount: finished.detectedPRs.count,
                    completedWorkoutCount: SwiftDataRepository.shared.workoutSessionCount())
            } else {
                saveError = sessionService.lastFinishError ?? "Could not save workout. Return to your workout and try again."
                AccessibilityNotification.Announcement("Could not save workout").post()
            }
            saving = false
        }
    }

    private func syncNameFromSession() {
        // Don't clobber an in-progress edit — only adopt the session's
        // name when the user isn't actively typing in the field.
        guard !nameFieldFocused else { return }
        workoutName = sessionService.activeSession?.name ?? ""
    }

    /// Sessions in the trailing 7 days ending on `session`'s day,
    /// itself included — same window `WeeklyMuscleHeatmap` uses for the
    /// Train tab's heatmap, reused here so `WorkoutFinishView`'s
    /// consistency callout and the heatmap always agree on "this week."
    private func weeklySessionCount(asOf session: WorkoutSession) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: session.startedAt)
        let windowStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return SwiftDataRepository.shared.loadWorkoutSessions(startedBetween: windowStart..<windowEnd).count
    }

    // MARK: - Content

    private func content(for session: WorkoutSession) -> some View {
        WorkoutFocusView(
            session: session, unit: unit,
            onAddExercise: { showExercisePicker = true },
            onFinish: { showFinishSheet = true }
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GlassIconButton(icon: "chevron.down", accessibilityLabel: "Minimize workout", action: minimize)
            }
            ToolbarItem(placement: .principal) {
                Menu {
                    Button("Workout overview", systemImage: "list.bullet") { showOverview = true }
                    Button("Add exercise", systemImage: "plus") { showExercisePicker = true }
                    Button { showFinishSheet = true } label: {
                        Text("Finish workout")
                        if session.completedSetCount == 0 {
                            Text("Complete a set first")
                        }
                        Image(systemName: "checkmark")
                    }
                    .disabled(session.completedSetCount == 0)
                    Button(role: .destructive) { showDiscardConfirm = true } label: {
                        Label("Discard workout", systemImage: "trash")
                    }
                } label: {
                    Label("Workout", systemImage: "ellipsis.circle")
                        .font(AppFont.callout).foregroundStyle(AppColor.textPrimary).minimumHitArea()
                }
                .accessibilityLabel("Workout options")
                .accessibilityIdentifier("workout-options")
            }
            ToolbarItem(placement: .topBarTrailing) {
                GlassIconButton(
                    icon: session.isPaused ? "play.fill" : "pause.fill",
                    accessibilityLabel: session.isPaused ? "Resume workout" : "Pause workout"
                ) {
                    dismissKeyboard()
                    sessionService.togglePause()
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    if nameFieldFocused { commitWorkoutName() }
                    dismissKeyboard()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showOverview, onDismiss: commitWorkoutName) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        if let liveSession = sessionService.activeSession {
                            heroHeader(for: liveSession)
                            SessionMuscleCard(session: liveSession)
                            exerciseStack(for: liveSession).disabled(liveSession.isPaused)
                        }
                    }
                    .padding(Spacing.screenPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(AppColor.background.ignoresSafeArea())
                .navigationTitle("Workout overview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { commitWorkoutName(); showOverview = false }
                            .accessibilityIdentifier("workout-overview-done")
                    }
                }
            }
            // Its own presenter: the workout-level picker can't open while
            // this sheet is still up.
            .sheet(isPresented: $showOverviewPicker) {
                ExercisePickerSheet { exercise in
                    sessionService.addExercise(exercise)
                }
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet { exercise in
                sessionService.addExercise(exercise)
            }
        }
        .alert("Discard this workout?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) {
                sessionService.discardWorkout()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Nothing logged so far will be saved.")
        }
    }

    // MARK: - Hero

    private func heroHeader(for session: WorkoutSession) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField("Workout name", text: $workoutName)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .focused($nameFieldFocused)
                    .onSubmit {
                        sessionService.renameWorkout(workoutName)
                    }

                HStack(spacing: Spacing.lg) {
                    // TimelineView redraws only this tile each second, and
                    // stops ticking when the view leaves the screen — an
                    // autoconnected Timer.publish re-rendered the whole
                    // body at 1Hz for as long as the view value existed.
                    TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                        StatTile(
                            label: "Elapsed",
                            value: elapsedFormatted(session, now: context.date),
                            size: .large,
                            surface: .plain
                        )
                    }
                    StatTile(
                        label: "Sets done",
                        value: "\(session.completedSetCount)",
                        size: .large,
                        surface: .plain
                    )
                    StatTile(
                        label: "Volume (\(unit.weightSuffix))",
                        value: "\(Int(unit.weightForDisplay(session.totalVolumeKg).rounded()))",
                        size: .large,
                        surface: .plain
                    )
                }
            }
        }
    }

    private func elapsedFormatted(_ session: WorkoutSession, now: Date) -> String {
        let seconds = session.elapsedSeconds(now: now)
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Exercise stack

    @ViewBuilder
    private func exerciseStack(for session: WorkoutSession) -> some View {
        if session.exercises.isEmpty {
            emptyExerciseState
        } else {
            VStack(spacing: Spacing.md) {
                ForEach(session.exercises) { entry in
                    WorkoutExerciseCard(
                        entry: entry,
                        exercise: library.lookup(id: entry.exerciseID),
                        unit: unit,
                        previousSetsLookup: {
                            sessionService.previousSessionSets(forExerciseID: entry.exerciseID)
                        },
                        progression: sessionService.progression(for: entry),
                        effectiveRestSeconds: entry.restSeconds ?? defaultRestSeconds,
                        supersetLetter: session.supersetLetter(for: entry.id),
                        canSupersetWithNext: session.entryBelow(entry.id).map {
                            $0.supersetGroup == nil || $0.supersetGroup != entry.supersetGroup
                        } ?? false,
                        onSetUpdate: { updated in
                            sessionService.updateSet(updated, inExerciseEntryID: entry.id)
                        },
                        onAddSet: {
                            sessionService.addSet(toExerciseID: entry.id)
                        },
                        onRemoveSet: { setID in
                            sessionService.removeSet(setID: setID,
                                                     fromExerciseEntryID: entry.id)
                        },
                        onRemoveExercise: {
                            sessionService.removeExercise(id: entry.id)
                        },
                        onSetRestSeconds: { seconds in
                            sessionService.setRestSeconds(seconds, forExerciseEntryID: entry.id)
                        },
                        onApplyProgression: {
                            sessionService.applyProgression(toExerciseEntryID: entry.id)
                        },
                        onSupersetWithNext: {
                            sessionService.supersetWithNext(entry.id)
                        },
                        onRemoveFromSuperset: {
                            sessionService.removeFromSuperset(entry.id)
                        }
                    )
                }
            }
        }
    }

    private var emptyExerciseState: some View {
        EmptyStateView(
            icon: "figure.strengthtraining.traditional",
            title: "Add your first exercise",
            message: "Search the library by name, muscle or equipment.",
            action: .init(title: "Add exercise", icon: "plus") { showOverviewPicker = true },
            style: .compact
        )
    }

    // MARK: - No active session fallback

    private var noActiveSession: some View {
        EmptyStateView(
            icon: "figure.run",
            title: "No workout in progress",
            message: "Tap Start on the Train tab to begin a session.",
            action: .init(title: "Close", icon: "xmark") { dismiss() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.ignoresSafeArea())
    }
}

// MARK: - Finish sheet

/// The finish step: an optional effort rating and note, both written onto
/// the session. A sheet rather than the old alert because an alert can't
/// hold a rating control.
private struct FinishWorkoutSheet: View {
    let onFinish: (_ perceivedEffort: Int?, _ note: String?) -> Void

    @State private var effort: Int?
    @State private var note = ""
    @FocusState private var noteFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// `WorkoutSession.perceivedEffort` is a 1–5 rating; label n names n.
    private static let effortLabels = ["Easy", "Moderate", "Hard", "Very hard", "Max"]
    private static let noteLimit = 500

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Your sets and PRs will be saved.")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)

                    effortSection
                    noteSection

                    PrimaryCTAButton(title: "Finish workout", icon: "checkmark") {
                        onFinish(effort, trimmedNote)
                    }
                    .accessibilityIdentifier("confirm-finish-workout")
                }
                .padding(Spacing.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Finish workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { noteFocused = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .liquidGlassPresentation(detents: [.medium, .large])
    }

    private var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var effortSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("How hard was it?")
            // A fixed 1–5 scale: five adaptive word chips wrapped 3 + 2.
            HStack(spacing: Spacing.sm) {
                ForEach(Self.effortLabels.indices, id: \.self) { index in
                    effortChip(value: index + 1, label: Self.effortLabels[index])
                }
            }
            .appAnimation(AppAnimation.springSnappy, value: effort)
            Text(effort.map { Self.effortLabels[$0 - 1] } ?? "1 is easy, 5 is everything you had")
                .font(AppFont.footnote)
                .foregroundStyle(effort == nil ? AppColor.textTertiary : AppColor.textPrimary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }

    private func effortChip(value: Int, label: String) -> some View {
        let isSelected = effort == value
        return Button {
            Haptics.selection()
            effort = isSelected ? nil : value
        } label: {
            Text("\(value)")
                .font(AppFont.headline)
                .monospacedDigit()
                .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(isSelected ? AppColor.accentFill : AppColor.surfaceSecondary.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .stroke(AppColor.glassBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(Text("Effort \(value) of 5, \(label)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Note")
            GlassTextField(
                placeholder: "How did it go?",
                text: $note,
                icon: nil,
                axis: .vertical,
                characterLimit: Self.noteLimit,
                focus: $noteFocused,
                label: "Workout note"
            )
            .lineLimit(3...6)
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Optional")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
    }
}
