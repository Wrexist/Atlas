import SwiftUI

/// Presented only after a confirmed durable local save.
struct WorkoutFinishView: View {
    let unit: MeasurementUnit
    let onClose: () -> Void
    @State private var store: WorkoutRecapStore
    @State private var editing = false
    @State private var sharing = false
    @State private var announced = false

    init(session: WorkoutSession, detectedPRs: [PRDetectionEngine.DetectedPR],
         unit: MeasurementUnit, weeklySessionCount: Int? = nil, onClose: @escaping () -> Void) {
        self.unit = unit
        self.onClose = onClose
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
                        Text("Workout saved").font(AppFont.scaled(30, weight: .bold))
                        Text(summary.name).font(AppFont.headline).multilineTextAlignment(.center)
                        if let date = summary.session.finishedAt {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(AppFont.subheadline).foregroundStyle(AppColor.recapSecondary)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, Spacing.sm)
                    if let week = store.week {
                        NavigationLink {
                            WorkoutWeeklyProgressView(week: week, unit: unit)
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "chart.bar.fill").foregroundStyle(AppColor.recapSuccess)
                                Text("\(week.count) workouts this week").font(AppFont.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.padding(Spacing.cardPadding).frame(minHeight: 52)
                                .background(AppColor.recapSuccess.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).accessibilityIdentifier("recap-weekly")
                    }
                    RecapMetrics(summary: summary, unit: unit)
                    if store.historyUnavailable {
                        Button("Weekly progress unavailable · Retry") { Task { await store.load() } }
                            .font(AppFont.subheadline).frame(minHeight: 44)
                    }
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
                    RecapCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text("Muscle focus").font(AppFont.headline)
                            Text("Estimated from your logged exercises")
                                .font(AppFont.caption).foregroundStyle(AppColor.recapSecondary)
                            RecapAnatomy(muscles: summary.muscles)
                                .frame(maxWidth: 250).frame(maxWidth: .infinity)
                            RecapMuscleNames(muscles: summary.muscles)
                            RecapMissingMapping(count: summary.missingMappings)
                            NavigationLink("View details") {
                                WorkoutMuscleDetailsView(summary: summary, unit: unit)
                            }.font(AppFont.subheadline).frame(minHeight: 44)
                                .accessibilityIdentifier("recap-muscles")
                        }
                    }
                    if store.metadataUnavailable {
                        Text("Exercise metadata is unavailable. Your saved sets are still shown.").font(AppFont.caption)
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
            if !announced {
                announced = true
                Haptics.success()
                AccessibilityNotification.Announcement("Workout saved").post()
            }
        }
    }
}

struct RecapMissingMapping: View {
    let count: Int
    var body: some View {
        if count > 0 {
            Text("Muscle mapping unavailable for \(count) \(count == 1 ? "exercise" : "exercises")")
                .font(AppFont.caption).foregroundStyle(AppColor.recapSecondary)
        }
    }
}

struct RecapCalculationNotes: View {
    let summary: WorkoutRecapEngine.Summary
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if summary.duration == .unavailable { Text("Duration unavailable: no valid elapsed time was recorded.") }
            if summary.duration == .notTracked { Text("This workout was logged without a timer.") }
            if summary.volumeKg == nil { Text("No supported external-load volume recorded.") }
            else if summary.excludedVolumeSets > 0 {
                Text("Volume excludes \(summary.excludedVolumeSets) sets without supported external-load measurements.")
            }
            if summary.hasLegacyLoad { Text("Volume uses loads as recorded. No equipment multiplier is assumed.") }
        }.font(AppFont.caption).foregroundStyle(AppColor.recapSecondary)
    }
}
