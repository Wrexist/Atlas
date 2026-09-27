import SwiftUI

/// Quiet entry into the AI research assistant from Today. The chat's only
/// other door is an icon in the Library toolbar, behind a modal most users
/// never open. Same shape as `ProtocolsDiscoverRow`: one labeled row, no
/// tutorial. The caller decides whether a tap opens the chat or the paywall.
struct ResearchAssistantRow: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            onTap()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "sparkles")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(AppColor.accentPrimary.opacity(0.15))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Research assistant")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Ask about a compound or a study and get answers with citations.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Research assistant. Ask about a compound or a study and get answers with citations.")
        .accessibilityHint("Opens the AI research assistant")
    }
}

#Preview {
    ResearchAssistantRow(onTap: {})
        .padding()
        .background(AppColor.background)
        .preferredColorScheme(.dark)
}
