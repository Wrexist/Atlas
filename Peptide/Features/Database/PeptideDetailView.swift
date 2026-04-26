import SwiftUI

struct PeptideDetailView: View {
    let peptide: Peptide
    @State private var showingBuilder = false
    @AppStorage("experienceLevel") private var experienceLevel = "beginner"

    private enum Section: Hashable {
        case hero, about, mechanism, benefits, dosage, sideEffects,
             contraindications, stacks, regulatory, research, molecular
    }

    private var visibleSections: [Section] {
        var ids: [Section] = [.hero, .about]
        if !peptide.mechanism.isEmpty { ids.append(.mechanism) }
        ids.append(contentsOf: [.benefits, .dosage])
        if !peptide.sideEffects.isEmpty { ids.append(.sideEffects) }
        if !peptide.contraindications.isEmpty { ids.append(.contraindications) }
        if !peptide.commonStacks.isEmpty { ids.append(.stacks) }
        if !peptide.regulatoryStatus.isEmpty { ids.append(.regulatory) }
        if !peptide.researchLinks.isEmpty && experienceLevel != "beginner" { ids.append(.research) }
        if let mol = peptide.molecular, !mol.formula.isEmpty { ids.append(.molecular) }
        return ids
    }

    private func staggerIndex(_ section: Section) -> Int {
        visibleSections.firstIndex(of: section) ?? 0
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.lg) {
                // Hero Section
                GlassCard(tinted: true) {
                    VStack(spacing: Spacing.lg) {
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
                            .accessibilityHidden(true)

                            VStack(spacing: Spacing.sm) {
                                Text(peptide.abbreviation)
                                    .font(AppFont.largeTitle)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                Text(peptide.name)
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)

                                PeptideCategoryBadge(category: peptide.category)
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        }
                        .accessibilityElement(children: .combine)

                        GlassButton(title: "Add to Protocol", icon: "plus", style: .primary) {
                            showingBuilder = true
                        }
                    }
                }
                .sectionAppear(index: staggerIndex(.hero))

                // Description
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(peptide.category.color)
                                .accessibilityHidden(true)
                            Text("About")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                        }

                        ExpandableText(text: peptide.description, accentColor: peptide.category.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .sectionAppear(index: staggerIndex(.about))

                // Mechanism of Action
                if !peptide.mechanism.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "gearshape.2.fill")
                                    .foregroundStyle(peptide.category.color)
                                    .accessibilityHidden(true)
                                Text("Mechanism of Action")
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                            }

                            ExpandableText(text: peptide.mechanism, accentColor: peptide.category.color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sectionAppear(index: staggerIndex(.mechanism))
                }

                // Benefits
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(peptide.category.color)
                                .accessibilityHidden(true)
                            Text("Benefits")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                        }

                        BenefitTagFlow(
                            benefits: peptide.benefits,
                            color: peptide.category.color
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .sectionAppear(index: staggerIndex(.benefits))

                // Dosage Info
                DosageInfoSection(peptide: peptide)
                    .sectionAppear(index: staggerIndex(.dosage))

                // Side Effects
                if !peptide.sideEffects.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.orange)
                                    .accessibilityHidden(true)
                                Text("Side Effects")
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                            }

                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(peptide.sideEffects, id: \.self) { effect in
                                    HStack(alignment: .top, spacing: Spacing.sm) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(Color.orange.opacity(0.7))
                                            .shadow(color: Color.orange.opacity(0.3), radius: 3)
                                            .padding(.top, 7)

                                        Text(effect)
                                            .font(AppFont.body)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sectionAppear(index: staggerIndex(.sideEffects))
                }

                // Contraindications
                if !peptide.contraindications.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "hand.raised.fill")
                                    .foregroundStyle(Color.red.opacity(0.9))
                                    .accessibilityHidden(true)
                                Text("Contraindications")
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                            }

                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(peptide.contraindications, id: \.self) { item in
                                    HStack(alignment: .top, spacing: Spacing.sm) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.red.opacity(0.7))
                                            .shadow(color: Color.red.opacity(0.3), radius: 3)
                                            .padding(.top, 3)

                                        Text(item)
                                            .font(AppFont.body)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sectionAppear(index: staggerIndex(.contraindications))
                }

                // Common Stacks
                if !peptide.commonStacks.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .foregroundStyle(peptide.category.color)
                                    .accessibilityHidden(true)
                                Text("Commonly Stacked With")
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                            }

                            StackTagFlow(
                                stacks: peptide.commonStacks,
                                fallbackColor: AppColor.accentPrimary,
                                excludingPeptideID: peptide.id
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sectionAppear(index: staggerIndex(.stacks))
                }

                // Regulatory Status
                if !peptide.regulatoryStatus.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "building.columns.fill")
                                    .foregroundStyle(peptide.category.color)
                                    .accessibilityHidden(true)
                                Text("Regulatory Status")
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                            }

                            ExpandableText(text: peptide.regulatoryStatus, accentColor: peptide.category.color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sectionAppear(index: staggerIndex(.regulatory))
                }

                // Research Links (hidden for beginners)
                if !peptide.researchLinks.isEmpty && experienceLevel != "beginner" {
                    ResearchLinksSection(links: peptide.researchLinks, categoryColor: peptide.category.color)
                        .sectionAppear(index: staggerIndex(.research))
                }

                // Molecular Data
                if let mol = peptide.molecular, !mol.formula.isEmpty {
                    MolecularInfoSection(molecular: mol, categoryColor: peptide.category.color)
                        .sectionAppear(index: staggerIndex(.molecular))
                }

                disclaimerFooter
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .medium), trigger: showingBuilder) { _, new in new }
        .glassSheet(isPresented: $showingBuilder) {
            ProtocolBuilderView(preselectedPeptide: peptide)
        }
    }

    private var disclaimerFooter: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textTertiary)
            Text(PeptideDatabase.disclaimer)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Molecular Info Section

struct MolecularInfoSection: View {
    let molecular: MolecularData
    var categoryColor: Color = AppColor.accentPrimary

    private var showsFormula: Bool {
        !molecular.formula.isEmpty && !molecular.formula.hasPrefix("Complex peptide")
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "atom")
                        .foregroundStyle(categoryColor)
                        .accessibilityHidden(true)
                    Text("Molecular Data")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                }

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
            .frame(maxWidth: .infinity, alignment: .leading)
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
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
