import SwiftUI

/// Full-screen habits list — one HabitRowCard per active habit, with
/// an "Add habit" toolbar action and per-row swipe to edit/delete.
/// Opens from the HabitsHomeCard's "View all" button as a sheet, or
/// can be navigated to as a destination.
struct HabitsView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: HabitEditTarget?
    /// Memoized per-row payload. Rebuilt only when the habit list or
    /// entry list changes — without this, every body invalidation
    /// (scroll, color-scheme flicker, environment change) re-walks
    /// summary + heatmap + columns for every habit (audit Habits P2).
    @State private var rows: [Row] = []

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
            let summary = HabitsService.summary(for: habit, entries: entries)
            let days = HabitsService.heatmap(for: habit, entries: entries, dayCount: 182)
            let columns = HabitsService.heatmapColumns(from: days)
            return Row(habit: habit, summary: summary, columns: columns, heatmapStart: days.first?.date)
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
