import SwiftUI

enum ScheduleCadenceMode: String, CaseIterable, Identifiable {
    case weekly
    case interval

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .weekly: "Days of week"
        case .interval: "Every N days"
        }
    }
}

struct ScheduleEditor: View {
    @Binding var selectedDays: Set<Int>
    @Binding var timesPerDay: Int
    var cycleLengthWeeks: Binding<Int>?
    var cadenceMode: Binding<ScheduleCadenceMode>?
    var intervalDays: Binding<Int>?
    let dayNames: [String]

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if let cadenceBinding = cadenceMode {
                cadencePicker(selection: cadenceBinding)
                Divider().foregroundStyle(AppColor.glassBorder)
            }

            if effectiveMode == .weekly {
                weeklyDaySelector
            } else if let intervalBinding = intervalDays {
                intervalStepper(binding: intervalBinding)
            }

            Divider().foregroundStyle(AppColor.glassBorder)

            timesPerDayStepper

            if let cycleBinding = cycleLengthWeeks {
                Divider().foregroundStyle(AppColor.glassBorder)
                cycleLengthStepper(binding: cycleBinding)
            }
        }
    }

    private var effectiveMode: ScheduleCadenceMode {
        cadenceMode?.wrappedValue ?? .weekly
    }

    // MARK: - Cadence picker

    private func cadencePicker(selection: Binding<ScheduleCadenceMode>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Cadence")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)

            Picker("Cadence", selection: selection) {
                ForEach(ScheduleCadenceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Weekly

    private var weeklyDaySelector: some View {
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
    }

    // MARK: - Interval

    private func intervalStepper(binding: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Every")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                Spacer()

                HStack(spacing: Spacing.md) {
                    Button {
                        withAnimation { binding.wrappedValue = max(1, binding.wrappedValue - 1) }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColor.surfaceElevated))
                    }

                    Text(binding.wrappedValue == 1 ? "1 day" : "\(binding.wrappedValue) days")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.accentLight)
                        .frame(width: 60)
                        .monospacedDigit()

                    Button {
                        withAnimation { binding.wrappedValue = min(30, binding.wrappedValue + 1) }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColor.surfaceElevated))
                    }
                }
            }

            Text(intervalHint(for: binding.wrappedValue))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
    }

    private func intervalHint(for n: Int) -> String {
        switch n {
        case 1: "Doses fire every day."
        case 2: "Doses fire every other day."
        default: "Doses fire every \(n) days, starting today."
        }
    }

    // MARK: - Times per day

    private var timesPerDayStepper: some View {
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
    }

    // MARK: - Cycle length

    private func cycleLengthStepper(binding: Binding<Int>) -> some View {
        HStack {
            Text("Cycle Length")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)

            Spacer()

            HStack(spacing: Spacing.md) {
                Button {
                    withAnimation { binding.wrappedValue = max(1, binding.wrappedValue - 1) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AppColor.surfaceElevated))
                }

                Text("\(binding.wrappedValue) wk")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 48)

                Button {
                    withAnimation { binding.wrappedValue = min(24, binding.wrappedValue + 1) }
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
