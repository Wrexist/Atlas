import SwiftUI

struct CommunityStackDetailView: View {
    let stack: CommunityStack
    /// Set when the protocol builder hosts this screen: the template then
    /// pre-fills the builder instead of being saved as a protocol of its own.
    let onUseTemplate: ((CommunityStack) -> Void)?
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var storeService = StoreService.shared
    @State private var didFork = false
    @State private var showingPaywall = false
    /// Resolved once, up front: filling these in a `.task` left the first
    /// frame claiming the stack's peptides were missing (warning copy,
    /// disabled CTA) until the lookup landed.
    @State private var resolvedPeptides: [Peptide]
    /// Built once so the share-card preview doesn't reconstruct the struct
    /// (and re-resolve every abbreviation) on every body evaluation.
    @State private var previewProtocol: PeptideProtocol

    init(stack: CommunityStack, onUseTemplate: ((CommunityStack) -> Void)? = nil) {
        self.stack = stack
        self.onUseTemplate = onUseTemplate
        let peptides = stack.peptideAbbreviations.compactMap { PeptideDatabase.peptide(matching: $0) }
        _resolvedPeptides = State(initialValue: peptides)
        _previewProtocol = State(initialValue: Self.makePreviewProtocol(for: stack, peptides: peptides))
    }

    private static func makePreviewProtocol(for stack: CommunityStack, peptides: [Peptide]) -> PeptideProtocol {
        let times = (1...max(1, stack.scheduleTimesPerDay)).map { _ in "8:00 AM" }
        return PeptideProtocol(
            id: UUID(),
            name: stack.name,
            peptides: peptides,
            schedule: ProtocolSchedule(
                daysOfWeek: stack.scheduleDaysOfWeek,
                timesPerDay: stack.scheduleTimesPerDay,
                preferredTimes: times
            ),
            cycleLengthWeeks: stack.cycleLengthWeeks,
            startDate: Date(),
            status: .active,
            notes: "",
            authorName: stack.authorName,
            authorHandle: stack.authorHandle,
            forkedFromStackId: stack.id,
            createdAt: Date()
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                hero
                cardPreview
                description
                peptidesList
                useStackButton
                Text("Research summary for education, not a recommendation or medical advice. Talk to a clinician before using any peptide.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationTitle(stack.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Name and author lead the screen (the inline bar title alone left the
    /// most important text at 17pt), with the stack's shape underneath.
    private var hero: some View {
        GlassCard(tinted: stack.featured) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if stack.featured {
                        Badge("Featured", icon: "star.fill")
                    }
                    Text(stack.name)
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    authorLine
                }

                HStack(spacing: Spacing.xl) {
                    miniStat(value: "\(stack.peptideAbbreviations.count)", label: "Peptides")
                    miniStat(value: "\(stack.cycleLengthWeeks)w", label: "Cycle")
                    miniStat(value: "\(stack.scheduleTimesPerDay)x", label: "Per day")
                    miniStat(value: "\(stack.scheduleDaysOfWeek.count)d", label: "Per week")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var authorLine: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "person.crop.circle.fill")
                .font(AppFont.scaled(20))
                .foregroundStyle(AppColor.accentLight)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(stack.authorName)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(stack.authorHandle ?? stack.authorTitle ?? "Atlas Editorial")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var cardPreview: some View {
        VStack(spacing: Spacing.sm) {
            CycleCardView(model: CycleCardModel.forProtocol(previewProtocol, in: dataStore))
                .frame(
                    width: ShareCardRenderer.canvasSize.width,
                    height: ShareCardRenderer.canvasSize.height
                )
                .scaleEffect(0.32, anchor: .topLeading)
                .frame(
                    width: ShareCardRenderer.canvasSize.width * 0.32,
                    height: ShareCardRenderer.canvasSize.height * 0.32
                )
                .clipShape(RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
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
                Label("About this protocol", systemImage: "text.alignleft")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(stack.description)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(3)
                if !stack.goalTags.isEmpty {
                    // Wraps rather than clipping once there are 3+ tags.
                    FlowLayout(spacing: Spacing.xs) {
                        ForEach(stack.goalTags, id: \.self) { tag in
                            Badge(LocalizedStringKey(tag))
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
                    Text("Some peptides in this protocol aren't in your local database.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.warning)
                } else {
                    ForEach(Array(resolvedPeptides.enumerated()), id: \.element.id) { index, peptide in
                        peptideRow(peptide)
                        if index < resolvedPeptides.count - 1 {
                            Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)
                        }
                    }
                }

                let missing = stack.peptideAbbreviations.count - resolvedPeptides.count
                if missing > 0 {
                    Text("^[\(missing) peptide](inflect: true) not in your library")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        }
    }

    private func peptideRow(_ peptide: Peptide) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: peptide.imageSystemName)
                .font(AppFont.scaled(16))
                .foregroundStyle(peptide.category.color)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
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
            title: didFork ? "Added to your protocols" : "Use this protocol",
            icon: didFork ? "checkmark" : "plus.circle.fill",
            style: .primary,
            isFullWidth: true
        ) {
            useThisStack()
        }
        // Disable when forked OR when nothing resolved locally (a
        // community stack that references peptides not in the user's
        // database would otherwise create an empty protocol — audit
        // Library P0.4).
        .disabled(didFork || resolvedPeptides.isEmpty)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: .communityStack)
                .liquidGlassPresentation()
        }
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
        guard !didFork else { return }
        guard !resolvedPeptides.isEmpty else { return }
        if let onUseTemplate {
            Haptics.selection()
            onUseTemplate(stack)
            return
        }
        // Honor the free-tier 3-active-protocol cap. The Pro gate on
        // the FAB in ProtocolListView is the documented path; this
        // route used to bypass it (audit Library P0.3).
        let activeCount = dataStore.activeProtocols.count
        if storeService.requiresPro(activeProtocolCount: activeCount) {
            showingPaywall = true
            return
        }
        let proto = CommunityStackService.shared.forkToProtocol(stack)
        dataStore.addProtocol(proto)
        Haptics.success()
        didFork = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        CommunityStackDetailView(stack: CommunityStack(
            id: UUID(),
            name: "Wolverine Stack",
            authorName: "Atlas Editorial",
            authorHandle: nil,
            authorTitle: "Research summary, not a recommendation",
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
