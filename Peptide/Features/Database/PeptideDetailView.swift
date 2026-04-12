import SwiftUI

struct PeptideDetailView: View {
    let peptide: Peptide
    @Environment(\.dismiss) private var dismiss
    @State private var showingBuilder = false
    @AppStorage("experienceLevel") private var experienceLevel = "beginner"

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
                .sectionAppear(index: 4)

                // Dosage Info
                DosageInfoSection(peptide: peptide)
                    .sectionAppear(index: 5)

                // Research Links (hidden for beginners)
                if !peptide.researchLinks.isEmpty && experienceLevel != "beginner" {
                    ResearchLinksSection(links: peptide.researchLinks)
                        .sectionAppear(index: 6)
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

#Preview {
    NavigationStack {
        PeptideDetailView(peptide: MockPeptides.bpc157)
    }
    .environment(DataStore())
    .preferredColorScheme(.dark)
}
