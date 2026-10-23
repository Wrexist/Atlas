import SwiftUI

struct StackAlertDetailSheet: View {
    let warning: StackRecommendationEngine.Warning
    let peptideDatabase: [Peptide]
    let onPrimaryAction: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var severityColor: Color {
        switch warning.severity {
        case .danger: return AppColor.destructive
        case .caution: return AppColor.warning
        case .info: return AppColor.accentPrimary
        }
    }

    private var severityLabel: String {
        switch warning.severity {
        case .danger: return "High priority"
        case .caution: return "Worth reviewing"
        case .info: return "For your awareness"
        }
    }

    private var primaryActionLabel: LocalizedStringKey {
        switch warning.kind {
        case .cycleOverrun, .desensitization: return "Schedule off period"
        case .timingConflict: return "Adjust schedule"
        case .injectionBurden: return "Group injections"
        case .general:
            switch warning.severity {
            case .danger: return "Review Protocol now"
            case .caution: return "Adjust Protocol"
            case .info: return "Open Protocols"
            }
        }
    }

    private var primaryActionIcon: String {
        switch warning.kind {
        case .cycleOverrun, .desensitization: return "calendar.badge.clock"
        case .timingConflict: return "clock.arrow.circlepath"
        case .injectionBurden: return "syringe"
        case .general: return "slider.horizontal.3"
        }
    }

    private var primaryButtonStyle: GlassButtonStyle {
        warning.severity == .danger ? .destructive : .primary
    }

    private func resolvedPeptide(for abbreviation: String) -> Peptide? {
        peptideDatabase.first { $0.abbreviation == abbreviation }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    heroHeader
                    severityBadge
                    detailSection
                    suggestionSection
                    affectedPeptidesSection
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(sheetBackground)
            .safeAreaInset(edge: .bottom) {
                actionFooter
            }
            .navigationDestination(for: Peptide.self) { peptide in
                PeptideDetailView(peptide: peptide)
            }
            .navigationDestination(for: PeptideProtocol.self) { proto in
                ProtocolDetailView(protocol_: proto)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 30, height: 30)
                            .glassControl(.circle)
                            .frame(width: Spacing.minimumHitTarget,
                                   height: Spacing.minimumHitTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationTitle("Alert details")
            .navigationBarTitleDisplayMode(.inline)
        }
        .liquidGlassPresentation(detents: [.medium, .large])
    }

    // MARK: - Sections

    private var heroHeader: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(severityColor.opacity(0.18))
                    .frame(width: 76, height: 76)
                    .overlay {
                        Circle()
                            .strokeBorder(severityColor.opacity(0.35), lineWidth: 0.8)
                    }
                    .liquidGlass(.circle)

                Image(systemName: warning.icon)
                    .font(AppFont.scaled(30, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(severityColor)
            }
            .appShadow(AppShadow.glassSubtle)

            Text(warning.title)
                .font(AppFont.title2)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.sm)
    }

    private var severityBadge: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(severityColor)
                .frame(width: 6, height: 6)

            Text(severityLabel.uppercased())
                .font(AppFont.scaled(11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(severityColor)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .glassControl(
            .capsule,
            tint: severityColor.opacity(0.12),
            border: severityColor.opacity(0.25)
        )
    }

    private var detailSection: some View {
        sectionCard(iconName: "info.circle.fill", title: "What's happening", tint: AppColor.textSecondary) {
            Text(warning.detail)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var suggestionSection: some View {
        sectionCard(iconName: "lightbulb.fill", title: "Recommended action", tint: AppColor.accentLight) {
            Text(warning.suggestion)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var affectedPeptidesSection: some View {
        if !warning.peptides.isEmpty {
            sectionCard(iconName: "pills.fill", title: "Affected peptides", tint: severityColor) {
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(warning.peptides, id: \.self) { abbreviation in
                        peptideChip(abbreviation: abbreviation)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func peptideChip(abbreviation: String) -> some View {
        if let peptide = resolvedPeptide(for: abbreviation) {
            NavigationLink(value: peptide) {
                peptideChipLabel(abbreviation, navigable: true)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.94))
        } else {
            peptideChipLabel(abbreviation, navigable: false)
        }
    }

    private func peptideChipLabel(_ abbreviation: String, navigable: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(abbreviation)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(severityColor)

            if navigable {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(8, weight: .bold))
                    .foregroundStyle(severityColor.opacity(0.7))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .glassControl(
            .capsule,
            tint: severityColor.opacity(0.14),
            border: severityColor.opacity(0.28)
        )
    }

    @ViewBuilder
    private func sectionCard<Inner: View>(
        iconName: String,
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Inner
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: iconName)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(tint)

                Text(title.uppercased())
                    .font(AppFont.scaled(11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(AppColor.textSecondary)
            }

            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius + 4)
    }

    private var actionFooter: some View {
        VStack(spacing: Spacing.sm) {
            GlassButton(
                title: primaryActionLabel,
                icon: primaryActionIcon,
                style: primaryButtonStyle,
                isFullWidth: true
            ) {
                Haptics.success()
                dismiss()
                // Let this sheet finish dismissing first — a modal chained
                // in the same tick can be dropped.
                Task { @MainActor in
                    try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
                    onPrimaryAction()
                }
            }

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.md)
        .background {
            LinearGradient(
                colors: [Color.clear, AppColor.background.opacity(0.85), AppColor.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var sheetBackground: some View {
        ZStack {
            AppColor.background.opacity(0.6)
            LinearGradient(
                colors: [
                    severityColor.opacity(0.12),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    StackAlertDetailSheet(
        warning: .init(
            severity: .danger,
            title: "Potential interaction",
            detail: "TB-500 and TB-4 may have contraindications when combined.",
            suggestion: "Review both peptides' safety profiles and consult a professional before combining.",
            peptides: ["TB-500", "TB-4"],
            icon: "xmark.octagon.fill"
        ),
        peptideDatabase: [],
        onPrimaryAction: {}
    )
    .preferredColorScheme(.dark)
}
