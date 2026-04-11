import SwiftUI

struct SplashScreenView: View {
    @State private var iconScale: CGFloat = 0.3
    @State private var iconOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 20
    @State private var subtitleOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var glowScale: CGFloat = 0.5

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    AppColor.accentPrimary.opacity(0.15),
                    AppColor.accentPrimary.opacity(0.05),
                    Color.clear,
                ],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            .scaleEffect(glowScale)
            .opacity(glowOpacity)

            VStack(spacing: Spacing.xxl) {
                Spacer()

                ZStack {
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [
                                    AppColor.accentDark,
                                    AppColor.accentPrimary,
                                    AppColor.accentLight,
                                    AppColor.accentDark,
                                ],
                                center: .center
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    ZStack {
                        Circle()
                            .fill(AppColor.accentPrimary.opacity(0.2))
                            .frame(width: 88, height: 88)
                            .overlay {
                                Circle()
                                    .strokeBorder(AppColor.glassBorderActive, lineWidth: 1)
                            }

                        Image(systemName: "atom")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppColor.accentLight, AppColor.accentPrimary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
                }

                VStack(spacing: Spacing.sm) {
                    Text("PeptideX")
                        .font(AppFont.largeTitle)
                        .foregroundStyle(AppColor.textPrimary)

                    Text("PEPTIDE THERAPY TRACKER")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .tracking(3)
                }
                .opacity(titleOpacity)
                .offset(y: titleOffset)

                Spacer()

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "syringe.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColor.accentPrimary)
                    Text("Track \u{2022} Optimize \u{2022} Thrive")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
                .opacity(subtitleOpacity)
                .padding(.bottom, Spacing.xxxxl)
            }
        }
        .onAppear {
            animateEntrance()
        }
    }

    private func animateEntrance() {
        withAnimation(AppAnimation.springSmooth) {
            glowOpacity = 1.0
            glowScale = 1.0
        }

        withAnimation(AppAnimation.springBouncy.delay(0.1)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }

        withAnimation(AppAnimation.springGentle.delay(0.3)) {
            ringScale = 1.0
            ringOpacity = 1.0
        }

        withAnimation(AppAnimation.springSmooth.delay(0.5)) {
            titleOpacity = 1.0
            titleOffset = 0
        }

        withAnimation(AppAnimation.fadeInSlow.delay(0.8)) {
            subtitleOpacity = 1.0
        }
    }
}

#Preview {
    SplashScreenView()
        .preferredColorScheme(.dark)
}
