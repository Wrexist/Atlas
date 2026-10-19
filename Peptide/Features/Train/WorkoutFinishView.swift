import SwiftUI

/// Presented only after a confirmed durable local save.
struct WorkoutFinishView: View {
    let unit: MeasurementUnit
    let onClose: () -> Void
    let celebratesSave: Bool
    let detectedPRs: [PRDetectionEngine.DetectedPR]
    @State private var store: WorkoutRecapStore
    @State private var editing = false
    @State private var sharing = false
    @State private var announced = false
    @State private var celebrated = false

    init(session: WorkoutSession, detectedPRs: [PRDetectionEngine.DetectedPR],
         unit: MeasurementUnit, weeklySessionCount: Int? = nil, celebratesSave: Bool = true,
         onClose: @escaping () -> Void) {
        self.unit = unit
        self.onClose = onClose
        self.celebratesSave = celebratesSave
        self.detectedPRs = detectedPRs
        _store = State(initialValue: WorkoutRecapStore(session: session))
    }

    var body: some View {
        ScrollView {
            if let summary = store.summary {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(spacing: Spacing.sm) {
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
                    }.frame(maxWidth: .infinity).padding(.vertical, Spacing.sm)
                        .sectionAppear(index: 0)
                        NavigationLink {
                            WorkoutWeeklyProgressView(store: store, unit: unit)
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "chart.bar.fill").foregroundStyle(AppColor.recapSuccess)
                                Text(store.week.map { "\($0.count) workouts this week" } ?? "Weekly progress unavailable")
                                    .font(AppFont.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.padding(Spacing.cardPadding).frame(minHeight: 52)
                                .background(AppColor.recapSuccess.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(ScalePressStyle()).accessibilityIdentifier("recap-weekly")
                        .sectionAppear(index: 1)
                    if !detectedPRs.isEmpty {
                        RecapNewPRs(prs: detectedPRs, entries: summary.entries, unit: unit)
                    }
                    RecapMetrics(summary: summary, unit: unit)
                        .sectionAppear(index: 2)
                    RecapCalculationNotes(summary: summary)
                    NavigationLink {
                        WorkoutRecapExercisesView(store: store, unit: unit)
                    } label: {
                        HStack {
                            Text("\(summary.entries.count) exercises · View workout")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.font(AppFont.subheadline).frame(minHeight: 44)
                    }.accessibilityIdentifier("recap-exercises")
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
                            NavigationLink("View details") {
                                WorkoutMuscleDetailsView(summary: summary, unit: unit)
                            }.font(AppFont.subheadline).frame(minHeight: 44)
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
                Task { await store.load() }
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
            }
        }
        .refreshWorkoutRecap(store)
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
            Text("Muscle mapping unavailable for \(count) \(count == 1 ? "exercise" : "exercises")")
                .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
        }
    }
}

struct RecapCalculationNotes: View {
    let summary: WorkoutRecapEngine.Summary
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if summary.session.exercises.isEmpty { Text("No exercise or set details were recorded for this workout.") }
            if summary.duration == .unavailable { Text("Duration unavailable: no valid elapsed time was recorded.") }
            if summary.duration == .notTracked { Text("This workout was logged without a timer.") }
            if summary.volumeKg == nil { Text("No supported external-load volume recorded.") }
            else if summary.excludedVolumeSets > 0 {
                Text("Volume excludes \(summary.excludedVolumeSets) sets without supported external-load measurements.")
            }
            if summary.hasLegacyLoad { Text("Volume uses loads as recorded. No equipment multiplier is assumed.") }
        }.font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
    }
}
