import SwiftUI

struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return min(max(CGFloat(current + 1) / CGFloat(total), 0), 1)
    }

    var body: some View {
        // The track + fill share a glass effect container so on iOS 26 the
        // moving fill morphs through the track instead of clipping over it
        // — same trick the system tab bar uses for its sliding pill.
        LiquidGlassContainer {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            Capsule().fill(AppColor.cardOverlay)
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                        .liquidGlass(.capsule)
                        .frame(height: 5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentPrimary, AppColor.accentLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .liquidGlass(
                            .capsule,
                            tint: AppColor.accentPrimary.opacity(0.35),
                            interactive: true
                        )
                        .frame(width: max(geo.size.width * progress, 12), height: 5)
                        .shadow(color: AppColor.accentPrimary.opacity(0.6), radius: 6, x: 0, y: 0)
                        .animation(.spring(response: 0.55, dampingFraction: 0.78), value: current)
                }
            }
            .frame(height: 5)
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        OnboardingProgressBar(current: 3, total: 8)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
