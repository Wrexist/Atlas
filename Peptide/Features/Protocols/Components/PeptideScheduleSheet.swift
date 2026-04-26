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
    }

    private var canSave: Bool {
        !useCustom || !selectedDays.isEmpty
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

    private func save() {
        if useCustom {
            let times = generateDefaultTimes(count: timesPerDay)
            let schedule = ProtocolSchedule(
                daysOfWeek: selectedDays.sorted(),
                timesPerDay: timesPerDay,
                preferredTimes: times
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
