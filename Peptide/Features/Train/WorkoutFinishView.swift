import SwiftUI

/// Presented only after a confirmed durable local save.
struct WorkoutFinishView: View {
    let unit: MeasurementUnit
    let onClose: () -> Void
    let celebratesSave: Bool
    /// Records this save set. Cleared after an edit: the edit re-derives
    /// stored records, so these could name a set the user just corrected.
    @State private var detectedPRs: [PRDetectionEngine.DetectedPR]
    @State private var store: WorkoutRecapStore
    @State private var editing = false
    @State private var sharing = false
    @State private var announced = false
    @State private var celebrated = false
    @State private var showsConfetti = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(session: WorkoutSession, detectedPRs: [PRDetectionEngine.DetectedPR],
         unit: MeasurementUnit, weeklySessionCount: Int? = nil, celebratesSave: Bool = true,
         onClose: @escaping () -> Void) {
        self.unit = unit
        self.onClose = onClose
        self.celebratesSave = celebratesSave
        _detectedPRs = State(initialValue: detectedPRs)
        _store = State(initialValue: WorkoutRecapStore(session: session, anchorsWeekOnSession: !celebratesSave))
    }

    var body: some View {
        ScrollView {
            if let summary = store.summary {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(summary)
                        .sectionAppear(index: 0)
                    NavigationLink {
                        WorkoutWeeklyProgressView(store: store, unit: unit)
                    } label: {
                        RecapNavigationRow(icon: "chart.bar.fill") {
                            if let week = store.week {
                                Text("^[\(week.count) workout](inflect: true) \(week.phrase)")
                            } else {
                                Text("Weekly progress unavailable")
                            }
                        }
                    }.buttonStyle(ScalePressStyle()).accessibilityIdentifier("recap-weekly")
                        .sectionAppear(index: 1)
                    if !detectedPRs.isEmpty {
                        RecapNewPRs(prs: detectedPRs, entries: summary.entries, unit: unit)
                            .sectionAppear(index: 1)
                    }
                    VStack(alignment: .trailing, spacing: 0) {
                        RecapMetrics(summary: summary, unit: unit)
                        RecapCalculationNotes(summary: summary)
                    }
                    .sectionAppear(index: 2)
                    NavigationLink {
                        WorkoutRecapExercisesView(store: store, unit: unit)
                    } label: {
                        RecapNavigationRow(icon: "list.bullet") {
                            Text("^[\(summary.entries.count) exercise](inflect: true) · View workout")
                        }
                    }.buttonStyle(ScalePressStyle()).accessibilityIdentifier("recap-exercises")
                        .sectionAppear(index: 3)
                    RecapCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text("Muscle focus").font(AppFont.headline)
                            Text("Estimated from your logged exercises")
                                .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                            RecapAnatomy(muscles: summary.muscles, animatesReveal: true)
                                .frame(maxWidth: 250).frame(maxWidth: .infinity)
                            RecapMuscleNames(muscles: summary.muscles)
                            RecapMissingMapping(count: summary.missingMappings)
                            NavigationLink {
                                WorkoutMuscleDetailsView(summary: summary, unit: unit)
                            } label: {
                                HStack {
                                    Text("View details")
                                    Spacer()
                                    Image(systemName: "chevron.right").accessibilityHidden(true)
                                }
                                .font(AppFont.subheadline)
                                .frame(minHeight: Spacing.minimumHitTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(ScalePressStyle())
                            .accessibilityIdentifier("recap-muscles")
                        }
                    }
                    .sectionAppear(index: 4)
                    if store.metadataUnavailable {
                        Text("Exercise metadata is unavailable. Your saved sets are still shown.").font(AppFont.subheadline)
                        Button("Retry exercise metadata") { Task { await store.load() } }.frame(minHeight: 44)
                    }
                }.padding(Spacing.screenPadding)
            } else { ProgressView("Loading workout…").padding(Spacing.xxl) }
        }
        .background(AppColor.recapBackground.ignoresSafeArea())
        .foregroundStyle(AppColor.recapText).tint(AppColor.recapAction)
        .navigationTitle("Summary").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }.frame(minHeight: 44)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.xs) {
                RecapAction(title: "Done", action: onClose).accessibilityIdentifier("recap-done")
                Button { sharing = true } label: {
                    Label("Share workout", systemImage: "square.and.arrow.up")
                        .font(AppFont.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                }.disabled(store.summary == nil)
            }.padding(.horizontal, Spacing.screenPadding).padding(.top, Spacing.sm)
                .background(AppColor.recapBackground)
        }
        .sheet(isPresented: $editing) {
            WorkoutSavedEditor(session: store.session, unit: unit) { edited in
                try store.saveEdits(edited)
                detectedPRs = []
            }
        }
        .sheet(isPresented: $sharing) {
            if let summary = store.summary { WorkoutShareView(summary: summary, unit: unit) }
        }
        .task {
            await store.load()
            if celebratesSave && !announced {
                announced = true
                celebrated = true
                Haptics.success()
                AccessibilityNotification.Announcement("Workout saved").post()
                await celebratePRs()
            }
        }
        .refreshWorkoutRecap(store)
        .overlay {
            if showsConfetti {
                ConfettiView(colors: [AppColor.achievement, AppColor.recapSuccess, AppColor.recapAction])
                    .ignoresSafeArea()
            }
        }
    }

    /// A fresh save celebrates; reopening an old session from history
    /// leads with when it happened instead of "Workout saved".
    private func header(_ summary: WorkoutRecapEngine.Summary) -> some View {
        VStack(spacing: Spacing.sm) {
            if celebratesSave {
                Image(systemName: "checkmark.circle")
                    .font(AppFont.scaled(52, weight: .regular))
                    .foregroundStyle(AppColor.recapSuccess).accessibilityHidden(true)
                    .symbolEffect(.bounce, value: celebrated)
                Text("Workout saved").font(AppFont.title)
                Text(summary.name).font(AppFont.headline).multilineTextAlignment(.center)
                if let date = summary.session.finishedAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                }
            } else {
                Text(summary.name).font(AppFont.title).multilineTextAlignment(.center)
                if let date = summary.session.finishedAt {
                    Text(date.formatted(date: .complete, time: .shortened))
                        .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, Spacing.sm)
    }

    /// One burst for a fresh save that set a PR. Reduce Motion skips it.
    private func celebratePRs() async {
        guard celebratesSave, !detectedPRs.isEmpty, !reduceMotion else { return }
        showsConfetti = true
        try? await Task.sleep(for: .seconds(2.5))
        showsConfetti = false
    }
}

/// The recap's tappable rows — weekly progress, the exercise list — on the
/// same card as everything around them, with a trailing chevron.
private struct RecapNavigationRow<Title: View>: View {
    let icon: String
    @ViewBuilder let title: Title

    var body: some View {
        RecapCard {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(AppColor.recapSuccess)
                    .accessibilityHidden(true)
                title.font(AppFont.subheadline)
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColor.recapSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Spacing.minimumHitTarget)
        }
        .contentShape(Rectangle())
    }
}

struct RecapNewPRs: View {
    let prs: [PRDetectionEngine.DetectedPR]
    let entries: [WorkoutRecapEngine.Entry]
    let unit: MeasurementUnit

    var body: some View {
        RecapCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(AppColor.achievement)
                        .accessibilityHidden(true)
                    Text("New PRs").font(AppFont.headline)
                }
                .accessibilityAddTraits(.isHeader)
                ForEach(prs, id: \.self) { pr in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(exerciseName(pr.exerciseID)).font(AppFont.subheadline)
                            Text(kindLabel(pr.kind))
                                .font(AppFont.caption).foregroundStyle(AppColor.recapSecondary)
                        }
                        Spacer(minLength: Spacing.sm)
                        Text(valueLabel(pr)).font(AppFont.headline).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func exerciseName(_ id: String) -> String {
        entries.first { $0.exerciseID == id }?.name ?? String(localized: "Exercise")
    }

    private func kindLabel(_ kind: PRDetectionEngine.DetectedPR.Kind) -> String {
        switch kind {
        case .estimatedOneRepMax: String(localized: "Estimated 1RM")
        case .absoluteWeight: String(localized: "Heaviest set")
        case .sessionVolume: String(localized: "Exercise volume")
        case .bodyweightReps: String(localized: "Most reps")
        }
    }

    private func valueLabel(_ pr: PRDetectionEngine.DetectedPR) -> String {
        if pr.kind == .bodyweightReps {
            let reps = Int(pr.value)
            return reps.formatted() + (reps == 1 ? " rep" : " reps")
        }
        let load = unit.weightForDisplay(pr.value).formatted(.number.precision(.fractionLength(0...1)))
        return load + " " + unit.weightSuffix
    }
}

struct RecapMissingMapping: View {
    let count: Int
    var body: some View {
        if count > 0 {
            Text("Muscle mapping unavailable for ^[\(count) exercise](inflect: true)")
                .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
        }
    }
}

/// Caveats on the totals above, behind an info button rather than as
/// permanent fine print on the celebration screen.
struct RecapCalculationNotes: View {
    let summary: WorkoutRecapEngine.Summary

    private var hasNotes: Bool {
        summary.session.exercises.isEmpty || summary.duration == .unavailable || summary.duration == .notTracked
            || summary.volumeKg == nil || summary.excludedVolumeSets > 0 || summary.hasLegacyLoad
    }

    var body: some View {
        if hasNotes {
            RecapInfoButton(title: "How these are counted") {
                if summary.session.exercises.isEmpty { Text("No exercise or set details were recorded for this workout.") }
                if summary.duration == .unavailable { Text("Duration unavailable: no valid elapsed time was recorded.") }
                if summary.duration == .notTracked { Text("This workout was logged without a timer.") }
                if summary.volumeKg == nil { Text("No supported external-load volume recorded.") }
                else if summary.excludedVolumeSets > 0 {
                    Text("Volume excludes ^[\(summary.excludedVolumeSets) set](inflect: true) without supported external-load measurements.")
                }
                if summary.hasLegacyLoad { Text("Volume uses loads as entered. No equipment multiplier is assumed.") }
            }
        }
    }
}
