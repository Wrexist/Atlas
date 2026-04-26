import SwiftUI

struct WeeklyProgressCircles: View {
    let days: [WeekDayStatus]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                DayCircle(day: day)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct DayCircle: View {
    let day: WeekDayStatus

    private var isCurrentDay: Bool {
        day.status == .today || (day.status == .completed && isCompletedToday)
    }

    // Only true when today's index matches AND the day is completed (so we still highlight the label)
    private var isCompletedToday: Bool {
        guard day.status == .completed else { return false }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let isoDay = weekday == 1 ? 7 : weekday - 1
        return day.id == isoDay
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(day.dayLabel)
                .font(AppFont.caption)
                .foregroundStyle(isCurrentDay ? AppColor.textPrimary : AppColor.textTertiary)
                .fontWeight(isCurrentDay ? .semibold : .regular)

            circleView
                .frame(width: 28, height: 28)
        }
    }

    @ViewBuilder
    private var circleView: some View {
        switch day.status {
        case .completed:
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

        case .partial:
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.35))

                Circle()
                    .strokeBorder(AppColor.accentPrimary, lineWidth: 1.5)
            }

        case .missed:
            Circle()
                .fill(AppColor.surfaceElevated)
                .overlay {
                    Circle()
                        .strokeBorder(AppColor.destructive.opacity(0.25), lineWidth: 1)
                }

        case .today:
            Circle()
                .fill(AppColor.surfaceElevated)
                .overlay {
                    Circle()
                        .strokeBorder(AppColor.accentLight, lineWidth: 2)
                }

        case .future:
            Circle()
                .fill(AppColor.surfaceElevated.opacity(0.5))

        case .noSchedule:
            Circle()
                .fill(AppColor.textTertiary.opacity(0.2))
                .padding(4)
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        WeeklyProgressCircles(days: [
            WeekDayStatus(id: 1, dayLabel: "Mon", status: .completed),
            WeekDayStatus(id: 2, dayLabel: "Tue", status: .completed),
            WeekDayStatus(id: 3, dayLabel: "Wed", status: .partial),
            WeekDayStatus(id: 4, dayLabel: "Thu", status: .missed),
            WeekDayStatus(id: 5, dayLabel: "Fri", status: .today),
            WeekDayStatus(id: 6, dayLabel: "Sat", status: .future),
            WeekDayStatus(id: 7, dayLabel: "Sun", status: .noSchedule),
        ])
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
