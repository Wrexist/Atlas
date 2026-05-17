import SwiftUI

/// Compact, minimizable habits card for the Home tab. Three states:
///
/// 1. **Empty** — no habits yet. Single CTA "Track a daily habit"
///    that opens the full HabitsView in a sheet.
/// 2. **Collapsed** (default after at least one habit exists) — header
///    + horizontally-scrollable row of today's habit chips. ~70pt
///    tall, doesn't dominate the Home feed.
/// 3. **Expanded** — header + collapsed row + a compact daily
///    completion bar at the bottom (today / yesterday / 7-day
///    summary). Tapping the expand chevron toggles.
///
/// All three states surface a "View all" affordance that presents
/// the full HabitsView for editing and the deeper heatmap layouts.
/// Collapsed-by-default keeps the Home feed cohesive; users who care
/// about their habits expand once and it stays expanded across
/// launches via `@AppStorage`.
struct HabitsHomeCard: View {
    @Environment(DataStore.self) private var dataStore
    @AppStorage("habits.home.expanded") private var isExpanded: Bool = false
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
            if isExpanded {
                expandedFooter
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(AppAnimation.springSnappy) { isExpanded.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse habits" : "Expand habits")
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
                        Text("+\(habits.count - 8)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(height: 32)
                            .padding(.horizontal, Spacing.md)
                            .background(Capsule().fill(AppColor.surfaceSecondary.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
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
        .accessibilityValue(done ? "completed today" : "not yet completed")
    }

    // MARK: - Expanded footer (7-day mini-summary)

    private var expandedFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST 7 DAYS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1)
                .foregroundStyle(AppColor.textTertiary)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { dayOffset in
                    weekColumn(dayOffset: 6 - dayOffset)
                }
            }
            .frame(height: 36)
        }
        .padding(.top, 6)
    }

    /// One column = one day. Each row inside the column is a habit's
    /// completion dot for that day; column height auto-sizes so up to
    /// 8 habits visualize cleanly without scroll.
    private func weekColumn(dayOffset: Int) -> some View {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
        let shortLabel: String = {
            let f = DateFormatter()
            f.dateFormat = "E"
            return String(f.string(from: day).prefix(1))
        }()

        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(habits.prefix(6)) { habit in
                    dotFor(habit: habit, day: day)
                }
            }
            Text(shortLabel)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(dayOffset == 0 ? AppColor.accentPrimary : AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func dotFor(habit: Habit, day: Date) -> some View {
        let entry = dataStore.profile.habitEntries.first {
            $0.habitId == habit.id && Calendar.current.isDate($0.date, inSameDayAs: day)
        }
        let target = habit.targetValue ?? 1
        let completed = (entry?.value ?? 0) >= target
        return Circle()
            .fill(completed ? habit.tint : AppColor.surfaceSecondary.opacity(0.6))
            .frame(width: 6, height: 6)
    }

    // MARK: - Derived counts

    private var dueCountToday: Int {
        habits.filter { $0.schedule.isDue(on: Date()) }.count
    }

    private var completedCountToday: Int {
        habits.filter { habit in
            let summary = HabitsService.summary(for: habit, entries: dataStore.profile.habitEntries)
            return summary.isCompletedToday
        }.count
    }
}
