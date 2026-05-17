import SwiftUI

/// Full-screen habits list — one HabitRowCard per active habit, with
/// an "Add habit" toolbar action and per-row swipe to edit/delete.
/// Opens from the HabitsHomeCard's "View all" button as a sheet, or
/// can be navigated to as a destination.
struct HabitsView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: HabitEditTarget?

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

    private var habits: [Habit] { dataStore.activeHabits }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Spacing.md) {
                    if habits.isEmpty {
                        emptyState
                            .padding(.top, Spacing.xxxxl)
                    } else {
                        ForEach(habits) { habit in
                            let summary = HabitsService.summary(
                                for: habit,
                                entries: dataStore.profile.habitEntries
                            )
                            let days = HabitsService.heatmap(
                                for: habit,
                                entries: dataStore.profile.habitEntries,
                                dayCount: 182
                            )
                            let columns = HabitsService.heatmapColumns(from: days)

                            HabitRowCard(
                                habit: habit,
                                summary: summary,
                                heatmapColumns: columns,
                                heatmapStart: days.first?.date,
                                onToggleToday: {
                                    dataStore.toggleHabitEntry(habitId: habit.id)
                                },
                                onTap: {
                                    editing = .existing(habit)
                                }
                            )
                            .contextMenu {
                                Button {
                                    editing = .existing(habit)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    dataStore.archiveHabit(id: habit.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxl)
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
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    .accessibilityLabel("Add habit")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { target in
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 92, height: 92)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            VStack(spacing: Spacing.sm) {
                Text("No habits yet")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Pick something small — 10 push-ups, 5 minutes of stretching, a glass of water. Consistency compounds.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }
            Button {
                editing = .new
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus")
                    Text("Create your first habit")
                }
                .font(AppFont.headline)
                .foregroundStyle(AppColor.background)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
    }
}
