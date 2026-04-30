import SwiftUI

/// Sheet for editing a single peptide's schedule. Used both in the protocol builder
/// (per-peptide override editing) and in the protocol detail view (live editing of an
/// existing protocol).
struct PeptideScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss

    let peptide: Peptide
    let defaultSchedule: ProtocolSchedule
    /// `nil` means "follow the protocol default". Non-nil is a custom override.
    let initialOverride: ProtocolSchedule?
    /// Called with `nil` to clear the override (revert to default), or a schedule to set one.
    let onSave: (ProtocolSchedule?) -> Void

    @State private var useCustom: Bool
    @State private var selectedDays: Set<Int>
    @State private var timesPerDay: Int
    @State private var customDose: String

    private static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    init(
        peptide: Peptide,
        defaultSchedule: ProtocolSchedule,
        initialOverride: ProtocolSchedule?,
        onSave: @escaping (ProtocolSchedule?) -> Void
    ) {
        self.peptide = peptide
        self.defaultSchedule = defaultSchedule
        self.initialOverride = initialOverride
        self.onSave = onSave
        let starting = initialOverride ?? defaultSchedule
        _useCustom = State(initialValue: initialOverride != nil)
        _selectedDays = State(initialValue: Set(starting.daysOfWeek))
        _timesPerDay = State(initialValue: starting.timesPerDay)
        _customDose = State(initialValue: initialOverride?.customDose ?? "")
    }

    private var canSave: Bool {
        !useCustom || !selectedDays.isEmpty
    }

    /// Quick-pick suggestions parsed from the peptide's dosageRange (e.g. "200-500 mcg").
    private var dosePresets: [String] {
        let range = peptide.dosageRange
        let parts = range.components(separatedBy: "-")
        guard parts.count == 2 else { return [range] }
        let unit = parts[1].components(separatedBy: " ").dropFirst().joined(separator: " ")
        let lowDigits = parts[0].trimmingCharacters(in: .whitespaces)
        let highRaw = parts[1].trimmingCharacters(in: .whitespaces)
        let highDigits = highRaw.components(separatedBy: " ").first ?? highRaw
        guard let low = Double(lowDigits), let high = Double(highDigits), low < high else {
            return [range]
        }
        let mid = (low + high) / 2
        let format: (Double) -> String = { v in
            v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
        }
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return [
            "\(format(low))\(suffix)",
            "\(format(mid))\(suffix)",
            "\(format(high))\(suffix)"
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        peptideHeader

                        modeToggle

                        if useCustom {
                            GlassCard {
                                VStack(alignment: .leading, spacing: Spacing.lg) {
                                    Label("Custom Schedule", systemImage: "calendar.badge.clock")
                                        .font(AppFont.headline)
                                        .foregroundStyle(AppColor.textPrimary)

                                    ScheduleEditor(
                                        selectedDays: $selectedDays,
                                        timesPerDay: $timesPerDay,
                                        cycleLengthWeeks: nil,
                                        dayNames: Self.dayNames
                                    )
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            doseSection
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            defaultScheduleSummary
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.bottom, Spacing.xxxxl)
                    .padding(.top, Spacing.md)
                    .animation(AppAnimation.springSnappy, value: useCustom)
                }
            }
            .navigationTitle(peptide.abbreviation)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? AppColor.accentPrimary : AppColor.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var peptideHeader: some View {
        GlassCard {
            HStack(spacing: Spacing.md) {
                Image(systemName: peptide.imageSystemName)
                    .font(.system(size: 18))
                    .foregroundStyle(peptide.category.color)
                    .frame(width: 40, height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(peptide.category.color.opacity(0.15))
                    }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(peptide.name)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(peptide.dosageRange)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer()
            }
        }
    }

    private var modeToggle: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Toggle(isOn: $useCustom.animation(AppAnimation.springSnappy)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom schedule")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(useCustom
                             ? "This peptide uses its own days and frequency"
                             : "Follows the protocol default")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                .tint(AppColor.accentPrimary)
            }
        }
    }

    private var defaultScheduleSummary: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Protocol Default", systemImage: "calendar")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                HStack {
                    Text("Days")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                    Text(defaultSchedule.daysDescription)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                }

                Divider().foregroundStyle(AppColor.glassBorder)

                HStack {
                    Text("Times/Day")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                    Text("\(defaultSchedule.timesPerDay)x")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                }
            }
        }
    }

    private var doseSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Dose", systemImage: "scalemass.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("Range: \(peptide.dosageRange)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Text("Override the dose for this peptide. Leave blank to use the default.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)

                HStack(spacing: Spacing.sm) {
                    TextField("e.g., 300 mcg", text: $customDose)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .tint(AppColor.accentPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(Spacing.md)
                        .background {
                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                .fill(AppColor.surfaceElevated)
                                .overlay {
                                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                }
                        }

                    if !customDose.isEmpty {
                        Button {
                            withAnimation(AppAnimation.springSnappy) { customDose = "" }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear dose")
                        .transition(.opacity)
                    }
                }

                if dosePresets.count > 1 {
                    HStack(spacing: Spacing.xs) {
                        ForEach(Array(dosePresets.enumerated()), id: \.offset) { index, preset in
                            let labelPrefix: String
                            switch index {
                            case 0: labelPrefix = "Low"
                            case dosePresets.count - 1: labelPrefix = "High"
                            default: labelPrefix = "Mid"
                            }
                            DoseChip(
                                label: labelPrefix,
                                value: preset,
                                isSelected: customDose == preset
                            ) {
                                withAnimation(AppAnimation.springSnappy) {
                                    customDose = preset
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    }
                }
            }
        }
    }

    private func save() {
        if useCustom {
            let times = generateDefaultTimes(count: timesPerDay)
            let trimmedDose = customDose.trimmingCharacters(in: .whitespacesAndNewlines)
            let schedule = ProtocolSchedule(
                daysOfWeek: selectedDays.sorted(),
                timesPerDay: timesPerDay,
                preferredTimes: times,
                customDose: trimmedDose.isEmpty ? nil : trimmedDose
            )
            onSave(schedule)
        } else {
            onSave(nil)
        }
        dismiss()
    }

    private func generateDefaultTimes(count: Int) -> [String] {
        (1...count).map { index in
            let hour24 = min(8 + (index - 1) * (12 / max(count, 1)), 23)
            let hour12 = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24)
            let period = hour24 >= 12 ? "PM" : "AM"
            return "\(hour12):00 \(period)"
        }
    }
}

private struct DoseChip: View {
    let label: String
    let value: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textTertiary)
                    .textCase(.uppercase)
                Text(value)
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, Spacing.xs)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AppColor.accentPrimary.opacity(0.25) : AppColor.surfaceElevated)
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

#Preview {
    PeptideScheduleSheet(
        peptide: MockPeptides.bpc157,
        defaultSchedule: ProtocolSchedule(
            daysOfWeek: [1, 2, 3, 4, 5],
            timesPerDay: 1,
            preferredTimes: ["8:00 AM"]
        ),
        initialOverride: nil,
        onSave: { _ in }
    )
    .preferredColorScheme(.dark)
}
