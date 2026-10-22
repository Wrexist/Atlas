import SwiftUI

/// Immutable snapshot powering the Today habits hero. Built in HomeView's
/// `refreshDerived()` (not in `body`) so HomeView never re-walks every habit's
/// streak summary on a scroll frame (audit A6).
struct HabitsHeroSnapshot: Equatable {
    struct Item: Equatable, Identifiable {
        let habit: Habit
        let isCompleted: Bool
        let isDueToday: Bool
        let currentStreak: Int
        let weeklyCount: Int?
        let weeklyTarget: Int?
        var id: UUID { habit.id }
    }

    let items: [Item]
    let dueCount: Int
    let doneCount: Int
    let bestCurrentStreak: Int

    static let empty = HabitsHeroSnapshot(items: [], dueCount: 0, doneCount: 0, bestCurrentStreak: 0)

    /// 0…1 of today's due habits completed.
    var progress: Double {
        guard dueCount > 0 else { return 0 }
        return min(1, Double(doneCount) / Double(dueCount))
    }

    static func build(activeHabits: [Habit], entries: [HabitEntry], frozenDayKeys: Set<String> = []) -> HabitsHeroSnapshot {
        var items: [Item] = []
        var due = 0
        var done = 0
        var best = 0
        for habit in activeHabits {
            let summary = HabitsService.summary(for: habit, entries: entries, frozenDayKeys: frozenDayKeys)
            let weekly = HabitsService.weeklyProgress(for: habit, entries: entries)
            items.append(
                Item(
                    habit: habit,
                    isCompleted: summary.isCompletedToday,
                    isDueToday: summary.isDueToday,
                    currentStreak: summary.currentStreak,
                    weeklyCount: weekly?.count,
                    weeklyTarget: weekly?.target
                )
            )
            if summary.isDueToday {
                due += 1
                if summary.isCompletedToday { done += 1 }
            }
            best = max(best, summary.currentStreak)
        }
        return HabitsHeroSnapshot(items: items, dueCount: due, doneCount: done, bestCurrentStreak: best)
    }
}

/// Habit-first hero at the top of Today: a daily completion ring, the best
/// active streak, the Atlas Score, and tap-to-complete chips. The app's
/// "what do I do today, and how am I doing?" surface — the first thing the
/// user sees and acts on.
struct TodayHabitsHero: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    /// Built by HomeView once per store revision and day rollover.
    let snapshot: HabitsHeroSnapshot
    @State private var addingNew = false
    @ScaledMetric(relativeTo: .headline) private var emptyIconSize: CGFloat = 40

    var body: some View {
        Group {
            if dataStore.activeHabits.isEmpty {
                emptyCard
                    .transition(.opacity.combined(with: .scale(0.97)))
            } else {
                populatedCard
                    .transition(.opacity.combined(with: .scale(0.97)))
            }
        }
        .appAnimation(AppAnimation.springSmooth, value: dataStore.activeHabits.isEmpty)
        .sheet(isPresented: $addingNew) {
            HabitEditSheet(editing: nil) { habit in
                dataStore.addHabit(habit)
            } onDelete: { _ in }
                .liquidGlassPresentation()
        }
    }

    // MARK: - Populated

    private var populatedCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            summaryRow
            chipsRow
            viewAllButton
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private var summaryRow: some View {
        HStack(spacing: Spacing.md) {
            ring
            VStack(alignment: .leading, spacing: 3) {
                Text("Today's habits")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                streakLine
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryAccessibilityLabel)
    }

    private var ring: some View {
        MetricRing(
            progress: snapshot.progress,
            diameter: 64,
            strokeWidth: 7,
            gradient: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
            appearAnimated: true,
            celebrateAtCompletion: true
        ) {
            if snapshot.dueCount > 0 {
                VStack(spacing: 0) {
                    Text("\(snapshot.doneCount)/\(snapshot.dueCount)")
                        .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                    Text("done")
                        .font(AppFont.badgeSmall)
                        .foregroundStyle(AppColor.textTertiary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                Image(systemName: "leaf.fill")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
            }
        }
    }

    @ViewBuilder
    private var streakLine: some View {
        if snapshot.bestCurrentStreak > 0 {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.streak)
                    .symbolEffect(.bounce, value: snapshot.bestCurrentStreak)
                Text("\(snapshot.bestCurrentStreak) day streak")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
        } else if snapshot.dueCount > 0 {
            Text("Tap one to start your streak")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        } else {
            Text("Nothing due today — rest up")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(snapshot.items) { item in
                    HabitCompletionChip(
                        habit: item.habit,
                        isCompleted: item.isCompleted,
                        currentStreak: item.currentStreak,
                        weeklyCount: item.weeklyCount,
                        weeklyTarget: item.weeklyTarget,
                        onTap: { dataStore.toggleHabitEntry(habitId: item.habit.id) }
                    )
                }
            }
        }
        .scrollClipDisabled()
    }

    private var viewAllButton: some View {
        Button {
            Haptics.impact(.soft)
            appState.selectedTab = .habits
        } label: {
            HStack(spacing: Spacing.xs) {
                Text("View all habits")
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .bold))
            }
            .font(AppFont.chipText)
            .foregroundStyle(AppColor.accentLight)
            .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle())
    }

    private var summaryAccessibilityLabel: String {
        let progress = snapshot.dueCount > 0
            ? "\(snapshot.doneCount) of \(snapshot.dueCount) habits done today"
            : "No habits due today"
        let streak = snapshot.bestCurrentStreak > 0
            ? ", \(snapshot.bestCurrentStreak) day streak"
            : ""
        return progress + streak
    }

    // MARK: - Empty

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Button {
                Haptics.impact(.soft)
                addingNew = true
            } label: {
                HStack(spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(AppColor.accentPrimary.opacity(0.15))
                            .frame(width: emptyIconSize, height: emptyIconSize)
                        Image(systemName: "checkmark.seal.fill")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start a daily habit")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Small wins, every day. Watch your streak — and your Atlas Score — climb.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(AppFont.scaled(24))
                        .foregroundStyle(AppColor.accentPrimary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))

            StarterHabitSuggestions(onPick: addStarter)
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private func addStarter(_ template: HabitTemplate) {
        Haptics.success()
        dataStore.addHabit(template.makeHabit())
    }
}
