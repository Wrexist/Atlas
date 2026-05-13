import SwiftUI

/// Onboarding page that surfaces educational, goal-based peptide matches
/// drawn from the user's selected goals. The user picks which peptides go
/// into their starter stack — at least one is required to build the protocol;
/// "Skip for now" is always available.
///
/// IMPORTANT: This screen does NOT display dose values or compute any dose
/// recommendation. It is a goal-to-peptide educational matcher. Users open
/// each peptide's detail page (with research citations) before deciding
/// whether to track it, and any dose they end up logging is provided by
/// their own clinician.
struct RecommendationsPage: View {
    let suggestions: [OnboardingRecommendationEngine.Suggestion]
    @Binding var selectedIds: Set<UUID>

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Educational matches")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            if suggestions.isEmpty {
                emptyState
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(suggestions) { suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            isSelected: selectedIds.contains(suggestion.peptide.id)
                        ) {
                            toggle(suggestion.peptide.id)
                        }
                    }
                }
                .padding(.top, Spacing.sm)

                educationalNotice
                    .padding(.top, Spacing.sm)
            }
        }
    }

    private var subtitle: String {
        if suggestions.isEmpty {
            return "We couldn't match your goals to a peptide. You can browse the full educational library after onboarding."
        }
        return "Peptides matched to your goals for further reading. Tap to add or remove. Not a dose recommendation."
    }

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("No matches yet", systemImage: "lightbulb")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Browse the full peptide library after onboarding to read about each entry.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var educationalNotice: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "stethoscope")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .padding(.top, 2)

            Text("PeptideX does not recommend, prescribe, or calculate doses. Tap any match to read its educational detail page with research citations. Always consult a qualified clinician before starting any protocol.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    private func toggle(_ id: UUID) {
        withAnimation(AppAnimation.springSnappy) {
            if selectedIds.contains(id) {
                selectedIds.remove(id)
            } else {
                selectedIds.insert(id)
            }
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

private struct SuggestionRow: View {
    let suggestion: OnboardingRecommendationEngine.Suggestion
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: suggestion.peptide.imageSystemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(suggestion.peptide.category.color)
                    .frame(width: 38, height: 38)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(suggestion.peptide.category.color.opacity(0.18))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(suggestion.peptide.abbreviation)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(suggestion.peptide.category.localizedTitle)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(suggestion.peptide.category.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule().fill(suggestion.peptide.category.color.opacity(0.15))
                            }
                    }

                    Text(suggestion.peptide.name)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)

                    // Rationale was previously rendered in accentLight (cyan)
                    // at full opacity, which screamed louder than the
                    // peptide name. Mute it so the visual hierarchy reads
                    // name → rationale, not the other way around.
                    Text(suggestion.rationale)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(isSelected ? AppColor.accentPrimary.opacity(0.10) : AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? AppColor.accentPrimary.opacity(0.45) : AppColor.glassBorder,
                                lineWidth: isSelected ? 1.0 : 0.5
                            )
                    }
            }
            .liquidGlass(
                .rect(cornerRadius: Spacing.cardCornerRadius),
                tint: isSelected ? AppColor.accentPrimary.opacity(0.35) : nil,
                interactive: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(suggestion.peptide.abbreviation), \(suggestion.peptide.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
