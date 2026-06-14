import SwiftUI

/// Immutable snapshot powering the Today habits hero. Built in a `.task` /
/// `.onChange` (not in `body`) so HomeView never re-walks every habit's
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

    static func build(activeHabits: [Habit], entries: [HabitEntry]) -> HabitsHeroSnapshot {
        var items: [Item] = []
        var due = 0
        var done = 0
        var best = 0
        for habit in activeHabits {
            let summary = HabitsService.summary(for: habit, entries: entries)
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
    @State private var snapshot: HabitsHeroSnapshot = .empty
    @State private var addingNew = false

    var body: some View {
        Group {
            if dataStore.activeHabits.isEmpty {
                emptyCard
            } else {
                populatedCard
            }
        }
        .task { rebuild() }
        .onChange(of: dataStore.profile.habitEntries) { _, _ in rebuild() }
        .onChange(of: dataStore.activeHabits) { _, _ in rebuild() }
        .sheet(isPresented: $addingNew) {
            HabitEditSheet(editing: nil) { habit in
                dataStore.addHabit(habit)
            } onDelete: { _ in }
        }
    }

    private func rebuild() {
        snapshot = HabitsHeroSnapshot.build(
            activeHabits: dataStore.activeHabits,
            entries: dataStore.profile.habitEntries
        )
    }

    // MARK: - Populated

    private var populatedCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            summaryRow
            chipsRow
            viewAllButton
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
            Spacer(minLength: Spacing.sm)
            atlasScoreChip
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
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                    Text("done")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
            } else {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
            }
        }
    }

    @ViewBuilder
    private var streakLine: some View {
        if snapshot.bestCurrentStreak > 0 {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.streak)
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

    private var atlasScoreChip: some View {
        let momentum = dataStore.momentum
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("LV \(momentum.level)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(AppColor.accentLight)
            if momentum.todayEarned > 0 {
                Text("+\(momentum.todayEarned) today")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.streak)
                    .contentTransition(.numericText())
            } else {
                Text("\(momentum.score) pts")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(Capsule().fill(AppColor.accentPrimary.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Atlas Score level \(momentum.level), \(momentum.score) points")
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
            HStack(spacing: 4) {
                Text("View all habits")
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColor.accentLight)
        }
        .buttonStyle(.plain)
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
        Button {
            Haptics.impact(.soft)
            addingNew = true
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(AppColor.accentPrimary.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a daily habit")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Small wins, every day. Watch your streak — and your Atlas Score — climb.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColor.accentPrimary)
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
        }
        .buttonStyle(.plain)
    }
}
