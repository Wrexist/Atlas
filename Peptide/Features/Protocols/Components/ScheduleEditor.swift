import SwiftUI

struct ScheduleEditor: View {
    @Binding var selectedDays: Set<Int>
    @Binding var timesPerDay: Int
    @Binding var cycleLengthWeeks: Int
    let dayNames: [String]

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Day selector
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Days of Week")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                HStack(spacing: Spacing.sm) {
                    ForEach(1...7, id: \.self) { day in
                        Button {
                            withAnimation(AppAnimation.springSnappy) {
                                if selectedDays.contains(day) {
                                    selectedDays.remove(day)
                                } else {
                                    selectedDays.insert(day)
                                }
                            }
                        } label: {
                            let isSelected = selectedDays.contains(day)
                            Text(String(dayNames[day - 1].prefix(1)))
                                .font(AppFont.footnote)
                                .fontWeight(.semibold)
                                .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textTertiary)
                                .frame(width: 36, height: 36)
                                .background {
                                    Circle()
                                        .fill(isSelected ? AppColor.accentPrimary.opacity(0.3) : AppColor.surfaceElevated)
                                        .overlay {
                                            Circle()
                                                .strokeBorder(
                                                    isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                                                    lineWidth: 0.5
                                                )
                                        }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().foregroundStyle(AppColor.glassBorder)

            // Times per day
            HStack {
                Text("Times per Day")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                Spacer()

                HStack(spacing: Spacing.md) {
                    Button {
                        withAnimation { timesPerDay = max(1, timesPerDay - 1) }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColor.surfaceElevated))
                    }

                    Text("\(timesPerDay)")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.accentLight)
                        .frame(width: 24)

                    Button {
                        withAnimation { timesPerDay = min(4, timesPerDay + 1) }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColor.surfaceElevated))
                    }
                }
            }

            Divider().foregroundStyle(AppColor.glassBorder)

            // Cycle length
            HStack {
                Text("Cycle Length")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                Spacer()

                HStack(spacing: Spacing.md) {
                    Button {
                        withAnimation { cycleLengthWeeks = max(1, cycleLengthWeeks - 1) }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColor.surfaceElevated))
                    }

                    Text("\(cycleLengthWeeks) wk")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.accentLight)
                        .frame(width: 48)

                    Button {
                        withAnimation { cycleLengthWeeks = min(24, cycleLengthWeeks + 1) }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColor.surfaceElevated))
                    }
                }
            }
        }
    }
}
