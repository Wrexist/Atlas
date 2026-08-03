import SwiftUI

/// Bevel-style chronological "what happened today" feed — merges
/// dose entries, meals, the daily check-in, and workouts into one
/// vertically sorted timeline. Lets the user read their day as a
/// single story instead of jumping between four sections.
///
/// Build logic is a pure function (`TodayTimelineEvent.build(...)`)
/// so it can be unit-tested without standing up a DataStore.
struct TodayTimelineCard: View {
    let events: [TodayTimelineEvent]

    var body: some View {
        if events.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HomeSectionHeader(eyebrow: "TIMELINE", title: "Your day")

                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        eventRow(event, isLast: index == events.count - 1)
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
                    Text(Self.timeFormatter.string(from: event.date))
                        .font(AppFont.scaled(11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(AppColor.textSecondary)
                    Text(event.title)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if event.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(AppColor.success)
                    } else if event.isPending {
                        Text("PENDING")
                            .font(AppFont.scaled(8, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(AppColor.warning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background {
                                Capsule().fill(AppColor.warning.opacity(0.15))
                            }
                    }
                }
                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func color(for tint: TodayTimelineEvent.TimelineTint) -> Color {
        switch tint {
        case .dose:    AppColor.accentPrimary
        case .meal:    AppColor.macroProtein
        case .checkIn: AppColor.metricHRV
        case .workout: AppColor.metricActivity
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
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
    let isCompleted: Bool
    let isPending: Bool

    enum TimelineTint: Equatable, Sendable {
        case dose, meal, checkIn, workout
    }

    /// Builds the sorted timeline from the day's raw entries.
    /// Caller provides the data; the function decides ordering and
    /// row content. Pure — no DataStore or HealthKit reads.
    static func build(
        doses: [ProtocolEntry],
        meals: [MealEntry],
        checkIn: OutcomeEntry?,
        workouts: [WorkoutEntry],
        now: Date = Date()
    ) -> [TodayTimelineEvent] {
        var events: [TodayTimelineEvent] = []

        for entry in doses {
            events.append(TodayTimelineEvent(
                id: "dose-\(entry.id)",
                date: entry.actualTime ?? entry.date,
                icon: "syringe.fill",
                tint: .dose,
                title: entry.peptide.abbreviation,
                subtitle: entry.dose,
                isCompleted: entry.completed,
                isPending: !entry.completed && (entry.date <= now)
            ))
        }

        for meal in meals {
            events.append(TodayTimelineEvent(
                id: "meal-\(meal.id)",
                date: meal.date,
                icon: meal.category.icon,
                tint: .meal,
                title: meal.name,
                subtitle: "\(meal.calories) kcal · \(meal.proteinG)g protein",
                isCompleted: true,
                isPending: false
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
                subtitle: String(format: "%.1f / 5 across energy, sleep, recovery, mood, focus", avg),
                isCompleted: true,
                isPending: false
            ))
        }

        for workout in workouts {
            events.append(TodayTimelineEvent(
                id: "workout-\(workout.id)",
                date: workout.date,
                icon: "figure.run",
                tint: .workout,
                title: workout.name,
                subtitle: workoutSubtitle(workout),
                isCompleted: true,
                isPending: false
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
        .init(id: "1", date: at(6, 30), icon: "syringe.fill", tint: .dose,
              title: "BPC-157", subtitle: "5 mg",
              isCompleted: true, isPending: false),
        .init(id: "2", date: at(7, 15), icon: "sun.horizon.fill", tint: .meal,
              title: "Oats and berries", subtitle: "420 kcal · 28g protein",
              isCompleted: true, isPending: false),
        .init(id: "3", date: at(8, 0), icon: "figure.run", tint: .workout,
              title: "Push day", subtitle: "45 min · 5×5",
              isCompleted: true, isPending: false),
        .init(id: "4", date: at(18, 0), icon: "syringe.fill", tint: .dose,
              title: "Ipamorelin", subtitle: "200 mcg",
              isCompleted: false, isPending: true),
    ]
    return ZStack {
        AppColor.background.ignoresSafeArea()
        TodayTimelineCard(events: events)
            .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
