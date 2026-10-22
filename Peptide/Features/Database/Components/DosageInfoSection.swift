import SwiftUI

/// Educational summary of how this peptide is described in published
/// research literature. The values come straight from the canonical
/// `peptides.json` corpus and are NOT a recommendation, prescription, or
/// personalized calculation. Apple Guideline 1.4.1 requires medical info
/// to be paired with citations, so the section surfaces an inline
/// citation count and routes the user to the Research section below.
struct DosageInfoSection: View {
    let peptide: Peptide
    /// Optional callback so the caller can scroll the list to the
    /// `ResearchLinksSection` when the user taps "View sources".
    var onShowSources: (() -> Void)? = nil

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .foregroundStyle(peptide.category.color)
                        .accessibilityHidden(true)
                    Text("Reported in Research")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                }

                Text("Educational summary of values reported in published research literature. Atlas does not recommend, prescribe, or calculate doses — always confirm anything you do with a qualified clinician.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Spacing.md) {
                    let rows = visibleRows
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)
                        }
                        DosageRow(label: row.label, value: row.value, icon: row.id)
                    }
                }

                if !peptide.researchLinks.isEmpty {
                    Button(action: { onShowSources?() }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(AppFont.scaled(11, weight: .semibold))
                            Text(sourcesLabel)
                                .font(AppFont.caption2)
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.down")
                                .font(AppFont.scaled(11, weight: .semibold))
                        }
                        .foregroundStyle(AppColor.accentPrimary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background {
                            Capsule().fill(AppColor.accentPrimary.opacity(0.12))
                        }
                    }
                    .buttonStyle(ScalePressStyle())
                    .accessibilityHint("Scrolls to the research citations for this peptide")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Custom compounds carry no half-life or route, so a row only shows
    /// when it has a value — a blank right column read as a broken screen.
    private var visibleRows: [DosageField] {
        [
            DosageField(id: "scalemass.fill", label: "Reported Range", value: peptide.dosageRange),
            DosageField(id: "clock.fill", label: "Reported Frequency", value: peptide.frequency),
            DosageField(id: "hourglass", label: "Half-Life", value: peptide.halfLife),
            DosageField(id: "cross.vial.fill", label: "Administration", value: peptide.adminRoute)
        ]
        .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var sourcesLabel: LocalizedStringKey {
        peptide.researchLinks.count == 1
            ? "View source citation"
            : "View source citations"
    }
}

/// One labelled value; `id` is its (unique) SF Symbol.
private struct DosageField: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let value: String
}

private struct DosageRow: View {
    let label: LocalizedStringKey
    let value: String
    let icon: String

    var body: some View {
        HStack(alignment: .top) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Text(label)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .layoutPriority(1)
            }

            Spacer(minLength: Spacing.sm)

            Text(value)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        DosageInfoSection(peptide: MockPeptides.bpc157)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
