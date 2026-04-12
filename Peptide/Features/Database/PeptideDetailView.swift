import SwiftUI

struct PeptideDetailView: View {
    let peptide: Peptide
    @Environment(\.dismiss) private var dismiss
    @State private var showingBuilder = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Hero Section
                VStack(spacing: Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(peptide.category.color.opacity(0.15))
                            .frame(width: 80, height: 80)
                            .overlay {
                                Circle()
                                    .strokeBorder(peptide.category.color.opacity(0.3), lineWidth: 1)
                            }

                        Image(systemName: peptide.imageSystemName)
                            .font(.system(size: 32))
                            .foregroundStyle(peptide.category.color)
                    }
                    .glassEffect(in: .circle)
                    .sectionAppear(index: 0)

                    VStack(spacing: Spacing.sm) {
                        Text(peptide.abbreviation)
                            .font(AppFont.largeTitle)
                            .foregroundStyle(AppColor.textPrimary)

                        Text(peptide.name)
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)

                        PeptideCategoryBadge(category: peptide.category)
                    }
                    .sectionAppear(index: 1)

                    GlassButton(title: "Add to Protocol", icon: "plus", style: .primary) {
                        showingBuilder = true
                    }
                    .sectionAppear(index: 2)
                }
                .padding(.top, Spacing.lg)

                // Description
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("About", systemImage: "info.circle.fill")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        Text(peptide.description)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineSpacing(4)
                    }
                }
                .sectionAppear(index: 3)

                // Mechanism of Action
                if !peptide.mechanism.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Mechanism of Action", systemImage: "gearshape.2.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            Text(peptide.mechanism)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineSpacing(4)
                        }
                    }
                    .sectionAppear(index: 4)
                }

                // Benefits
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("Benefits", systemImage: "star.fill")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        BenefitTagFlow(
                            benefits: peptide.benefits,
                            color: peptide.category.color
                        )
                    }
                }
                .sectionAppear(index: 5)

                // Dosage Info
                DosageInfoSection(peptide: peptide)
                    .sectionAppear(index: 6)

                // Side Effects
                if !peptide.sideEffects.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Side Effects", systemImage: "exclamationmark.triangle.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(Color.orange)

                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(peptide.sideEffects, id: \.self) { effect in
                                    HStack(alignment: .top, spacing: Spacing.sm) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 5))
                                            .foregroundStyle(Color.orange.opacity(0.6))
                                            .padding(.top, 7)

                                        Text(effect)
                                            .font(AppFont.body)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .sectionAppear(index: 7)
                }

                // Contraindications
                if !peptide.contraindications.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Contraindications", systemImage: "hand.raised.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(Color.red.opacity(0.9))

                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(peptide.contraindications, id: \.self) { item in
                                    HStack(alignment: .top, spacing: Spacing.sm) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.red.opacity(0.6))
                                            .padding(.top, 3)

                                        Text(item)
                                            .font(AppFont.body)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .sectionAppear(index: 8)
                }

                // Common Stacks
                if !peptide.commonStacks.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Commonly Stacked With", systemImage: "square.stack.3d.up.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            BenefitTagFlow(
                                benefits: peptide.commonStacks,
                                color: AppColor.accentPrimary
                            )
                        }
                    }
                    .sectionAppear(index: 9)
                }

                // Regulatory Status
                if !peptide.regulatoryStatus.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Regulatory Status", systemImage: "building.columns.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            Text(peptide.regulatoryStatus)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineSpacing(4)
                        }
                    }
                    .sectionAppear(index: 10)
                }

                // Research Links
                if !peptide.researchLinks.isEmpty {
                    ResearchLinksSection(links: peptide.researchLinks)
                        .sectionAppear(index: 11)
                }

                // Molecular Data
                if let mol = peptide.molecular, !mol.formula.isEmpty {
                    MolecularInfoSection(molecular: mol)
                        .sectionAppear(index: 12)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .glassSheet(isPresented: $showingBuilder) {
            ProtocolBuilderView(preselectedPeptide: peptide)
        }
    }
}

// MARK: - Molecular Info Section

struct MolecularInfoSection: View {
    let molecular: MolecularData

    private var showsFormula: Bool {
        !molecular.formula.isEmpty && !molecular.formula.hasPrefix("Complex peptide")
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Label("Molecular Data", systemImage: "atom")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                VStack(spacing: Spacing.md) {
                    if showsFormula {
                        MolecularRow(label: "Formula", value: molecular.formula, icon: "textformat.abc")
                    }

                    if !molecular.weight.isEmpty {
                        if showsFormula {
                            Divider().foregroundStyle(AppColor.glassBorder)
                        }
                        MolecularRow(label: "Molecular Weight", value: molecular.weight, icon: "scalemass.fill")
                    }

                    if let cid = molecular.cid, cid > 0, !molecular.pubchemURL.isEmpty {
                        if showsFormula || !molecular.weight.isEmpty {
                            Divider().foregroundStyle(AppColor.glassBorder)
                        }
                        if let url = URL(string: molecular.pubchemURL) {
                            Link(destination: url) {
                                HStack {
                                    HStack(spacing: Spacing.sm) {
                                        Image(systemName: "link")
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppColor.accentPrimary)
                                            .frame(width: 20)

                                        Text("PubChem")
                                            .font(AppFont.subheadline)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }

                                    Spacer()

                                    Text("CID: \(cid)")
                                        .font(AppFont.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(AppColor.accentPrimary)

                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AppColor.accentPrimary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MolecularRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 20)

                Text(label)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Text(value)
                .font(AppFont.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

#Preview {
    NavigationStack {
        PeptideDetailView(peptide: MockPeptides.bpc157)
    }
    .environment(DataStore())
    .preferredColorScheme(.dark)
}
