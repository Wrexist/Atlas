import SwiftUI

/// Bevel-style chronological "what happened today" feed — merges
/// meals, the daily check-in, and workouts into one vertically
/// sorted timeline. Doses are left out on purpose: they have one
/// home on Today, the "Today's doses" section, which carries their
/// taken/pending state.
///
/// Build logic is a pure function (`TodayTimelineEvent.build(...)`)
/// so it can be unit-tested without standing up a DataStore.
struct TodayTimelineCard: View {
    let events: [TodayTimelineEvent]
    /// Opens the thing a row describes — Meals, Train, the check-in.
    /// Nil keeps the rows display-only.
    var onTap: ((TodayTimelineEvent) -> Void)?

    var body: some View {
        if events.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HomeSectionHeader(eyebrow: "Timeline", title: "Your day")

                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        tappableRow(event, isLast: index == events.count - 1)
                    }
                }
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.55))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func tappableRow(_ event: TodayTimelineEvent, isLast: Bool) -> some View {
        let row = eventRow(event, isLast: isLast)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: event))
        if let onTap {
            Button { onTap(event) } label: { row }
                .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        } else {
            row
        }
    }

    /// One VoiceOver stop per row: "7:15 AM, Oats and berries, 420 kcal · 28g protein".
    private func accessibilityLabel(for event: TodayTimelineEvent) -> String {
        var parts = [event.date.formatted(date: .omitted, time: .shortened), event.title]
        if let subtitle = event.subtitle { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }

    private func eventRow(_ event: TodayTimelineEvent, isLast: Bool) -> some View {
        let tint = color(for: event.tint)
        return HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                    Image(systemName: event.icon)
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 26, height: 26)

                if !isLast {
                    Rectangle()
                        .fill(AppColor.glassBorder)
                        .frame(width: 1)
                        .frame(minHeight: 16)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(event.date, format: .dateTime.hour().minute())
                        .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textSecondary)
                    Text(event.title)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func color(for tint: TodayTimelineEvent.TimelineTint) -> Color {
        switch tint {
        case .meal:    AppColor.macroProtein
        case .checkIn: AppColor.metricHRV
        case .workout: AppColor.metricActivity
        }
    }
}

// MARK: - Timeline event

/// One row in the timeline. Flat value type so the view stays
/// pure and `build(...)` is callable from tests without a
/// DataStore. Color-free (uses a tint enum) so the type stays
/// `Sendable`.
struct TodayTimelineEvent: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let icon: String
    let tint: TimelineTint
    let title: String
    let subtitle: String?

    enum TimelineTint: Equatable, Sendable {
        case meal, checkIn, workout
    }

    /// Builds the sorted timeline from the day's raw entries.
    /// Caller provides the data; the function decides ordering and
    /// row content. Pure — no DataStore or HealthKit reads.
    static func build(
        meals: [MealEntry],
        checkIn: OutcomeEntry?,
        workouts: [WorkoutEntry]
    ) -> [TodayTimelineEvent] {
        var events: [TodayTimelineEvent] = []

        for meal in meals {
            events.append(TodayTimelineEvent(
                id: "meal-\(meal.id)",
                date: meal.date,
                icon: meal.category.icon,
                tint: .meal,
                title: meal.name,
                subtitle: "\(meal.calories) kcal · \(meal.proteinG)g protein"
            ))
        }

        if let checkIn {
            let avg = Double(checkIn.energy + checkIn.sleepQuality + checkIn.recovery + checkIn.mood + checkIn.focus) / 5.0
            events.append(TodayTimelineEvent(
                id: "checkin-\(checkIn.id)",
                date: checkIn.date,
                icon: "heart.text.square.fill",
                tint: .checkIn,
                title: "Daily check-in",
                subtitle: String(format: "%.1f / 5 across energy, sleep, recovery, mood, focus", avg)
            ))
        }

        for workout in workouts {
            events.append(TodayTimelineEvent(
                id: "workout-\(workout.id)",
                date: workout.date,
                icon: "figure.run",
                tint: .workout,
                title: workout.name,
                subtitle: workoutSubtitle(workout)
            ))
        }

        return events.sorted { $0.date < $1.date }
    }

    private static func workoutSubtitle(_ workout: WorkoutEntry) -> String {
        var parts: [String] = []
        if workout.durationMinutes > 0 { parts.append("\(workout.durationMinutes) min") }
        if workout.sets > 0, workout.reps > 0 {
            parts.append("\(workout.sets)×\(workout.reps)")
        }
        return parts.isEmpty ? "Logged" : parts.joined(separator: " · ")
    }
}

#Preview {
    let now = Date()
    let cal = Calendar.current
    func at(_ h: Int, _ m: Int) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
    }
    let events: [TodayTimelineEvent] = [
        .init(id: "2", date: at(7, 15), icon: "sun.horizon.fill", tint: .meal,
              title: "Oats and berries", subtitle: "420 kcal · 28g protein"),
        .init(id: "3", date: at(8, 0), icon: "figure.run", tint: .workout,
              title: "Push day", subtitle: "45 min · 5×5"),
        .init(id: "4", date: at(18, 30), icon: "heart.text.square.fill", tint: .checkIn,
              title: "Daily check-in", subtitle: "3.8 / 5 across energy, sleep, recovery, mood, focus"),
    ]
    return ZStack {
        AppColor.background.ignoresSafeArea()
        TodayTimelineCard(events: events)
            .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
