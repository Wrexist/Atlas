import SwiftUI

/// The calendar week at a glance, computed once per training revision so
/// the hero never scans history in `body`.
struct TrainWeekSummary: Equatable {
    /// The seven days of the week holding `now`, from the calendar's own
    /// first weekday.
    let days: [Date]
    let trainedDays: Set<Date>
    let today: Date
    let workoutCount: Int
    let seconds: Int
    let volumeKg: Double

    static let empty = TrainWeekSummary(days: [], trainedDays: [], today: Date(), workoutCount: 0, seconds: 0, volumeKg: 0)

    static func make(from sessions: [WorkoutSession], now: Date = Date(), calendar: Calendar) -> TrainWeekSummary {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return .empty }
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
        let inWeek = sessions.filter { !$0.isActive && $0.dayAnchor >= week.start && $0.dayAnchor < week.end }
        return TrainWeekSummary(
            days: days,
            trainedDays: Set(inWeek.map { $0.day(in: calendar) }),
            today: calendar.startOfDay(for: now),
            workoutCount: inWeek.count,
            seconds: inWeek.reduce(0) { $0 + $1.elapsedSeconds() },
            volumeKg: inWeek.reduce(0) { $0 + $1.totalVolumeKg }
        )
    }
}

/// Train's lit hero: the week as seven day marks, with the count against
/// the user's training-days goal when they set one. Same accent body and
/// lift as Today's hero, held still so the tab reads calm.
struct TrainWeekHeroCard: View {
    let summary: TrainWeekSummary
    /// Days per week from onboarding; nil shows the plain workout count.
    let target: Int?
    let unit: MeasurementUnit
    var calendar: Calendar = .current

    @ScaledMetric(relativeTo: .caption2) private var markHeight: CGFloat = 40

    private var trainedCount: Int { summary.trainedDays.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("This week")
                .font(AppFont.eyebrow)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(AppColor.onAccent.opacity(0.78))
            headline
            dayMarks
                .accessibilityHidden(true)
            footer
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { TrainHeroSurface() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("train-weekly-goal")
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            if let target {
                Text("\(trainedCount)/\(target)")
                    .font(AppFont.statValueSmall)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Training days")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.onAccent.opacity(0.78))
            } else {
                Text("\(summary.workoutCount)")
                    .font(AppFont.statValueSmall)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Workouts")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.onAccent.opacity(0.78))
            }
        }
        .foregroundStyle(AppColor.onAccent)
        .appAnimation(AppAnimation.springSnappy, value: trainedCount)
    }

    private var dayMarks: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(summary.days, id: \.self) { day in
                dayColumn(day)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// A filled pill for a day trained, an outline for one still open;
    /// today's outline is brighter so the eye finds where the week stands.
    private func dayColumn(_ day: Date) -> some View {
        let trained = summary.trainedDays.contains(day)
        let isToday = day == summary.today
        let symbol = calendar.veryShortStandaloneWeekdaySymbols[calendar.component(.weekday, from: day) - 1]
        return VStack(spacing: Spacing.sm) {
            Capsule(style: .continuous)
                .fill(AppColor.onAccent.opacity(trained ? 1 : 0))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AppColor.onAccent.opacity(isToday ? 0.9 : 0.32), lineWidth: isToday ? 1.5 : 1)
                        .opacity(trained ? 0 : 1)
                }
                .frame(width: Spacing.md, height: markHeight)
            Text(symbol)
                .font(AppFont.caption2.weight(isToday ? .bold : .regular))
                .foregroundStyle(AppColor.onAccent.opacity(isToday ? 1 : 0.7))
        }
    }

    @ViewBuilder
    private var footer: some View {
        let reached = target.map { trainedCount >= $0 } ?? false
        Group {
            if reached {
                Text("Goal reached")
            } else if summary.workoutCount > 0 {
                Text("\(durationLabel) · \(unit.weightLabel(summary.volumeKg))")
                    .monospacedDigit()
            } else {
                Text("Your week fills in as you train.")
            }
        }
        .font(AppFont.footnote)
        .foregroundStyle(AppColor.onAccent.opacity(0.78))
    }

    private var durationLabel: String {
        Duration.seconds(summary.seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// The accent body Today's hero uses — key light top left, shade bottom
/// right, gloss and a lit rim — without the drift, so it sits still.
private struct TrainHeroSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Spacing.sheetCornerRadius, style: .continuous)
        mesh
            .clipShape(shape)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [AppColor.onAccent.opacity(0.14), AppColor.onAccent.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [AppColor.onAccent.opacity(0.36), AppColor.onAccent.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .appShadow(AppShadow.paperContact)
            .appShadow(AppShadow.heroLift)
    }

    private var mesh: MeshGradient {
        // Light mode keeps the falloff shallow, as on Today.
        let light = colorScheme == .light
        let deep = AppColor.accentFill.mix(with: AppColor.accentDeep, by: light ? 0.2 : 1)
        let fill = AppColor.accentFill
        let sheen = AppColor.accentFill.mix(with: AppColor.accentSheen, by: light ? 0.6 : 0.8)
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                sheen, sheen, fill,
                sheen, fill, fill,
                fill, fill, deep,
            ]
        )
    }
}
