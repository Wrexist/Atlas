import SwiftUI

struct PeptideDetailView: View {
    @Environment(DataStore.self) private var dataStore
    let peptide: Peptide
    @State private var showingPicker = false
    @State private var showingBuilder = false
    @State private var showingPaywall = false
    @AppStorage("experienceLevel") private var experienceLevel = "beginner"

    private enum Section: Hashable {
        case hero, yourStacks, about, mechanism, benefits, dosage, sideEffects,
             contraindications, stacks, regulatory, research, molecular
    }

    private var memberProtocols: [PeptideProtocol] {
        dataStore.protocolsContaining(peptideId: peptide.id)
    }

    private var visibleSections: [Section] {
        var ids: [Section] = [.hero]
        if !memberProtocols.isEmpty { ids.append(.yourStacks) }
        ids.append(.about)
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

                        GlassButton(
                            title: memberProtocols.isEmpty ? "Add to Stack" : "Add to Another Stack",
                            icon: "plus",
                            style: .primary
                        ) {
                            showingPicker = true
                        }
                    }
                }
                .sectionAppear(index: staggerIndex(.hero))

                if !memberProtocols.isEmpty {
                    yourStacksSection
                        .sectionAppear(index: staggerIndex(.yourStacks))
                }

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
        .navigationDestination(for: PeptideProtocol.self) { proto in
            ProtocolDetailView(protocol_: proto)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: showingPicker) { _, new in new }
        .glassSheet(isPresented: $showingPicker) {
            AddToStackSheet(peptide: peptide) {
                if StoreService.shared.requiresPro(activeProtocolCount: dataStore.activeProtocols.count) {
                    showingPaywall = true
                } else {
                    showingBuilder = true
                }
            }
        }
        .glassSheet(isPresented: $showingBuilder) {
            ProtocolBuilderView(preselectedPeptide: peptide)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    private var yourStacksSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundStyle(AppColor.accentLight)
                        .accessibilityHidden(true)
                    Text("In Your Stacks")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("\(memberProtocols.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.accentLight)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .background { Capsule().fill(AppColor.accentLight.opacity(0.18)) }
                }

                VStack(spacing: Spacing.sm) {
                    ForEach(memberProtocols) { proto in
                        NavigationLink(value: proto) {
                            stackChip(proto)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stackChip(_ proto: PeptideProtocol) -> some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(statusColor(proto.status).opacity(0.25))
                .frame(width: 8, height: 8)
                .overlay { Circle().strokeBorder(statusColor(proto.status), lineWidth: 1) }

            VStack(alignment: .leading, spacing: 2) {
                Text(proto.name)
                    .font(AppFont.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)

                Text(proto.schedule.daysDescription)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated.opacity(0.8))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .liquidGlass(.rect(cornerRadius: Spacing.smallCornerRadius))
    }

    private func statusColor(_ status: ProtocolStatus) -> Color {
        switch status {
        case .active: AppColor.accentLight
        case .paused: AppColor.warning
        case .completed: AppColor.textTertiary
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
