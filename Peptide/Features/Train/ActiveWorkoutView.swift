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

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }

    private var defaultRestSeconds: Int {
        dataStore.profile.trainingPreferences?.restTimerDefault ?? 90
    }

    var body: some View {
        NavigationStack {
            if let session = sessionService.activeSession {
                content(for: session)
            } else if let finished = finishedSession {
                WorkoutFinishView(
                    session: finished,
                    detectedPRs: finishedPRs,
                    unit: unit,
                    weeklySessionCount: weeklySessionCount(asOf: finished),
                    onClose: { dismiss() }
                )
                .task { await requestReviewIfEarned() }
            } else {
                noActiveSession
            }
        }
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
            sessionService.reconcileRest()
        }
        .onChange(of: sessionService.activeSession?.id) { _, _ in syncNameFromSession() }
    }

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
        // Persist the latest workout-name edit FIRST — the .onSubmit-only
        // binding meant a user who typed "Push Day A" then tapped Finish
        // without hitting Return saved the session with a nil name (audit
        // Train C3).
        commitWorkoutName()
        guard let finished = sessionService.finishWorkout(perceivedEffort: perceivedEffort, note: note)
        else { return }
        finishedSession = finished.session
        finishedPRs = finished.detectedPRs
        showFinishSheet = false
        isReviewMoment = ReviewPromptService.isWorkoutReviewMoment(
            detectedPRCount: finished.detectedPRs.count,
            completedWorkoutCount: SwiftDataRepository.shared.workoutSessionCount()
        )
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
                GlassIconButton(icon: "xmark", accessibilityLabel: "Minimize workout", action: minimize)
            }
            ToolbarItem(placement: .principal) {
                Menu {
                    Button("Workout overview", systemImage: "list.bullet") { showOverview = true }
                    Button("Add exercise", systemImage: "plus") { showExercisePicker = true }
                    Button("Finish workout", systemImage: "checkmark") { showFinishSheet = true }
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
                        statTile(
                            value: elapsedFormatted(session, now: context.date),
                            label: "Elapsed"
                        )
                    }
                    statTile(
                        value: "\(session.completedSetCount)",
                        label: "Sets done"
                    )
                    statTile(
                        value: "\(Int(unit.weightForDisplay(session.totalVolumeKg).rounded()))",
                        label: "Volume (\(unit.weightSuffix))"
                    )
                }
            }
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppFont.statValueSmall)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        effectiveRestSeconds: entry.restSeconds ?? defaultRestSeconds,
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
                            Haptics.selection()
                            sessionService.setRestSeconds(seconds, forExerciseEntryID: entry.id)
                        }
                    )
                }
            }
        }
    }

    private var emptyExerciseState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, Spacing.lg)
            Text("Add your first exercise")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Pick from 870+ exercises filtered by muscle and equipment.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.md)
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
                        Haptics.success()
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
        return trimmed.isEmpty ? nil : String(trimmed.prefix(Self.noteLimit))
    }

    private var effortSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("How hard was it?")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: Spacing.sm)],
                spacing: Spacing.sm
            ) {
                ForEach(Self.effortLabels.indices, id: \.self) { index in
                    effortChip(value: index + 1, label: Self.effortLabels[index])
                }
            }
        }
    }

    private func effortChip(value: Int, label: String) -> some View {
        let isSelected = effort == value
        return Button {
            Haptics.selection()
            effort = isSelected ? nil : value
        } label: {
            Text(label)
                .font(AppFont.callout.weight(.semibold))
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
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Effort \(value) of 5, \(label)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Note")
            TextField("How did it go?", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .focused($noteFocused)
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .stroke(noteFocused ? AppColor.accentPrimary : AppColor.glassBorder,
                                lineWidth: noteFocused ? 1 : 0.5)
                )
                .accessibilityLabel("Workout note")
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
