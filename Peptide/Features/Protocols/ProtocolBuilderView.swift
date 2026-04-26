import SwiftUI

struct ProtocolBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    var preselectedPeptide: Peptide?
    var editingProtocol: PeptideProtocol?

    @State private var name = ""
    @State private var selectedPeptides: Set<UUID> = []
    @State private var cycleLengthWeeks = 8
    @State private var timesPerDay = 1
    @State private var notes = ""
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var currentStep = 0

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let totalSteps = 2

    private var isEditing: Bool { editingProtocol != nil }

    private var canProceed: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedPeptides.isEmpty
    }

    private var canCreate: Bool {
        canProceed && !selectedDays.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    StepIndicator(currentStep: currentStep, totalSteps: totalSteps)
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.md)

                    ZStack {
                        if currentStep == 0 {
                            detailsStep
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        } else {
                            scheduleStep
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Protocol" : "New Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentStep == 0 {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(AppColor.textSecondary)
                    } else {
                        Button {
                            withAnimation(AppAnimation.springSnappy) {
                                currentStep = 0
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                            }
                            .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if currentStep == 0 {
                        Button("Next") {
                            withAnimation(AppAnimation.springSnappy) {
                                currentStep = 1
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(canProceed ? AppColor.accentPrimary : AppColor.textTertiary)
                        .disabled(!canProceed)
                    }
                }
            }
            .onAppear {
                if let peptide = preselectedPeptide {
                    selectedPeptides.insert(peptide.id)
                }
                if let proto = editingProtocol {
                    name = proto.name
                    selectedPeptides = Set(proto.peptides.map(\.id))
                    cycleLengthWeeks = proto.cycleLengthWeeks
                    timesPerDay = proto.schedule.timesPerDay
                    notes = proto.notes
                    selectedDays = Set(proto.schedule.daysOfWeek)
                }
            }
        }
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("Protocol Name", systemImage: "pencil")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        TextField("e.g., Recovery Stack", text: $name)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .tint(AppColor.accentPrimary)
                            .padding(Spacing.md)
                            .background {
                                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                    .fill(AppColor.surfaceElevated)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                    }
                            }
                    }
                }
                .sectionAppear(index: 0)

                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("Select Peptides", systemImage: "flask.fill")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        PeptideSelector(
                            selectedPeptides: $selectedPeptides,
                            allPeptides: dataStore.peptideDatabase,
                            onAddCustomPeptide: { dataStore.addCustomPeptide($0) }
                        )
                    }
                }
                .sectionAppear(index: 1)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
    }

    private var scheduleStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        Label("Schedule", systemImage: "calendar")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        ScheduleEditor(
                            selectedDays: $selectedDays,
                            timesPerDay: $timesPerDay,
                            cycleLengthWeeks: $cycleLengthWeeks,
                            dayNames: dayNames
                        )
                    }
                }
                .sectionAppear(index: 0)

                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("Notes", systemImage: "note.text")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        TextField("Optional notes...", text: $notes, axis: .vertical)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .tint(AppColor.accentPrimary)
                            .lineLimit(3...6)
                            .padding(Spacing.md)
                            .background {
                                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                    .fill(AppColor.surfaceElevated)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                    }
                            }
                    }
                }
                .sectionAppear(index: 1)

                GlassButton(
                    title: isEditing ? "Save Changes" : "Create Protocol",
                    icon: isEditing ? "checkmark.circle.fill" : "plus.circle.fill",
                    style: .primary,
                    isFullWidth: true
                ) {
                    isEditing ? saveProtocol() : createProtocol()
                }
                .opacity(canCreate ? 1.0 : 0.5)
                .disabled(!canCreate)
                .sectionAppear(index: 2)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
    }

    private func createProtocol() {
        let peptides = dataStore.peptideDatabase.filter { selectedPeptides.contains($0.id) }
        guard !peptides.isEmpty else { return }

        let defaultTimes = (1...timesPerDay).map { index in
            let hour24 = 8 + (index - 1) * (12 / max(timesPerDay, 1))
            let hour12 = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24)
            let period = hour24 >= 12 ? "PM" : "AM"
            return "\(hour12):00 \(period)"
        }

        let newProtocol = PeptideProtocol(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            peptides: peptides,
            schedule: ProtocolSchedule(
                daysOfWeek: selectedDays.sorted(),
                timesPerDay: timesPerDay,
                preferredTimes: defaultTimes
            ),
            cycleLengthWeeks: cycleLengthWeeks,
            startDate: Date(),
            status: .active,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        dataStore.addProtocol(newProtocol)
        dismiss()
    }

    private func saveProtocol() {
        guard let proto = editingProtocol else { return }
        let peptides = dataStore.peptideDatabase.filter { selectedPeptides.contains($0.id) }
        guard !peptides.isEmpty else { return }

        let times: [String]
        if timesPerDay == proto.schedule.timesPerDay {
            times = proto.schedule.preferredTimes
        } else {
            times = generateDefaultTimes(count: timesPerDay)
        }

        dataStore.updateProtocol(
            id: proto.id,
            name: name.trimmingCharacters(in: .whitespaces),
            peptides: peptides,
            schedule: ProtocolSchedule(
                daysOfWeek: selectedDays.sorted(),
                timesPerDay: timesPerDay,
                preferredTimes: times
            ),
            cycleLengthWeeks: cycleLengthWeeks,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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

private struct StepIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? AppColor.accentPrimary : AppColor.surfaceElevated)
                    .frame(height: 4)
                    .overlay {
                        Capsule()
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
                    .animation(AppAnimation.springSmooth, value: currentStep)
            }
        }
    }
}

#Preview {
    ProtocolBuilderView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
