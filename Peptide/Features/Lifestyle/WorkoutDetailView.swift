import SwiftUI

/// Full-screen drill-in for the Workout Tracker card. Renders a hero
/// stats summary, a 7-day minutes bar chart, and a history list grouped
/// by week. The existing `WorkoutLogSheet` is reused for quick entry
/// (presented modally) and for swipe-to-delete; this view doesn't try
/// to be a full gym app — just the canonical place to review training
/// trends and clean up a typo.
struct WorkoutDetailView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showLogSheet = false
    /// Cached workout-session list — re-fetched on appear and after
    /// any mutation. Plan C moved the canonical store from
    /// `profile.workoutHistory` (array on the profile blob) to
    /// `StoredWorkoutSession` (SwiftData rows), so this view now
    /// pulls through `SwiftDataRepository.loadWorkoutSessions` and
    /// adapts each session to the legacy `WorkoutEntry` shape that
    /// the existing chart + history list code already understands.
    @State private var historyCache: [WorkoutEntry] = []

    private var history: [WorkoutEntry] { historyCache }

    private func refresh() {
        let sessions = SwiftDataRepository.shared.loadWorkoutSessions()
        historyCache = sessions
            .sorted { $0.startedAt > $1.startedAt }
            .map { Self.entryFromSession($0) }
    }

    /// Lossy adapter: collapses a structured `WorkoutSession` into
    /// the legacy `WorkoutEntry` shape the UI is wired against.
    /// `sets` / `reps` come from the per-set tally when present;
    /// quick-log sessions (empty `exercises`) fall back to parsing
    /// the note string the migration left behind.
    private static func entryFromSession(_ session: WorkoutSession) -> WorkoutEntry {
        let totalSets = session.exercises
            .flatMap(\.sets)
            .count
        let totalReps = session.exercises
            .flatMap(\.sets)
            .reduce(0) { $0 + $1.reps }
        let avgReps = totalSets > 0 ? totalReps / totalSets : 0
        let duration: Int = {
            guard let finished = session.finishedAt else { return 0 }
            return max(0, Int(finished.timeIntervalSince(session.startedAt) / 60))
        }()
        return WorkoutEntry(
            id: session.id,
            date: session.startedAt,
            name: session.name ?? "Workout",
            sets: totalSets,
            reps: avgReps,
            durationMinutes: duration
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                heroSummary
                weeklyChart
                historySection
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Workout Tracker")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showLogSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Log workout")
            }
        }
        .sheet(isPresented: $showLogSheet) {
            WorkoutLogSheet(
                history: history,
                onLog: { entry in
                    dataStore.logWorkout(entry)
                    refresh()
                },
                onDelete: { id in
                    dataStore.deleteWorkout(id: id)
                    refresh()
                },
                onClose: { showLogSheet = false }
            )
        }
        .task { refresh() }
        .onChange(of: showLogSheet) { _, isUp in
            // Re-pull after the sheet closes so any add / delete in
            // the modal lands on the list. External writes (Train-tab
            // session finish) refresh on next push into this view.
            if !isUp { refresh() }
        }
    }

    // MARK: - Hero summary

    private var heroSummary: some View {
        let stats = Stats(from: history)
        return HStack(spacing: Spacing.sm) {
            statTile(
                value: "\(stats.thisWeekCount)",
                caption: "This week",
                detail: stats.thisWeekMinutes > 0 ? "\(stats.thisWeekMinutes) min" : nil
            )
            statTile(
                value: "\(stats.thisMonthCount)",
                caption: "This month",
                detail: stats.thisMonthMinutes > 0 ? "\(stats.thisMonthMinutes) min" : nil
            )
            statTile(
                value: "\(history.count)",
                caption: "All time",
                detail: stats.totalMinutes > 0 ? "\(stats.totalMinutes) min" : nil
            )
        }
    }

    private func statTile(value: String, caption: LocalizedStringKey, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(value)
                .font(AppFont.statValueSmall)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(caption)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
            if let detail {
                Text(detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .monospacedDigit()
            } else {
                Text(" ")
                    .font(AppFont.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .liquidGlass(.rect(cornerRadius: Spacing.cardCornerRadius))
    }

    // MARK: - 7-day bar chart

    private var weeklyChart: some View {
        let bars = sevenDayBars()
        let maxMinutes = max(1, bars.map(\.minutes).max() ?? 0)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text("Last 7 days")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                } icon: {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(AppColor.accentPrimary)
                }
                Spacer()
                Text("\(bars.reduce(0) { $0 + $1.minutes }) min total")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }

            HStack(alignment: .bottom, spacing: Spacing.sm) {
                ForEach(bars) { bar in
                    VStack(spacing: Spacing.xs) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(AppColor.surfaceElevated)
                                .frame(width: 22, height: 96)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppColor.accentLight, AppColor.accentPrimary],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(
                                    width: 22,
                                    height: max(4, 96 * CGFloat(bar.minutes) / CGFloat(maxMinutes))
                                )
                                .opacity(bar.minutes == 0 ? 0 : 1)
                        }
                        .accessibilityElement()
                        .accessibilityLabel("\(bar.label): \(bar.minutes) minutes across \(bar.count) sessions")

                        Text(bar.label)
                            .font(AppFont.caption)
                            .foregroundStyle(
                                bar.isToday ? AppColor.accentLight : AppColor.textTertiary
                            )
                            .fontWeight(bar.isToday ? .semibold : .regular)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .liquidGlass(.rect(cornerRadius: Spacing.cardCornerRadius))
    }

    // MARK: - History grouped by week

    @ViewBuilder
    private var historySection: some View {
        if history.isEmpty {
            EmptyStateView(
                icon: "dumbbell.fill",
                title: "No workouts yet",
                message: "Log your first session to start a training history.",
                action: .init(title: "Log workout", icon: "plus") {
                    showLogSheet = true
                }
            )
        } else {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(historyGroups, id: \.label) { group in
                    weekSection(label: group.label, entries: group.entries)
                }
            }
        }
    }

    private func weekSection(label: String, entries: [WorkoutEntry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)

            VStack(spacing: Spacing.sm) {
                ForEach(entries) { entry in
                    historyRow(entry)
                }
            }
        }
    }

    private func historyRow(_ entry: WorkoutEntry) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppColor.accentPrimary.opacity(0.18))
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(rowSubtitle(for: entry))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer(minLength: 0)

            Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .monospacedDigit()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .contextMenu {
            Button(role: .destructive) {
                Haptics.warning()
                dataStore.deleteWorkout(id: entry.id)
                refresh()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func rowSubtitle(for entry: WorkoutEntry) -> String {
        var parts: [String] = []
        if entry.sets > 0 || entry.reps > 0 {
            parts.append("\(entry.sets)×\(entry.reps)")
        }
        if entry.durationMinutes > 0 {
            parts.append("\(entry.durationMinutes) min")
        }
        if parts.isEmpty {
            parts.append(entry.date.formatted(.dateTime.hour().minute()))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Derived data

    private struct Stats {
        let thisWeekCount: Int
        let thisWeekMinutes: Int
        let thisMonthCount: Int
        let thisMonthMinutes: Int
        let totalMinutes: Int

        init(from history: [WorkoutEntry]) {
            let cal = Calendar.current
            let now = Date()
            let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now

            var thisWeekCount = 0
            var thisWeekMinutes = 0
            var thisMonthCount = 0
            var thisMonthMinutes = 0
            var totalMinutes = 0

            for entry in history {
                totalMinutes += entry.durationMinutes
                if entry.date >= monthStart {
                    thisMonthCount += 1
                    thisMonthMinutes += entry.durationMinutes
                }
                if entry.date >= weekStart {
                    thisWeekCount += 1
                    thisWeekMinutes += entry.durationMinutes
                }
            }

            self.thisWeekCount = thisWeekCount
            self.thisWeekMinutes = thisWeekMinutes
            self.thisMonthCount = thisMonthCount
            self.thisMonthMinutes = thisMonthMinutes
            self.totalMinutes = totalMinutes
        }
    }

    private struct DayBar: Identifiable {
        let id = UUID()
        let label: String
        let minutes: Int
        let count: Int
        let isToday: Bool
    }

    /// Builds 7 bars for the last seven calendar days, oldest → newest.
    /// Empty days render as a faint track so the bar row reads as a
    /// continuous week rather than a sparse smattering.
    private func sevenDayBars() -> [DayBar] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let sessions = history.filter { cal.isDate($0.date, inSameDayAs: day) }
            let minutes = sessions.reduce(0) { $0 + $1.durationMinutes }
            return DayBar(
                label: formatter.string(from: day),
                minutes: minutes,
                count: sessions.count,
                isToday: offset == 0
            )
        }
    }

    private struct HistoryGroup {
        let label: String
        let entries: [WorkoutEntry]
    }

    /// Newest-first list grouped under "This week" / "Last week" /
    /// week-of date labels. Three relative bins keep the recent past
    /// scannable, anything older rolls into "Earlier".
    private var historyGroups: [HistoryGroup] {
        let cal = Calendar.current
        let now = Date()
        let weekInterval = cal.dateInterval(of: .weekOfYear, for: now)
        let thisWeekStart = weekInterval?.start ?? now
        let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart
        let twoWeeksAgo = cal.date(byAdding: .weekOfYear, value: -2, to: thisWeekStart) ?? thisWeekStart

        let sorted = history.sorted { $0.date > $1.date }

        var thisWeek: [WorkoutEntry] = []
        var lastWeek: [WorkoutEntry] = []
        var earlier: [WorkoutEntry] = []

        for entry in sorted {
            if entry.date >= thisWeekStart {
                thisWeek.append(entry)
            } else if entry.date >= lastWeekStart {
                lastWeek.append(entry)
            } else if entry.date >= twoWeeksAgo {
                earlier.append(entry)
            } else {
                earlier.append(entry)
            }
        }

        var groups: [HistoryGroup] = []
        if !thisWeek.isEmpty {
            groups.append(.init(label: "This week", entries: thisWeek))
        }
        if !lastWeek.isEmpty {
            groups.append(.init(label: "Last week", entries: lastWeek))
        }
        if !earlier.isEmpty {
            groups.append(.init(label: "Earlier", entries: earlier))
        }
        return groups
    }
}

#Preview("With history") {
    NavigationStack {
        WorkoutDetailView()
            .environment(DataStore(seedSampleData: true))
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    NavigationStack {
        WorkoutDetailView()
            .environment(DataStore())
    }
    .preferredColorScheme(.dark)
}
