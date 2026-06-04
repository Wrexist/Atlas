import SwiftUI

/// One-line tile in the Profile "tools" cluster. Drills into the
/// full Labs surface. Sits next to the reconstitution calculator
/// — the two share the design intent of "instrument the user's
/// workflow with utility tools, not just review surfaces".
struct LabsEntryCard: View {
    let labCount: Int
    let panelCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.accentPrimary.opacity(0.45),
                                    AppColor.accentLight.opacity(0.25),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    Image(systemName: "testtube.2")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Lab work")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitleCopy)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the lab-work view to log or review biomarker values over time.")
    }

    private var subtitleCopy: LocalizedStringResource {
        if labCount == 0 {
            return LocalizedStringResource("Track testosterone, IGF-1, lipids…")
        }
        return LocalizedStringResource(
            "\(labCount) entries across \(panelCount) panels",
            comment: "Subtitle on the labs entry tile when the user has at least one entry."
        )
    }

    private var accessibilityLabel: String {
        if labCount == 0 {
            return String(localized: "Lab work — no entries yet")
        }
        return String(
            localized: "Lab work — \(labCount) entries across \(panelCount) panels",
            comment: "VoiceOver readout for the labs tile."
        )
    }
}
