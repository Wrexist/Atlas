import SwiftUI

struct CustomPeptideForm: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (Peptide) -> Void

    @State private var name = ""
    @State private var abbreviation = ""
    @State private var category: PeptideCategory = .recovery
    @State private var dosageRange = ""
    @State private var frequency = ""
    @State private var notes = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAbbreviation: String {
        abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDosage: String {
        dosageRange.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !trimmedAbbreviation.isEmpty && !trimmedDosage.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        identitySection
                        categorySection
                        dosingSection
                        notesSection
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.vertical, Spacing.lg)
                    .padding(.bottom, Spacing.xxxxl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .dismissKeyboardOnTap()
            .navigationTitle("Add a compound")
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

    private var identitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Identity", systemImage: "tag.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                fieldLabel("Name")
                styledTextField("e.g., Creatine", label: "Name", text: $name)

                fieldLabel("Abbreviation")
                styledTextField("e.g., CRE", label: "Abbreviation", text: $abbreviation)
                    .textInputAutocapitalization(.characters)
            }
        }
    }

    private var categorySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Category", systemImage: "square.grid.2x2.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(PeptideCategory.allCases) { option in
                            GlassChip(
                                option.localizedTitle,
                                icon: option.iconName,
                                tint: option.color,
                                isSelected: category == option
                            ) {
                                category = option
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private var dosingSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Dosing", systemImage: "drop.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                fieldLabel("Dosage range")
                styledTextField("e.g., 200-300 mcg", label: "Dosage range", text: $dosageRange)

                fieldLabel("Frequency")
                styledTextField("e.g., 1x daily (optional)", label: "Frequency", text: $frequency)
            }
        }
    }

    private var notesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Notes", systemImage: "note.text")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                GlassTextField(
                    placeholder: "Optional description or mechanism…",
                    text: $notes,
                    icon: nil,
                    axis: .vertical
                )
                .lineLimit(3...6)
            }
        }
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.caption2)
            .foregroundStyle(AppColor.textTertiary)
    }

    /// `label` is what VoiceOver announces. Without it the field's name is
    /// the placeholder, so the Name field introduced itself as its example
    /// ("e.g., Creatine") — the example read as the label.
    private func styledTextField(_ placeholder: LocalizedStringKey,
                                 label: LocalizedStringKey,
                                 text: Binding<String>) -> some View {
        GlassTextField(placeholder: placeholder, text: text, icon: nil)
            .accessibilityLabel(label)
    }

    private func save() {
        guard canSave else { return }
        let peptide = Peptide(
            name: trimmedName,
            abbreviation: trimmedAbbreviation,
            category: category,
            description: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            benefits: [],
            dosageRange: trimmedDosage,
            frequency: frequency.trimmingCharacters(in: .whitespacesAndNewlines),
            halfLife: "",
            adminRoute: "",
            researchLinks: [],
            imageSystemName: "flask.fill"
        )
        onSave(peptide)
        Haptics.success()
        dismiss()
    }
}

#Preview {
    CustomPeptideForm { _ in }
        .preferredColorScheme(.dark)
}
