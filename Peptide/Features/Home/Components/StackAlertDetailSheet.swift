import SwiftUI

struct StackAlertDetailSheet: View {
    let warning: StackRecommendationEngine.Warning
    let peptideDatabase: [Peptide]
    let hapticEnabled: Bool
    let onPrimaryAction: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var severityColor: Color {
        switch warning.severity {
        case .danger: return AppColor.destructive
        case .caution: return Color.orange
        case .info: return AppColor.accentPrimary
        }
    }

    private var severityLabel: String {
        switch warning.severity {
        case .danger: return "High Priority"
        case .caution: return "Worth Reviewing"
        case .info: return "For Your Awareness"
        }
    }

    private var primaryActionLabel: String {
        let title = warning.title.lowercased()
        if title.contains("cycle") || title.contains("desensitization") {
            return "Schedule Off Period"
        }
        if title.contains("timing") {
            return "Adjust Schedule"
        }
        if title.contains("injection burden") {
            return "Group Injections"
        }
        switch warning.severity {
        case .danger: return "Review Stack Now"
        case .caution: return "Adjust Stack"
        case .info: return "Open Protocols"
        }
    }

    private var primaryActionIcon: String {
        let title = warning.title.lowercased()
        if title.contains("cycle") || title.contains("desensitization") {
            return "calendar.badge.clock"
        }
        if title.contains("timing") {
            return "clock.arrow.circlepath"
        }
        if title.contains("injection burden") {
            return "syringe"
        }
        return "slider.horizontal.3"
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 30, height: 30)
                            .background {
                                Circle()
                                    .fill(AppColor.surfaceSecondary.opacity(0.7))
                                    .overlay {
                                        Circle()
                                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                    }
                            }
                            .liquidGlass(.circle)
                    }
                }
            }
            .navigationTitle("Alert Details")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
        .presentationCornerRadius(Spacing.cardCornerRadius + 8)
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
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(severityColor)
            }
            .shadow(color: severityColor.opacity(0.35), radius: 18, x: 0, y: 0)

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
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(severityColor)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(severityColor.opacity(0.12))
                .overlay {
                    Capsule()
                        .strokeBorder(severityColor.opacity(0.25), lineWidth: 0.5)
                }
        }
        .liquidGlass(.capsule)
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
            .buttonStyle(ChipPressStyle(hapticEnabled: hapticEnabled))
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
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(severityColor.opacity(0.7))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            Capsule()
                .fill(severityColor.opacity(0.14))
                .overlay {
                    Capsule()
                        .strokeBorder(severityColor.opacity(0.28), lineWidth: 0.5)
                }
        }
        .liquidGlass(.capsule)
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)

                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(AppColor.textSecondary)
            }

            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius + 4, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius + 4, style: .continuous)
                        .fill(AppColor.cardOverlay)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius + 4, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius + 4, style: .continuous))
        .liquidGlass(.rect(cornerRadius: Spacing.smallCornerRadius + 4))
    }

    private var actionFooter: some View {
        VStack(spacing: Spacing.sm) {
            GlassButton(
                title: primaryActionLabel,
                icon: primaryActionIcon,
                style: primaryButtonStyle,
                isFullWidth: true
            ) {
                if hapticEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                dismiss()
                onPrimaryAction()
            }

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(AppFont.subheadline)
                    .fontWeight(.medium)
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

private struct ChipPressStyle: ButtonStyle {
    var hapticEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(AppAnimation.springSnappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && hapticEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
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
        hapticEnabled: true,
        onPrimaryAction: {}
    )
    .preferredColorScheme(.dark)
}
