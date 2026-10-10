import SwiftUI

/// A single sculpted object, with an arrival keyed to the selected page.
struct HeroIcon: View {
    let symbol: String
    var color: Color = AppColor.accentPrimary
    var size: CGFloat = 96
    var bounceTrigger: Int = 0
    var isActive: Bool = true

    var body: some View {
        MilestoneArtwork(
            symbol: symbol,
            tint: color,
            size: size,
            style: .symbol,
            trigger: bounceTrigger,
            isActive: isActive
        )
        .frame(width: size * 1.25, height: size * 1.25)
    }
}

/// The real brand asset gets the same brief light sweep as the milestone
/// family. Its stable silhouette remains immediately recognizable.
struct HeroLogo: View {
    var imageName: String = "AtlasLogo"
    var size: CGFloat = 140
    var bounceTrigger: Int = 0
    var isActive: Bool = true

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 1)
            }
            .appShadow(AppShadow.glassElevated)
            .milestoneMotion(trigger: bounceTrigger, isActive: isActive)
            .frame(width: size * 1.25, height: size * 1.25)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: Spacing.xxl) {
        HeroLogo()
        HeroIcon(symbol: "heart.fill", color: AppColor.metricHeartRate)
    }
    .padding(Spacing.xl)
    .background(AppColor.background)
}
