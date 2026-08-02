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
                    Image(systemName: "syringe.fill")
                        .foregroundStyle(peptide.category.color)
                        .accessibilityHidden(true)
                    Text("Reported in Research")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if !peptide.researchLinks.isEmpty {
                        citationChip
                    }
                }

                Text("Educational summary of values reported in published research literature. Atlas does not recommend, prescribe, or calculate doses — always confirm anything you do with a qualified clinician.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Spacing.md) {
                    DosageRow(label: "Reported Range", value: peptide.dosageRange, icon: "scalemass.fill")
                    Divider().foregroundStyle(AppColor.glassBorder)
                    DosageRow(label: "Reported Frequency", value: peptide.frequency, icon: "clock.fill")
                    Divider().foregroundStyle(AppColor.glassBorder)
                    DosageRow(label: "Half-Life", value: peptide.halfLife, icon: "hourglass")
                    Divider().foregroundStyle(AppColor.glassBorder)
                    DosageRow(label: "Administration", value: peptide.adminRoute, icon: "cross.vial.fill")
                }

                if !peptide.researchLinks.isEmpty {
                    Button(action: { onShowSources?() }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(AppFont.scaled(12, weight: .semibold))
                            Text(sourcesLabel)
                                .font(AppFont.caption)
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.down")
                                .font(AppFont.scaled(10, weight: .semibold))
                        }
                        .foregroundStyle(AppColor.accentPrimary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background {
                            Capsule().fill(AppColor.accentPrimary.opacity(0.12))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Scrolls to the research citations for this peptide")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var citationChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(AppFont.scaled(10, weight: .bold))
            Text(citationCountText)
                .font(AppFont.scaled(10, weight: .bold))
        }
        .foregroundStyle(AppColor.accentLight)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            Capsule().fill(AppColor.accentPrimary.opacity(0.15))
        }
        .accessibilityLabel(accessibleCitationLabel)
    }

    private var citationCountText: String {
        let count = peptide.researchLinks.count
        return count == 1 ? "1 SOURCE" : "\(count) SOURCES"
    }

    private var accessibleCitationLabel: String {
        let count = peptide.researchLinks.count
        return count == 1 ? "1 research citation" : "\(count) research citations"
    }

    private var sourcesLabel: LocalizedStringKey {
        peptide.researchLinks.count == 1
            ? "View source citation"
            : "View source citations"
    }
}

private struct DosageRow: View {
    let label: LocalizedStringKey
    let value: String
    let icon: String

    var body: some View {
        HStack(alignment: .top) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 20)

                Text(label)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .layoutPriority(1)
            }

            Spacer(minLength: Spacing.sm)

            Text(value)
                .font(AppFont.subheadline)
                .fontWeight(.medium)
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
