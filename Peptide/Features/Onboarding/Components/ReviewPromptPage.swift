import SwiftUI

private let reviewStarYellow = Color(hex: 0xFFC93C)

struct ReviewPromptHero: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(0..<5) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(reviewStarYellow)
                    .shadow(color: reviewStarYellow.opacity(0.55), radius: 8, x: 0, y: 0)
                    .scaleEffect(animate ? 1 : 0.6)
                    .opacity(animate ? 1 : 0)
                    .animation(
                        AppAnimation.springBouncy.delay(Double(index) * 0.07),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

struct ReviewPromptPage: View {
    @State private var stagger = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("Join 1,000+ peptide trackers")
                .font(AppFont.largeTitle)
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.textPrimary, AppColor.accentLight],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.sm)

            VStack(spacing: Spacing.md) {
                ForEach(Array(Self.testimonials.enumerated()), id: \.offset) { index, testimonial in
                    TestimonialCard(testimonial: testimonial)
                        .opacity(stagger ? 1 : 0)
                        .offset(y: stagger ? 0 : 16)
                        .animation(
                            AppAnimation.springSmooth.delay(0.12 + Double(index) * 0.10),
                            value: stagger
                        )
                }
            }
            .padding(.top, Spacing.xs)
        }
        .onAppear { stagger = true }
    }

    fileprivate static let testimonials: [Testimonial] = [
        Testimonial(
            initials: "AR",
            name: "Alex R.",
            tint: AppColor.accentPrimary,
            quote: "Finally a tracker built for real stacks. The reconstitution calc alone is worth it."
        ),
        Testimonial(
            initials: "JK",
            name: "Jamie K.",
            tint: OnboardingTint.fatLoss,
            quote: "GHK-Cu cycle tracking changed my whole protocol. Best peptide app out there."
        ),
    ]

    fileprivate struct Testimonial {
        let initials: String
        let name: String
        let tint: Color
        let quote: String
    }
}

private struct TestimonialCard: View {
    let testimonial: ReviewPromptPage.Testimonial

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: Spacing.md) {
                avatar

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(testimonial.name)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    HStack(spacing: 2) {
                        ForEach(0..<5) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(reviewStarYellow)
                        }
                    }

                    Text(testimonial.quote)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(testimonial.tint.opacity(0.22))
                .overlay {
                    Circle().strokeBorder(testimonial.tint.opacity(0.45), lineWidth: 0.5)
                }
            Text(testimonial.initials)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(testimonial.tint)
        }
        .frame(width: 44, height: 44)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.xl) {
            ReviewPromptHero()
            ReviewPromptPage()
                .padding(.horizontal, Spacing.screenPadding)
        }
    }
    .preferredColorScheme(.dark)
}
