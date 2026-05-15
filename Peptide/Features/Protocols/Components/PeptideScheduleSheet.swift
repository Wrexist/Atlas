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
    @State private var cadenceMode: ScheduleCadenceMode
    @State private var intervalDays: Int
    @State private var intervalAnchor: Date
    @State private var preferredTimes: [String]

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
        _cadenceMode = State(initialValue: starting.isInterval ? .interval : .weekly)
        _intervalDays = State(initialValue: starting.intervalDays ?? 3)
        _intervalAnchor = State(initialValue: starting.intervalAnchor ?? Date())
        _preferredTimes = State(initialValue: starting.preferredTimes)
    }

    private var canSave: Bool {
        if !useCustom { return true }
        return cadenceMode == .interval ? intervalDays >= 1 : !selectedDays.isEmpty
    }

    // Pre-filled dose presets were removed to avoid suggesting any specific
    // dose. Users enter their own dose (the one their clinician advised) into
    // the text field; the peptide's reported research range is displayed
    // beside the field for reference only.

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
                                        cadenceMode: $cadenceMode,
                                        intervalDays: $intervalDays,
                                        preferredTimes: $preferredTimes,
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
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
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

                Text("Enter the dose your clinician advised. The research range above is reference only — Atlas does not recommend or calculate doses.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

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
                        .accessibilityLabel("Clear dose")
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear dose")
                        .transition(.opacity)
                    }
                }

            }
        }
    }

    private func save() {
        if useCustom {
            var times = preferredTimes
            while times.count < timesPerDay {
                times.append(ScheduleEditor.defaultTimeString(for: times.count))
            }
            times = Array(times.prefix(timesPerDay))

            let trimmedDose = customDose.trimmingCharacters(in: .whitespacesAndNewlines)
            let schedule = ProtocolSchedule(
                daysOfWeek: cadenceMode == .weekly ? selectedDays.sorted() : [1, 2, 3, 4, 5, 6, 7],
                timesPerDay: timesPerDay,
                preferredTimes: times,
                customDose: trimmedDose.isEmpty ? nil : trimmedDose,
                intervalDays: cadenceMode == .interval ? intervalDays : nil,
                intervalAnchor: cadenceMode == .interval ? intervalAnchor : nil
            )
            onSave(schedule)
        } else {
            onSave(nil)
        }
        dismiss()
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
