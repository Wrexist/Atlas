import SwiftUI

struct GlassTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var icon: String = "magnifyingglass"

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(AppFont.scaled(15, weight: .medium))
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
                        .font(AppFont.scaled(14))
                        .foregroundStyle(AppColor.textTertiary)
                        .frame(width: Spacing.minimumHitTarget,
                               height: Spacing.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear text")
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .glassSurfaceCapsule()
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
