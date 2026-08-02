import SwiftUI

/// Profile-tab entry point for the stack-wide cycle card share. Hides
/// itself when the user has no active protocols — there's nothing to
/// summarise yet, and surfacing the CTA would just open an empty card.
struct CycleCardShareSection: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showShareSheet = false

    var body: some View {
        if dataStore.activeProtocols.isEmpty {
            EmptyView()
        } else {
            content
                .sheet(isPresented: $showShareSheet) {
                    ShareCardSheet(subject: .fullStack)
                        .environment(dataStore)
                        .liquidGlassPresentation()
                }
        }
    }

    private var content: some View {
        Button {
            showShareSheet = true
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.onAccent)
                    .frame(width: 40, height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppColor.accentPrimary, AppColor.accentLight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Share my cycle card")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("A 1080×1920 Stories-ready snapshot of your stack and stats.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }
}
