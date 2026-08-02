import SwiftUI

/// Full-screen habits list — one HabitRowCard per active habit, with
/// an "Add habit" toolbar action and per-row swipe to edit/delete.
/// Opens from the Today habits hero's "View all" button as a sheet, or
/// can be navigated to as a destination.
struct HabitsView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    /// True when presented as a sheet (shows a Done button). False when
    /// hosted as the Habits tab root, where there's nothing to dismiss.
    var presentedModally = false
    @State private var editing: HabitEditTarget?
    /// Memoized per-row payload. Rebuilt only when the habit list or
    /// entry list changes — without this, every body invalidation
    /// (scroll, color-scheme flicker, environment change) re-walks
    /// summary + heatmap + columns for every habit (audit Habits P2).
    @State private var rows: [Row] = []
    @State private var showProgress = false

    /// One state for both the "add" sheet and the "edit existing" sheet.
    /// Single source of truth so the same sheet binding works for both.
    enum HabitEditTarget: Identifiable {
        case new
        case existing(Habit)
        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let h): return h.id.uuidString
            }
        }
    }

    private struct Row: Identifiable {
        let habit: Habit
        let summary: HabitsService.Summary
        let columns: [[HabitsService.HeatmapStatus?]]
        let heatmapStart: Date?
        var id: UUID { habit.id }
    }

    private var habits: [Habit] { dataStore.activeHabits }

    /// `rows` filtered to habits that still exist. `rows` is rebuilt
    /// asynchronously via `.task(id:)`, so for one frame after a
    /// delete it can still carry the removed habit's card — rendering
    /// (and accepting taps on) a row whose habit is already gone.
    private var visibleRows: [Row] {
        let liveIDs = Set(habits.map(\.id))
        return rows.filter { liveIDs.contains($0.habit.id) }
    }

    /// Cheap-enough equality token. SwiftUI's `.task(id:)` re-runs the
    /// rebuild only when this tuple changes; comparing two Habit /
    /// HabitEntry arrays is the same cost as one rebuild, so we don't
    /// lose anything by skipping a manual digest.
    private struct ChangeToken: Equatable {
        let habits: [Habit]
        let entries: [HabitEntry]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Spacing.md) {
                    if habits.isEmpty {
                        // Empty state — driven by `habits`, not `rows`, so
                        // the first-frame-before-task gap doesn't flash a
                        // false "no habits" message.
                        emptyState
                            .padding(.top, Spacing.xxxxl)
                    } else {
                        if dataStore.habitStreakAtRisk {
                            streakFreezeBanner
                        }
                        habitsSummaryHeader(rows: visibleRows)
                        progressLink
                        ForEach(visibleRows) { row in
                            HabitRowCard(
                                habit: row.habit,
                                summary: row.summary,
                                heatmapColumns: row.columns,
                                heatmapStart: row.heatmapStart,
                                onToggleToday: {
                                    dataStore.toggleHabitEntry(habitId: row.habit.id)
                                },
                                onTap: {
                                    editing = .existing(row.habit)
                                }
                            )
                            .contextMenu {
                                Button {
                                    editing = .existing(row.habit)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    dataStore.archiveHabit(id: row.habit.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxl)
                // iPad cap so the heatmap rows don't stretch into an
                // 1100pt wide strip (Phase 5.8 partial).
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .task(id: ChangeToken(habits: habits, entries: dataStore.profile.habitEntries)) {
                rebuildRows()
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Habits")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = .new
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(AppFont.scaled(20, weight: .semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    .accessibilityLabel("Add habit")
                }
                if presentedModally {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showProgress) {
                AtlasProgressView()
                    .environment(dataStore)
            }
            .sheet(item: $editing) { target in
                Group {
                    switch target {
                    case .new:
                        HabitEditSheet(editing: nil) { habit in
                            dataStore.addHabit(habit)
                        } onDelete: { _ in }
                    case .existing(let habit):
                        HabitEditSheet(editing: habit) { updated in
                            dataStore.updateHabit(updated)
                        } onDelete: { id in
                            dataStore.archiveHabit(id: id)
                        }
                    }
                }
                .liquidGlassPresentation()
            }
        }
    }

    private func rebuildRows() {
        let entries = dataStore.profile.habitEntries
        rows = habits.map { habit in
            let summary = HabitsService.summary(for: habit, entries: entries, frozenDayKeys: dataStore.profile.streakFreezeDays)
            let days = HabitsService.heatmap(for: habit, entries: entries, dayCount: 182)
            let columns = HabitsService.heatmapColumns(from: days)
            return Row(habit: habit, summary: summary, columns: columns, heatmapStart: days.first?.date)
        }
    }

    /// At-a-glance header for the tab root: today's completion ring, best
    /// active streak, and the Atlas Score level. Reuses the per-habit
    /// summaries already built into `rows` (no extra walk) plus the cheap
    /// `dataStore.momentum` arithmetic.
    private func habitsSummaryHeader(rows: [Row]) -> some View {
        let due = rows.filter { $0.summary.isDueToday }.count
        let done = rows.filter { $0.summary.isDueToday && $0.summary.isCompletedToday }.count
        let best = rows.map { $0.summary.currentStreak }.max() ?? 0
        let progress = due > 0 ? min(1, Double(done) / Double(due)) : 0
        let momentum = dataStore.momentum

        return HStack(spacing: Spacing.lg) {
            MetricRing(
                progress: progress,
                diameter: 64,
                strokeWidth: 7,
                gradient: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                appearAnimated: true,
                celebrateAtCompletion: true
            ) {
                if due > 0 {
                    VStack(spacing: 0) {
                        Text("\(done)/\(due)")
                            .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("today")
                            .font(AppFont.scaled(8, weight: .semibold))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                } else {
                    Image(systemName: "leaf.fill")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if best > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(AppColor.streak)
                        Text("\(best) day streak")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                } else {
                    Text("Build your streak")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(AppColor.accentLight)
                    Text("Level \(momentum.level) · \(momentum.score) pts")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(due > 0 ? "\(done) of \(due) habits done today" : "No habits due today")"
            + (best > 0 ? ", \(best) day streak" : "")
            + ", Atlas level \(momentum.level)"
        )
    }

    /// Shown when a streak is at risk and a monthly freeze is available —
    /// one tap shields yesterday so the streak survives. Reuses the existing
    /// `DataStore.applyStreakFreeze` (defaults to yesterday).
    private var streakFreezeBanner: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "snowflake")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.macroWater)
            VStack(alignment: .leading, spacing: 2) {
                Text("Streak at risk")
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("You missed yesterday — use your monthly freeze to keep your streak alive.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                Haptics.success()
                withAnimation(AppAnimation.springSmooth) {
                    dataStore.applyStreakFreeze()
                }
            } label: {
                Text("Freeze")
                    .font(AppFont.subheadline.weight(.bold))
                    .foregroundStyle(AppColor.background)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Capsule().fill(AppColor.macroWater))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.macroWater.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .strokeBorder(AppColor.macroWater.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streak at risk. You missed yesterday. Use your monthly freeze to keep your streak.")
    }

    private var progressLink: some View {
        Button { showProgress = true } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(AppFont.scaled(11, weight: .semibold))
                Text("See your progress")
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
            }
            .font(AppFont.subheadline.weight(.semibold))
            .foregroundStyle(AppColor.accentLight)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your progress")
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            EmptyStateView(
                icon: "checkmark.seal.fill",
                title: "No habits yet",
                message: "Pick something small — 10 push-ups, 5 minutes of stretching, a glass of water. Consistency compounds.",
                action: .init(title: "Create your first habit", icon: "plus") {
                    editing = .new
                }
            )

            StarterHabitSuggestions(onPick: addStarter)
        }
    }

    private func addStarter(_ template: HabitTemplate) {
        Haptics.success()
        dataStore.addHabit(template.makeHabit())
    }
}
