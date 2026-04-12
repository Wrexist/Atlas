import SwiftUI

struct DoseLoggingSheet: View {
    let entry: ProtocolEntry
    let onLog: (String?, Date?, String?, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var actualDose: String
    @State private var actualTime: Date
    @State private var selectedSite: String?
    @State private var notes: String

    init(entry: ProtocolEntry, onLog: @escaping (String?, Date?, String?, String) -> Void) {
        self.entry = entry
        self.onLog = onLog
        _actualDose = State(initialValue: entry.actualDose ?? entry.dose)
        _actualTime = State(initialValue: entry.actualTime ?? entry.date)
        _selectedSite = State(initialValue: entry.injectionSite)
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Peptide info
                    GlassCard(tinted: true) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: entry.peptide.imageSystemName)
                                .font(.system(size: 24))
                                .foregroundStyle(entry.peptide.category.color)
                                .frame(width: 48, height: 48)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(entry.peptide.category.color.opacity(0.15))
                                }

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(entry.peptide.name)
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                                Text("Scheduled: \(entry.dose) at \(entry.date.formatted(.dateTime.hour().minute()))")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer()
                        }
                    }

                    // Actual dose
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Actual Dose", systemImage: "syringe.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            TextField("e.g., 250 mcg", text: $actualDose)
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

                    // Time
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Time Taken", systemImage: "clock.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            DatePicker("", selection: $actualTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(height: 100)
                                .clipped()
                                .tint(AppColor.accentPrimary)
                        }
                    }

                    // Injection site
                    if entry.peptide.adminRoute.lowercased().contains("subcutaneous") {
                        GlassCard {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Label("Injection Site", systemImage: "figure.arms.open")
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                                    ForEach(InjectionSite.allCases, id: \.rawValue) { site in
                                        let isSelected = selectedSite == site.rawValue
                                        Button {
                                            withAnimation(AppAnimation.springSnappy) {
                                                selectedSite = isSelected ? nil : site.rawValue
                                            }
                                        } label: {
                                            Text(site.rawValue)
                                                .font(AppFont.caption)
                                                .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, Spacing.sm)
                                                .background {
                                                    RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                                                        .fill(isSelected ? AppColor.accentPrimary.opacity(0.15) : AppColor.surfaceElevated)
                                                        .overlay {
                                                            RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
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
                    }

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
                                .lineLimit(2...4)
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

                    // Log button
                    GlassButton(title: "Log Dose", icon: "checkmark.circle.fill", style: .primary, isFullWidth: true) {
                        onLog(actualDose, actualTime, selectedSite, notes)
                        dismiss()
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Log Dose")
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
