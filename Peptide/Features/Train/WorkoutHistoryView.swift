import SwiftUI

/// Real history list — replaces the hardcoded "No workouts logged
/// yet" placeholder that persisted forever even after 30 finished
/// workouts (audit Train C2). Reads from SwiftDataRepository and
/// groups by month so the user can scan through their year.
struct WorkoutHistoryView: View {
    @State private var groupedSessions: [MonthGroup] = []
    @State private var hasLoaded: Bool = false
    @State private var sessionService = WorkoutSessionService.shared
    @Environment(DataStore.self) private var dataStore

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }

    /// Explicit type rather than a `.init` shorthand inside the call —
    /// leading-dot syntax in an optional-typed ternary is the kind of
    /// inference that reads fine and resolves badly.
    private var startAction: EmptyStateView.Action? {
        guard sessionService.activeSession == nil else { return nil }
        return EmptyStateView.Action(title: "Start a workout", icon: "play.fill") {
            sessionService.startWorkout()
        }
    }

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groupedSessions.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "No workouts logged yet",
                    message: "Once you finish your first session, it'll show up here, grouped by month.",
                    // TrainContainerView presents the active workout as soon
                    // as `activeSession` appears, so starting one here needs
                    // no plumbing back through the parent.
                    action: startAction
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .onAppear(perform: reload)
        // A workout finished or edited elsewhere bumps the revision.
        .onChange(of: dataStore.revision) { _, _ in reload() }
    }

    /// Always hosted inside TrainContainerView's `NavigationStack`, so it
    /// pushes through that stack's `TrainNavigation` destinations rather
    /// than nesting a stack of its own.
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedSessions, id: \.month) { group in
                    Section {
                        VStack(spacing: Spacing.sm) {
                            ForEach(group.sessions) { session in
                                NavigationLink(value: TrainNavigation.workoutDetail(session.id)) {
                                    row(for: session)
                                }
                                .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                            }
                        }
                    } header: {
                        sectionHeader(group.month)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxl)
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.eyebrow)
                .tracking(1.2)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.sm)
        .background(AppColor.background)
    }

    private func row(for session: WorkoutSession) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(session.displayDate)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                Text(session.name ?? "Workout")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(summaryLine(for: session))
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            if let duration = session.durationLabel {
                Label(duration, systemImage: "clock")
                    .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(Spacing.md)
        .contentShape(Rectangle())
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .combine)
    }

    private func summaryLine(for session: WorkoutSession) -> String {
        let exercises = session.exercises.count == 1 ? "1 exercise" : "\(session.exercises.count) exercises"
        let sets = session.completedSetCount == 1 ? "1 set" : "\(session.completedSetCount) sets"
        guard session.totalVolumeKg > 0 else { return "\(exercises) · \(sets)" }
        return "\(exercises) · \(sets) · \(unit.weightLabel(session.totalVolumeKg))"
    }

    // MARK: - Grouping

    private struct MonthGroup: Hashable {
        let month: String
        var sessions: [WorkoutSession]
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    /// Newest month first, newest session first within each month.
    private static func group(_ sessions: [WorkoutSession]) -> [MonthGroup] {
        let sorted = sessions.sorted { $0.historyDate > $1.historyDate }
        var groups: [MonthGroup] = []
        for session in sorted {
            let month = monthFormatter.string(from: session.historyDate)
            if groups.last?.month == month {
                groups[groups.count - 1].sessions.append(session)
            } else {
                groups.append(MonthGroup(month: month, sessions: [session]))
            }
        }
        return groups
    }

    private func reload() {
        let finished = SwiftDataRepository.shared.loadWorkoutSessions()
            .filter { $0.finishedAt != nil }
        groupedSessions = Self.group(finished)
        hasLoaded = true
    }
}

private enum WorkoutHistoryFormat {
    static let rowDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
}

private extension WorkoutSession {
    var historyDate: Date { finishedAt ?? startedAt }

    /// "Mon, Aug 12" — local-relative date label for the row header.
    var displayDate: String {
        WorkoutHistoryFormat.rowDate.string(from: historyDate)
    }

    /// "42m" / "1h 12m" — nil for sessions without a finishedAt
    /// (shouldn't happen for entries in this view since we filter,
    /// but defensive).
    var durationLabel: String? {
        guard finishedAt != nil else { return nil }
        let interval = elapsedSeconds()
        guard interval > 0 else { return nil }
        let totalMinutes = Int(interval / 60)
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
