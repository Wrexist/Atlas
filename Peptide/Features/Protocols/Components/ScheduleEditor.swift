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
    /// First dose of an interval schedule; the hint counts from here.
    var intervalAnchor: Date = Date()
    let dayNames: [String]

    /// Short weekday names in the data model's ISO order (index 0 = Monday),
    /// from the user's locale rather than hard-coded English.
    static var isoWeekdayNames: [String] {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        return Array(symbols[1...]) + [symbols[0]]
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if let cadenceBinding = cadenceMode {
                GlassSegmentedControl(
                    options: ScheduleCadenceMode.allCases,
                    selected: cadenceBinding,
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
            .appAnimation(AppAnimation.springSnappy, value: effectiveMode)

            Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)

            timesPerDayStepper

            if let timesBinding = preferredTimes {
                preferredTimesEditor(binding: timesBinding)
                    .transition(.opacity)
            }

            if let cycleBinding = cycleLengthWeeks {
                Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)
                cycleLengthStepper(binding: cycleBinding)
            }
        }
        .appAnimation(AppAnimation.springSmooth, value: timesPerDay)
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
                    AppAnimation.with(AppAnimation.springSnappy) {
                        if selectedDays.count == 7 {
                            selectedDays = [1, 2, 3, 4, 5]
                        } else {
                            selectedDays = Set(1...7)
                        }
                    }
                } label: {
                    Text(selectedDays.count == 7 ? "Weekdays" : "Every day")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.accentPrimary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: Spacing.xs) {
                ForEach(1...7, id: \.self) { day in
                    DayChip(
                        label: dayNames[day - 1],
                        isSelected: selectedDays.contains(day)
                    ) {
                        triggerSelectionHaptic()
                        AppAnimation.with(AppAnimation.springBouncy) {
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
                    label: "Dose interval",
                    value: binding,
                    range: 1...30,
                    formatter: { $0 == 1 ? "1 day" : "\($0) days" },
                    width: 88
                )
            }

            Text(intervalHint(for: binding.wrappedValue))
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
                .id(binding.wrappedValue)
                .transition(.opacity)
        }
    }

    private func intervalHint(for n: Int) -> String {
        let start = intervalAnchor.formatted(.dateTime.month().day())
        switch n {
        case 1: return String(localized: "One dose every day, from \(start)")
        case 2: return String(localized: "One dose every other day, from \(start)")
        default: return String(localized: "One dose every \(n) days, from \(start)")
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
                label: "Times per day",
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
                .font(AppFont.caption2)
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
                label: "Cycle length",
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
                .font(AppFont.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: Spacing.minimumHitTarget)
                .background { selectedFill }
                .chipSurface(isSelected: isSelected)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.92))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A selected day is a solid accent tile carrying `onAccent`; an
    /// unselected one is plain glass. Exactly one of the two paints, so the
    /// chip never stacks a fill under the glass material.
    @ViewBuilder
    private var selectedFill: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.accentFill)
        }
    }
}

private extension View {
    @ViewBuilder
    func chipSurface(isSelected: Bool) -> some View {
        if isSelected {
            self
        } else {
            glassControl(.rect(cornerRadius: Spacing.smallCornerRadius), interactive: false)
        }
    }
}

// MARK: - LiquidGlassStepper

/// Compact "−  value  +" control with the app's liquid-glass styling. Used
/// for times-per-day, interval days, and cycle weeks so all three stay
/// visually consistent.
struct LiquidGlassStepper: View {
    /// What VoiceOver announces for the whole control; the value and the
    /// swipe-to-adjust action ride on the same element.
    let label: LocalizedStringKey
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
                AppAnimation.with(AppAnimation.springSnappy) { value -= 1 }
            }

            Text(formatter(value))
                .font(AppFont.headline)
                .foregroundStyle(AppColor.accentLight)
                .frame(width: width)
                .monospacedDigit()
                .contentTransition(.numericText())
                .appAnimation(AppAnimation.quick, value: value)

            stepperButton(
                icon: "plus",
                isEnabled: value < range.upperBound
            ) {
                guard value < range.upperBound else { return }
                tick()
                AppAnimation.with(AppAnimation.springSnappy) { value += 1 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(formatter(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where value < range.upperBound: value += 1
            case .decrement where value > range.lowerBound: value -= 1
            default: break
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
                .font(AppFont.scaled(11, weight: .bold))
                .foregroundStyle(isEnabled ? AppColor.textPrimary : AppColor.textTertiary)
                .frame(width: 30, height: 30)
                .glassControl(.circle)
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.88))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        // Folded into the stepper's single adjustable element above; kept
        // so the button is never an unlabelled control on its own.
        .accessibilityLabel(icon == "minus" ? "Decrease" : "Increase")
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
                        .font(AppFont.caption2)
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
                    .appAnimation(AppAnimation.quick, value: timeString)

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .glassControl(.rect(cornerRadius: Spacing.smallCornerRadius))
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
    }
}
