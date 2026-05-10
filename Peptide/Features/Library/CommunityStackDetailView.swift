import SwiftUI

struct CommunityStackDetailView: View {
    let stack: CommunityStack
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var didFork = false

    private var resolvedPeptides: [Peptide] {
        stack.peptideAbbreviations.compactMap { PeptideDatabase.peptide(matching: $0) }
    }

    private var previewProtocol: PeptideProtocol {
        CommunityStackService.shared.forkToProtocol(stack)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                hero
                authorChip
                cardPreview
                description
                peptidesList
                useStackButton
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationTitle(stack.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        GlassCard(tinted: stack.featured) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    if stack.featured {
                        Label("Featured", systemImage: "star.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColor.accentLight)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(AppColor.glassTint))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                        Text("\(stack.popularityScore) popularity")
                            .font(AppFont.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(AppColor.accentLight)
                    Spacer()
                }

                HStack(spacing: Spacing.xl) {
                    miniStat(value: "\(stack.peptideAbbreviations.count)", label: "Peptides")
                    miniStat(value: "\(stack.cycleLengthWeeks)w", label: "Cycle")
                    miniStat(value: "\(stack.scheduleTimesPerDay)x", label: "Per day")
                    miniStat(value: "\(stack.scheduleDaysOfWeek.count)d", label: "Per week")
                }
            }
        }
    }

    private var authorChip: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColor.accentLight)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stack.authorName)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(stack.authorHandle ?? stack.authorTitle ?? "Community contributor")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.cardOverlay)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                )
        )
    }

    private var cardPreview: some View {
        VStack(spacing: Spacing.sm) {
            CycleCardView(proto: previewProtocol, showsQR: false)
                .frame(
                    width: ShareCardRenderer.canvasSize.width,
                    height: ShareCardRenderer.canvasSize.height
                )
                .scaleEffect(0.32, anchor: .topLeading)
                .frame(
                    width: ShareCardRenderer.canvasSize.width * 0.32,
                    height: ShareCardRenderer.canvasSize.height * 0.32
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity)

            Text("Preview")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
    }

    private var description: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("About this stack", systemImage: "text.alignleft")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(stack.description)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(3)
                if !stack.goalTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(stack.goalTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColor.accentLight)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(AppColor.glassTint))
                        }
                    }
                }
            }
        }
    }

    private var peptidesList: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Peptides", systemImage: "flask.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                if resolvedPeptides.isEmpty {
                    Text("Some peptides in this stack aren't in your local database.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.warning)
                } else {
                    ForEach(Array(resolvedPeptides.enumerated()), id: \.element.id) { index, peptide in
                        peptideRow(peptide)
                        if index < resolvedPeptides.count - 1 {
                            Divider().foregroundStyle(AppColor.glassBorder)
                        }
                    }
                }

                let missing = stack.peptideAbbreviations.count - resolvedPeptides.count
                if missing > 0 {
                    Text("\(missing) peptide\(missing == 1 ? "" : "s") not in your library")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        }
    }

    private func peptideRow(_ peptide: Peptide) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: peptide.imageSystemName)
                .font(.system(size: 16))
                .foregroundStyle(peptide.category.color)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(peptide.category.color.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(peptide.abbreviation)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(peptide.dosageRange)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.xxs)
    }

    private var useStackButton: some View {
        GlassButton(
            title: didFork ? "Added to your protocols" : "Use this stack",
            icon: didFork ? "checkmark" : "plus.circle.fill",
            style: .primary,
            isFullWidth: true
        ) {
            useThisStack()
        }
        .disabled(didFork)
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.accentLight)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func useThisStack() {
        let proto = CommunityStackService.shared.forkToProtocol(stack)
        dataStore.addProtocol(proto)
        didFork = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        CommunityStackDetailView(stack: CommunityStack(
            id: UUID(),
            name: "Wolverine Stack",
            authorName: "Dr. M. Reyes",
            authorHandle: "@reyes.recovery",
            authorTitle: "MD",
            description: "Two complementary mechanisms for tissue repair.",
            goalTags: ["Recovery"],
            peptideAbbreviations: ["BPC-157", "TB-500"],
            cycleLengthWeeks: 8,
            scheduleDaysOfWeek: [1, 2, 3, 4, 5],
            scheduleTimesPerDay: 1,
            popularityScore: 96,
            featured: true
        ))
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
