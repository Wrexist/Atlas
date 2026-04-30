import SwiftUI

struct GlassTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var icon: String = "magnifyingglass"

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)

            TextField(placeholder, text: $text)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .tint(AppColor.accentPrimary)

            if !text.isEmpty {
                Button {
                    withAnimation(AppAnimation.springSnappy) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background {
            Capsule()
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    Capsule()
                        .fill(AppColor.cardOverlay)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .liquidGlass(.capsule)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            GlassTextField(placeholder: "Search peptides...", text: .constant(""))
            GlassTextField(placeholder: "Search peptides...", text: .constant("BPC"))
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
