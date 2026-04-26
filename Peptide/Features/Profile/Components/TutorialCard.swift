import SwiftUI

struct TutorialCard: View {
    @State private var showTutorial = false

    var body: some View {
        Button {
            showTutorial = true
        } label: {
            GlassCard {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColor.accentLight)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(AppColor.glassTint)
                                .overlay {
                                    Circle().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                                }
                        }
                        .liquidGlass(.circle, tint: AppColor.accentPrimary.opacity(0.35), interactive: false)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Guide på svenska")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Steg-för-steg genomgång av appen")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showTutorial) {
            TutorialView()
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        TutorialCard()
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
