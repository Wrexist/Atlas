import SwiftUI

/// Train tab landing surface — "Översikt" in the Lyfta reference.
/// Built around three layered cards:
///
///   1. **Weekly muscle map** — anatomical figure that lights up the
///      muscles the user actually trained over the past 7 days. The
///      whole body stays visible at a low baseline so the surface
///      reads even on a fresh install.
///   2. **Top muscles** — three pills under the map calling out the
///      most-worked regions, with the working-set count.
///   3. **Recent workouts** — the last three sessions with date, set
///      count and total volume, tappable into the (future) detail
///      view.
///   4. **Month calendar** — heat-by-day grid for the current month.
///      Days the user trained pulse with the accent colour; rest days
///      stay calm. Mirrors the shape of the existing peptide
///      compliance calendar so the visual language is consistent
///      across tabs.
struct TrainOverviewView: View {
    @State private var library = ExerciseLibrary.shared
    @State private var sessions: [WorkoutSession] = []
    @State private var sessionService = WorkoutSessionService.shared

    private var frequencies: [AnatomicalMuscle: Double] {
        WeeklyMuscleHeatmap.frequencies(
            from: sessions,
            library: library
        )
    }

    private var weekHasTraining: Bool {
        !frequencies.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                startWorkoutButton
                weeklyMuscleCard
                if weekHasTraining {
                    topMusclesRow
                }
                recentWorkoutsCard
                calendarCard
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .refreshable { refresh() }
        .task { @MainActor in
            library.load()
            refresh()
        }
    }

    /// Primary CTA — kicks off an empty workout. Hidden when one's
    /// already in progress (the container surfaces a "Resume" banner
    /// in that case so we don't show two competing actions).
    @ViewBuilder
    private var startWorkoutButton: some View {
        if sessionService.activeSession == nil {
            Button {
                sessionService.startWorkout()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "play.fill")
                    Text("Start workout")
                }
                .font(AppFont.headline)
                .foregroundStyle(AppColor.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.accentPrimary)
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Pulls the latest sessions out of SwiftData. Called on appear
    /// and on pull-to-refresh; the workout-logging screen (next
    /// commit) will broadcast a notification this view can listen to
    /// for live updates after a finish event.
    private func refresh() {
        sessions = SwiftDataRepository.shared.loadWorkoutSessions()
    }

    // MARK: - Weekly muscle map

    private var weeklyMuscleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(weekHasTraining
                         ? "Muscles you trained over the past 7 days."
                         : "Log a workout and watch your body light up.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                MuscleMapView(
                    highlights: MuscleMapView.intensityHighlights(from: frequencies)
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 320)
                .animation(.easeInOut(duration: 0.4), value: frequencies)
            }
        }
    }

    // MARK: - Top muscles row

    private var topMusclesRow: some View {
        let top = WeeklyMuscleHeatmap.topMuscles(from: frequencies)
        return HStack(spacing: Spacing.sm) {
            ForEach(top, id: \.muscle) { item in
                topMusclePill(for: item.muscle, count: item.count)
            }
            Spacer(minLength: 0)
        }
    }

    private func topMusclePill(for muscle: AnatomicalMuscle, count: Double) -> some View {
        let setCount = Int(count.rounded())
        return VStack(spacing: 4) {
            Text(displayName(for: muscle))
                .font(AppFont.chipText)
                .foregroundStyle(AppColor.textPrimary)
            Text("\(setCount) \(setCount == 1 ? "set" : "sets")")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Recent workouts

    private var recentWorkoutsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Recent workouts")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if !sessions.isEmpty {
                        Text("\(sessions.count) total")
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }

                if sessions.isEmpty {
                    emptyRecentWorkouts
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.prefix(3))) { session in
                            recentWorkoutRow(session)
                            if session.id != sessions.prefix(3).last?.id {
                                Divider().background(AppColor.glassBorder)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyRecentWorkouts: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("No sessions yet")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
            Text("Browse the Exercises tab and log your first set — it'll show up here.")
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.vertical, Spacing.sm)
    }

    private func recentWorkoutRow(_ session: WorkoutSession) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name ?? defaultSessionName(for: session))
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.completedSetCount) sets")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                if session.totalVolumeKg > 0 {
                    Text("\(Int(session.totalVolumeKg.rounded())) kg")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func defaultSessionName(for session: WorkoutSession) -> String {
        let dayName = session.startedAt.formatted(.dateTime.weekday(.wide))
        return "\(dayName) workout"
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text(currentMonthLabel)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                }
                TrainingCalendarGrid(sessions: sessions)
            }
        }
    }

    private var currentMonthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date()).capitalized
    }

    // MARK: - Display helpers

    private func displayName(for muscle: AnatomicalMuscle) -> String {
        // Surface friendlier labels on the top-muscles row than the
        // raw enum case names (which are split by side for the map).
        switch muscle {
        case .chest:                                  return "Chest"
        case .abdominals:                             return "Abs"
        case .obliques:                               return "Obliques"
        case .shouldersFront, .shouldersBack:         return "Shoulders"
        case .neckFront:                              return "Neck"
        case .bicepsLeft, .bicepsRight:               return "Biceps"
        case .tricepsLeft, .tricepsRight:             return "Triceps"
        case .forearmsFront, .forearmsBack:           return "Forearms"
        case .quadricepsLeft, .quadricepsRight:       return "Quads"
        case .hamstringsLeft, .hamstringsRight:       return "Hamstrings"
        case .calvesFront, .calvesBack:               return "Calves"
        case .glutesLeft, .glutesRight:               return "Glutes"
        case .adductors:                              return "Adductors"
        case .traps:                                  return "Traps"
        case .lats:                                   return "Lats"
        case .lowerBack:                              return "Lower back"
        }
    }
}

// MARK: - Calendar grid

/// Calendar grid for the current month — one cell per day, tinted by
/// whether the user trained that day. Visually echoes the existing
/// peptide compliance calendar so the two surfaces feel like
/// siblings.
struct TrainingCalendarGrid: View {
    let sessions: [WorkoutSession]

    private var trainedDays: Set<Date> {
        let cal = Calendar.current
        return Set(sessions.map { cal.startOfDay(for: $0.startedAt) })
    }

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        guard let monthInterval = cal.dateInterval(of: .month, for: now),
              let firstDayWeekday = cal.dateComponents([.weekday], from: monthInterval.start).weekday
        else { return AnyView(EmptyView()) }

        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        // Convert to Monday-first column index: Sunday=1 → 6, Monday=2 → 0, …
        let leadingBlanks = (firstDayWeekday + 5) % 7

        return AnyView(
            VStack(spacing: Spacing.xs) {
                weekdayHeaderRow
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                          spacing: 6) {
                    ForEach(0..<leadingBlanks, id: \.self) { _ in
                        Color.clear.frame(height: 28)
                    }
                    ForEach(1...daysInMonth, id: \.self) { day in
                        dayCell(for: day, monthStart: monthInterval.start, calendar: cal)
                    }
                }
            }
        )
    }

    private var weekdayHeaderRow: some View {
        let days = ["M", "T", "W", "T", "F", "S", "S"]
        return HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(for day: Int, monthStart: Date, calendar: Calendar) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
        let trained = trainedDays.contains(calendar.startOfDay(for: date))
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()

        return Text("\(day)")
            .font(AppFont.caption)
            .foregroundStyle(textColor(trained: trained, isToday: isToday, isFuture: isFuture))
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor(trained: trained, isToday: isToday))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isToday ? AppColor.accentPrimary : Color.clear, lineWidth: 1)
            )
    }

    private func textColor(trained: Bool, isToday: Bool, isFuture: Bool) -> Color {
        if isFuture { return AppColor.textTertiary.opacity(0.6) }
        if trained { return AppColor.background }
        if isToday { return AppColor.accentPrimary }
        return AppColor.textSecondary
    }

    private func backgroundColor(trained: Bool, isToday: Bool) -> Color {
        if trained { return AppColor.accentPrimary }
        return Color.clear
    }
}

#Preview {
    TrainOverviewView()
        .padding(.top, Spacing.lg)
        .background(AppColor.background)
        .preferredColorScheme(.dark)
}
