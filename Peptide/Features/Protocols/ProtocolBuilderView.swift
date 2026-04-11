import SwiftUI

struct ProtocolBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedPeptides: Set<UUID> = []
    @State private var cycleLengthWeeks = 8
    @State private var timesPerDay = 1
    @State private var notes = ""
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5]

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Name
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

                    // Peptide Selection
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Select Peptides", systemImage: "flask.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            PeptideSelector(selectedPeptides: $selectedPeptides)
                        }
                    }
                    .sectionAppear(index: 1)

                    // Schedule
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
                    .sectionAppear(index: 2)

                    // Notes
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
                    .sectionAppear(index: 3)

                    // Create Button
                    GlassButton(title: "Create Protocol", icon: "plus.circle.fill", style: .primary, isFullWidth: true) {
                        dismiss()
                    }
                    .sectionAppear(index: 4)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("New Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }
}

#Preview {
    ProtocolBuilderView()
        .preferredColorScheme(.dark)
}
