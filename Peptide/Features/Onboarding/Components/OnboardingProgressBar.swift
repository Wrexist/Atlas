import SwiftUI

struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return min(max(CGFloat(current + 1) / CGFloat(total), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColor.surfaceElevated)
                    .overlay {
                        Capsule()
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
                    .frame(height: 4)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accentPrimary, AppColor.accentLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * progress, 8), height: 4)
                    .shadow(color: AppColor.accentPrimary.opacity(0.6), radius: 6, x: 0, y: 0)
                    .animation(AppAnimation.springSmooth, value: current)
            }
        }
        .frame(height: 4)
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
