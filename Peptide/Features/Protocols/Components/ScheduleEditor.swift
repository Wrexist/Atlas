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

    var icon: String {
        switch self {
        case .weekly: "calendar"
        case .interval: "repeat"
        }
    }
}

struct ScheduleEditor: View {
    @Binding var selectedDays: Set<Int>
    @Binding var timesPerDay: Int
    var cycleLengthWeeks: Binding<Int>?
    var cadenceMode: Binding<ScheduleCadenceMode>?
    var intervalDays: Binding<Int>?
    /// Optional bindable list of custom dose times. When provided, the editor
    /// shows per-slot DatePickers; otherwise it just stays in step with
    /// `timesPerDay` and the caller generates default times.
    var preferredTimes: Binding<[String]>?
    let dayNames: [String]

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if let cadenceBinding = cadenceMode {
                LiquidGlassSegmentedControl(
                    selection: cadenceBinding,
                    options: ScheduleCadenceMode.allCases,
                    label: { $0.label },
                    icon: { $0.icon }
                )
            }

            Group {
                if effectiveMode == .weekly {
                    weeklyDaySelector
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity
                        ))
                } else if let intervalBinding = intervalDays {
                    intervalStepper(binding: intervalBinding)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity
                        ))
                }
            }
            .animation(AppAnimation.springSnappy, value: effectiveMode)

            Divider().foregroundStyle(AppColor.glassBorder)

            timesPerDayStepper

            if let timesBinding = preferredTimes {
                preferredTimesEditor(binding: timesBinding)
                    .transition(.opacity)
            }

            if let cycleBinding = cycleLengthWeeks {
                Divider().foregroundStyle(AppColor.glassBorder)
                cycleLengthStepper(binding: cycleBinding)
            }
        }
        .animation(AppAnimation.springSmooth, value: timesPerDay)
    }

    private var effectiveMode: ScheduleCadenceMode {
        cadenceMode?.wrappedValue ?? .weekly
    }

    // MARK: - Weekly day selector

    private var weeklyDaySelector: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Days of Week")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Button {
                    triggerSelectionHaptic()
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
                    DayChip(
                        label: dayNames[day - 1],
                        isSelected: selectedDays.contains(day)
                    ) {
                        triggerSelectionHaptic()
                        withAnimation(AppAnimation.springBouncy) {
                            if selectedDays.contains(day) {
                                selectedDays.remove(day)
                            } else {
                                selectedDays.insert(day)
                            }
                        }
                    }
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

                LiquidGlassStepper(
                    value: binding,
                    range: 1...30,
                    formatter: { $0 == 1 ? "1 day" : "\($0) days" },
                    width: 88
                )
            }

            Text(intervalHint(for: binding.wrappedValue))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .id(binding.wrappedValue)
                .transition(.opacity)
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
            LiquidGlassStepper(
                value: $timesPerDay,
                range: 1...4,
                formatter: { "\($0)" },
                width: 36
            )
        }
    }

    // MARK: - Preferred times editor

    private func preferredTimesEditor(binding: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Dose Times")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)

            VStack(spacing: Spacing.xs) {
                ForEach(0..<timesPerDay, id: \.self) { index in
                    TimeSlotRow(
                        index: index,
                        timeString: timeStringBinding(for: index, in: binding)
                    )
                }
            }
        }
        .onChange(of: timesPerDay) { _, newCount in
            // Keep the array length in sync with the stepper. If the user
            // drops from 3 → 2, we keep the first two; if they bump from 2 →
            // 3, we append a sensible default for the new slot.
            var times = binding.wrappedValue
            if times.count > newCount {
                times = Array(times.prefix(newCount))
            } else if times.count < newCount {
                while times.count < newCount {
                    times.append(Self.defaultTimeString(for: times.count))
                }
            }
            binding.wrappedValue = times
        }
    }

    private func timeStringBinding(
        for index: Int,
        in binding: Binding<[String]>
    ) -> Binding<String> {
        Binding<String>(
            get: {
                let times = binding.wrappedValue
                if index < times.count { return times[index] }
                return Self.defaultTimeString(for: index)
            },
            set: { newValue in
                var times = binding.wrappedValue
                while times.count <= index {
                    times.append(Self.defaultTimeString(for: times.count))
                }
                times[index] = newValue
                binding.wrappedValue = times
            }
        )
    }

    static func defaultTimeString(for index: Int) -> String {
        let presets = ["8:00 AM", "1:00 PM", "6:00 PM", "9:00 PM"]
        if index < presets.count { return presets[index] }
        return "8:00 AM"
    }

    // MARK: - Cycle length

    private func cycleLengthStepper(binding: Binding<Int>) -> some View {
        HStack {
            Text("Cycle Length")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            LiquidGlassStepper(
                value: binding,
                range: 1...24,
                formatter: { "\($0) wk" },
                width: 64
            )
        }
    }

    // MARK: - Haptics

    private func triggerSelectionHaptic() {
        Haptics.selection()
    }
}

// MARK: - DayChip

private struct DayChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(isSelected ? AppColor.accentPrimary.opacity(0.32) : AppColor.surfaceElevated)
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                .strokeBorder(
                                    isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                                    lineWidth: isSelected ? 1 : 0.5
                                )
                        }
                }
                .liquidGlass(.rect(cornerRadius: Spacing.smallCornerRadius))
                .shadow(
                    color: isSelected ? AppColor.accentGlow : .clear,
                    radius: isSelected ? 8 : 0,
                    y: isSelected ? 2 : 0
                )
                .scaleEffect(isSelected ? 1.0 : 0.97)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.92))
    }
}

// MARK: - LiquidGlassSegmentedControl

/// Custom segmented control with a sliding glass-tinted indicator that
/// follows the selection. Replaces `Picker(.segmented)` because the system
/// control can't be tinted to match the rest of the app's liquid-glass
/// styling and animates noticeably less smoothly.
struct LiquidGlassSegmentedControl<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> LocalizedStringKey
    let icon: (Option) -> String

    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                segmentButton(for: option)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    Capsule()
                        .fill(AppColor.cardOverlay)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .liquidGlass(.capsule)
    }

    private func segmentButton(for option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            guard option != selection else { return }
            Haptics.impact(.light)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                selection = option
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(option))
                    .font(.system(size: 11, weight: .semibold))
                Text(label(option))
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(AppColor.accentPrimary.opacity(0.28))
                        .overlay {
                            Capsule().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                        .matchedGeometryEffect(id: "segment-pill", in: pillNamespace)
                        .liquidGlass(.capsule)
                }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.96))
    }
}

// MARK: - LiquidGlassStepper

/// Compact "−  value  +" control with the app's liquid-glass styling. Used
/// for times-per-day, interval days, and cycle weeks so all three stay
/// visually consistent.
struct LiquidGlassStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var formatter: (Int) -> String = { "\($0)" }
    var width: CGFloat = 48

    var body: some View {
        HStack(spacing: Spacing.md) {
            stepperButton(
                icon: "minus",
                isEnabled: value > range.lowerBound
            ) {
                guard value > range.lowerBound else { return }
                tick()
                withAnimation(AppAnimation.springSnappy) { value -= 1 }
            }

            Text(formatter(value))
                .font(AppFont.headline)
                .foregroundStyle(AppColor.accentLight)
                .frame(width: width)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.18), value: value)

            stepperButton(
                icon: "plus",
                isEnabled: value < range.upperBound
            ) {
                guard value < range.upperBound else { return }
                tick()
                withAnimation(AppAnimation.springSnappy) { value += 1 }
            }
        }
    }

    private func stepperButton(
        icon: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? AppColor.textPrimary : AppColor.textTertiary)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(AppColor.surfaceElevated)
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }
                .liquidGlass(.circle)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.88))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func tick() {
        Haptics.selection()
    }
}

// MARK: - TimeSlotRow

/// One editable time slot. Tapping the chip presents a wheel-style time
/// picker; the chip surface itself stays in liquid glass so it lines up
/// visually with the day chips above it.
private struct TimeSlotRow: View {
    let index: Int
    @Binding var timeString: String

    @State private var pickerDate: Date = Date()
    @State private var isShowingPicker = false

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Button {
            pickerDate = Self.formatter.date(from: timeString) ?? Date()
            isShowingPicker = true
            Haptics.impact(.light)
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(AppColor.accentPrimary.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Text("\(index + 1)")
                        .font(AppFont.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentLight)
                        .monospacedDigit()
                }

                Text("Dose \(index + 1)")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                Spacer()

                Text(displayString)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: timeString)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
            .liquidGlass(.rect(cornerRadius: Spacing.smallCornerRadius))
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .sheet(isPresented: $isShowingPicker) {
            TimePickerSheet(
                title: "Dose \(index + 1) Time",
                date: $pickerDate,
                onSave: {
                    timeString = Self.formatter.string(from: pickerDate)
                    isShowingPicker = false
                },
                onCancel: { isShowingPicker = false }
            )
            .liquidGlassPresentation(detents: [.height(360)])
        }
    }

    private var displayString: String {
        if let date = Self.formatter.date(from: timeString) {
            return Self.displayFormatter.string(from: date)
        }
        return timeString
    }
}

private struct TimePickerSheet: View {
    let title: LocalizedStringKey
    @Binding var date: Date
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal, Spacing.screenPadding)

                Spacer()
            }
            .padding(.top, Spacing.lg)
            .background(AppColor.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(AppColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onSave)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
