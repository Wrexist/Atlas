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
            .navigationTitle("Custom Peptide")
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
                styledTextField("e.g., Selank", text: $name)

                fieldLabel("Abbreviation")
                styledTextField("e.g., SLK", text: $abbreviation)
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
                            categoryChip(option)
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

                fieldLabel("Dosage Range")
                styledTextField("e.g., 200-300 mcg", text: $dosageRange)

                fieldLabel("Frequency")
                styledTextField("e.g., 1x daily (optional)", text: $frequency)
            }
        }
    }

    private var notesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Notes", systemImage: "note.text")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                TextField("Optional description or mechanism...", text: $notes, axis: .vertical)
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
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textTertiary)
    }

    private func styledTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
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

    private func categoryChip(_ option: PeptideCategory) -> some View {
        let isSelected = category == option
        return Button {
            category = option
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.iconName)
                    .font(AppFont.scaled(11, weight: .semibold))
                Text(option.localizedTitle)
                    .font(AppFont.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? option.color : AppColor.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(isSelected ? option.color.opacity(0.18) : AppColor.surfaceElevated)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isSelected ? option.color.opacity(0.5) : AppColor.glassBorder,
                                lineWidth: 0.5
                            )
                    }
            }
        }
        .buttonStyle(.plain)
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
        dismiss()
    }
}

#Preview {
    CustomPeptideForm { _ in }
        .preferredColorScheme(.dark)
}
