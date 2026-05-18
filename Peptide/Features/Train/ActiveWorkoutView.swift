import SwiftUI

/// Full-screen modal that hosts the in-progress workout. Top section:
/// editable name, live elapsed timer, finish action. Middle: scrollable
/// list of `WorkoutExerciseCard`s. Bottom: "Add exercise" CTA.
///
/// State lives in `WorkoutSessionService`; the view is a thin
/// presentation layer that mirrors the service's `activeSession` and
/// dispatches mutations back through service methods. That keeps the
/// "active session is a global truth" invariant straightforward —
/// any other surface (watch, finish screen, widgets) reading the
/// same service sees the same numbers.
struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @State private var sessionService = WorkoutSessionService.shared
    @State private var library = ExerciseLibrary.shared
    @State private var showExercisePicker = false
    @State private var showFinishConfirm = false
    @State private var showDiscardConfirm = false
    @State private var finishedSession: WorkoutSession?
    @State private var finishedPRs: [PRDetectionEngine.DetectedPR] = []
    @State private var workoutName: String = ""
    /// Bumps every second while the workout is active so the elapsed
    /// timer redraws without a publisher boilerplate dance.
    @State private var tick = 0
    /// In-workout rest timer. Driven by the per-exercise restSeconds
    /// or the training preferences default; surfaces a countdown
    /// overlay above the bottom edge and schedules a local
    /// notification so the user gets a buzz even when the phone is
    /// face-down (audit Train H2).
    @State private var restTimer = RestTimerState.inactive
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            if let session = sessionService.activeSession {
                content(for: session)
            } else if let finished = finishedSession {
                WorkoutFinishView(
                    session: finished,
                    detectedPRs: finishedPRs,
                    onClose: { dismiss() }
                )
            } else {
                noActiveSession
            }
        }
        .onReceive(timer) { _ in tick &+= 1 }
        .onAppear { syncNameFromSession() }
        .onChange(of: sessionService.activeSession?.id) { _, _ in syncNameFromSession() }
    }

    private func syncNameFromSession() {
        workoutName = sessionService.activeSession?.name ?? ""
    }

    // MARK: - Content

    private func content(for session: WorkoutSession) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                heroHeader(for: session)
                exerciseStack(for: session)
                addExerciseButton
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Discard", role: .destructive) {
                    showDiscardConfirm = true
                }
                .foregroundStyle(AppColor.destructive)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") {
                    showFinishConfirm = true
                }
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.accentPrimary)
                .disabled(session.completedSetCount == 0)
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet { exercise in
                sessionService.addExercise(exercise)
            }
        }
        .alert("Finish workout?", isPresented: $showFinishConfirm) {
            Button("Finish", role: .none) {
                // Persist the latest workout-name edit FIRST — the
                // .onSubmit-only binding meant a user who typed
                // "Push Day A" then tapped Finish without hitting
                // Return saved the session with a nil name (audit
                // Train C3).
                let trimmed = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sessionService.renameWorkout(trimmed)
                }
                if let finished = sessionService.finishWorkout() {
                    finishedSession = finished.session
                    finishedPRs = finished.detectedPRs
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your sets and PRs will be saved.")
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
        .overlay(alignment: .bottom) {
            RestTimerOverlay(state: $restTimer)
                .animation(AppAnimation.springSmooth, value: restTimer.isRunning)
        }
    }

    // MARK: - Hero

    private func heroHeader(for session: WorkoutSession) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField("Workout name", text: $workoutName)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .onSubmit {
                        sessionService.renameWorkout(workoutName)
                    }

                HStack(spacing: Spacing.lg) {
                    statTile(
                        value: elapsedFormatted(session),
                        label: "Elapsed"
                    )
                    statTile(
                        value: "\(session.completedSetCount)",
                        label: "Sets done"
                    )
                    statTile(
                        value: "\(Int(session.totalVolumeKg.rounded()))",
                        label: "Volume (kg)"
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

    private func elapsedFormatted(_ session: WorkoutSession) -> String {
        // Read `tick` so SwiftUI takes an observation dependency on
        // the 1Hz publisher — without this, the string only refreshes
        // when some other state changes. Do NOT delete: looks like
        // dead code, isn't.
        _ = tick
        let seconds = session.elapsedSeconds()
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
                        previousSetLookup: {
                            sessionService.lastCompletedSet(forExerciseID: entry.exerciseID)
                        },
                        onSetUpdate: { updated in
                            // Detect the "just got checked off"
                            // transition so we can kick the rest
                            // timer. We compare against the entry's
                            // current snapshot before persisting.
                            let priorSnapshot = entry.sets.first(where: { $0.id == updated.id })
                            let wasIncomplete = priorSnapshot?.completed == false
                            sessionService.updateSet(updated, inExerciseEntryID: entry.id)
                            if wasIncomplete && updated.completed && !updated.isWarmup {
                                let seconds = entry.restSeconds
                                    ?? dataStore.profile.trainingPreferences?.restTimerDefault
                                    ?? 90
                                restTimer.start(seconds: seconds)
                            }
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

    private var addExerciseButton: some View {
        Button {
            showExercisePicker = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                Text("Add exercise")
            }
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
