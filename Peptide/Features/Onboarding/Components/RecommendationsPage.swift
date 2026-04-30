import SwiftUI

/// Onboarding page that shows the cold-start peptide recommendations derived
/// from the user's selected goals and (optional) body metrics. The user picks
/// which peptides go into their starter stack — at least one is required to
/// build the protocol; "Skip for now" is always available.
struct RecommendationsPage: View {
    let suggestions: [OnboardingRecommendationEngine.Suggestion]
    @Binding var selectedIds: Set<UUID>
    let metricsAvailable: Bool

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Your recommended stack")
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
            }
        }
    }

    private var subtitle: String {
        if suggestions.isEmpty {
            return "We couldn't match your goals to a peptide. You can build a custom protocol from the full library after onboarding."
        }
        if metricsAvailable {
            return "Doses scaled to your weight where the literature supports it. Tap to add or remove."
        }
        return "Doses use published research ranges. Tap to add or remove."
    }

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("No matches yet", systemImage: "lightbulb")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Browse the full peptide library after onboarding and build a protocol manually.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                        Text(suggestion.peptide.category.displayName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(suggestion.peptide.category.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule().fill(suggestion.peptide.category.color.opacity(0.15))
                            }
                    }

                    HStack(spacing: Spacing.xs) {
                        Text(suggestion.suggestedDose)
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.accentLight)
                        if suggestion.isPersonalized {
                            personalizedBadge
                        }
                    }

                    Text(suggestion.peptide.frequency)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .lineLimit(1)

                    Text(suggestion.rationale)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
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
        .accessibilityLabel("\(suggestion.peptide.abbreviation), \(suggestion.suggestedDose), \(suggestion.peptide.frequency)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var personalizedBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "person.fill.checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("YOUR DOSE")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(AppColor.accentPrimary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background {
            Capsule().fill(AppColor.accentPrimary.opacity(0.15))
        }
    }
}
