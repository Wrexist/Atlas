import SwiftUI

/// Compact habits card for the Home tab. Two states:
///
/// 1. **Empty** — no habits yet. Single CTA "Track a daily habit"
///    that opens the editor sheet.
/// 2. **Populated** — header (HABITS · N of M done · View all) +
///    a horizontally-scrollable row of today's habit chips with
///    one-tap checkmarks. ~70pt tall, doesn't dominate the Home
///    feed. "View all" opens the full HabitsView with per-habit
///    heatmaps — the place to go for depth.
///
/// Deliberately no expand toggle: the agent polish review noted the
/// 6×7 dot grid was hard to read at 6pt and duplicated what the
/// full view shows in full fidelity. Minimal beats clever.
struct HabitsHomeCard: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showingFullView: Bool = false
    @State private var addingNew: Bool = false

    private var habits: [Habit] { dataStore.activeHabits }

    var body: some View {
        if habits.isEmpty {
            emptyCard
        } else {
            populatedCard
        }
    }

    // MARK: - Empty state

    private var emptyCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            addingNew = true
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(AppColor.accentPrimary.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track a daily habit")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Build streaks for the small things that matter.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
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
        .sheet(isPresented: $addingNew) {
            HabitEditSheet(editing: nil) { habit in
                dataStore.addHabit(habit)
            } onDelete: { _ in }
        }
    }

    // MARK: - Populated state

    private var populatedCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            chipsRow
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
        .sheet(isPresented: $showingFullView) {
            HabitsView()
                .environment(dataStore)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
            Text("HABITS")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(AppColor.textSecondary)
            Text("\(completedCountToday) of \(dueCountToday)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(AppColor.accentPrimary.opacity(0.18))
                )
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                showingFullView = true
            } label: {
                Text("View all")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
            }
            .buttonStyle(.plain)
        }
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(habits.prefix(8)) { habit in
                    chip(for: habit)
                }
                if habits.count > 8 {
                    Button {
                        showingFullView = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("+\(habits.count - 8)")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(height: 32)
                        .padding(.horizontal, Spacing.md)
                        .background(Capsule().fill(AppColor.surfaceSecondary.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View all \(habits.count) habits")
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(for habit: Habit) -> some View {
        let summary = HabitsService.summary(
            for: habit,
            entries: dataStore.profile.habitEntries
        )
        let done = summary.isCompletedToday
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(AppAnimation.springSnappy) {
                dataStore.toggleHabitEntry(habitId: habit.id)
            }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            done ? habit.tint : habit.tint.opacity(0.45),
                            lineWidth: 1.5
                        )
                        .frame(width: 18, height: 18)
                    if done {
                        Circle()
                            .fill(habit.tint)
                            .frame(width: 14, height: 14)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColor.background)
                    } else {
                        Image(systemName: habit.iconSymbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(habit.tint)
                    }
                }
                Text(habit.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(done ? AppColor.textSecondary : AppColor.textPrimary)
                    .lineLimit(1)
                if summary.currentStreak >= 3 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                        Text("\(summary.currentStreak)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: 0xFFB347))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(done ? habit.tint.opacity(0.12) : AppColor.surfaceSecondary.opacity(0.7))
            )
            .overlay(
                Capsule()
                    .strokeBorder(done ? habit.tint.opacity(0.4) : AppColor.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(habit.name)
        .accessibilityValue(accessibilityValue(for: summary, completed: done))
    }

    private func accessibilityValue(
        for summary: HabitsService.Summary,
        completed: Bool
    ) -> String {
        var parts: [String] = []
        parts.append(completed ? "completed today" : "not yet completed")
        if summary.currentStreak >= 3 {
            parts.append("\(summary.currentStreak) day streak")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Derived counts

    /// Computes summaries once per render and caches them so the
    /// header count, chip row, and badge all consult the same
    /// snapshot — previously each pass re-walked the entries array
    /// (audit M4).
    private var todaySummaries: [(habit: Habit, summary: HabitsService.Summary)] {
        habits.map { habit in
            (habit, HabitsService.summary(for: habit, entries: dataStore.profile.habitEntries))
        }
    }

    /// Habits the schedule says are due today. Drives the denominator
    /// in "N of M done".
    private var dueCountToday: Int {
        todaySummaries.filter { $0.summary.isDueToday }.count
    }

    /// Habits that are BOTH due today AND completed. Previously
    /// counted any completed habit regardless of due-ness, so a
    /// M/W/F habit completed on a Tuesday read "1 of 0 done"
    /// (audit H2).
    private var completedCountToday: Int {
        todaySummaries.filter { $0.summary.isDueToday && $0.summary.isCompletedToday }.count
    }
}
