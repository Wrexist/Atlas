import SwiftUI

struct ScheduleEditor: View {
    @Binding var selectedDays: Set<Int>
    @Binding var timesPerDay: Int
    var cycleLengthWeeks: Binding<Int>?
    let dayNames: [String]

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Day selector
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Days of Week")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                    Button {
                        withAnimation(AppAnimation.springSnappy) {
                            if selectedDays.count == 7 {
                                selectedDays = [1, 2, 3, 4, 5]
                            } else {
                                selectedDays = Set(1...7)
                            }
                        }
                    } label: {
                        Text(selectedDays.count == 7 ? "Weekdays" : "Every day")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
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
                            Text(dayNames[day - 1])
                                .font(AppFont.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textTertiary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? AppColor.accentPrimary.opacity(0.3) : AppColor.surfaceElevated)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
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

            if let cycleBinding = cycleLengthWeeks {
                Divider().foregroundStyle(AppColor.glassBorder)

                // Cycle length
                HStack {
                    Text("Cycle Length")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)

                    Spacer()

                    HStack(spacing: Spacing.md) {
                        Button {
                            withAnimation { cycleBinding.wrappedValue = max(1, cycleBinding.wrappedValue - 1) }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColor.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(AppColor.surfaceElevated))
                        }

                        Text("\(cycleBinding.wrappedValue) wk")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.accentLight)
                            .frame(width: 48)

                        Button {
                            withAnimation { cycleBinding.wrappedValue = min(24, cycleBinding.wrappedValue + 1) }
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
}
