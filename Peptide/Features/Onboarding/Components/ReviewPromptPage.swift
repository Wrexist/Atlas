import SwiftUI

private let reviewStarGold = Color(red: 0.961, green: 0.620, blue: 0.043) // #F59E0B

struct ReviewPromptPage: View {
    @State private var stagger = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("Join 10,000+ biohackers tracking smarter.")
                    .font(AppFont.largeTitle)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColor.textPrimary, AppColor.accentLight],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .multilineTextAlignment(.center)

                Text("This app was built for people serious about their protocols.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)
            }

            UsersPill()

            VStack(spacing: Spacing.md) {
                ForEach(Array(Self.testimonials.enumerated()), id: \.offset) { index, testimonial in
                    TestimonialCard(testimonial: testimonial)
                        .opacity(stagger ? 1 : 0)
                        .offset(y: stagger ? 0 : 16)
                        .animation(
                            AppAnimation.springSmooth.delay(0.15 + Double(index) * 0.10),
                            value: stagger
                        )
                }
            }
        }
        .onAppear { stagger = true }
    }

    fileprivate static let testimonials: [Testimonial] = [
        Testimonial(
            initials: "MT",
            name: "Marcus T.",
            tint: AppColor.accentPrimary,
            quote: "Finally a tracker built for actual peptide protocols. The reconstitution calculator alone saves me 10 minutes every cycle. Essential for anyone running a serious stack."
        ),
        Testimonial(
            initials: "AR",
            name: "Alex R.",
            tint: AppColor.accentLight,
            quote: "I've tried 4 apps. PeptideX is the only one that understands stacking. The half-life overlay is a game changer — I can finally see my active windows at a glance."
        ),
    ]

    fileprivate struct Testimonial {
        let initials: String
        let name: String
        let tint: Color
        let quote: String
    }
}

/// Compact "+10,000 users" capsule with three overlapping initial-avatars.
/// Sits below the subtitle as a quick at-a-glance social proof anchor
/// before the longer testimonial cards below.
private struct UsersPill: View {
    private let avatars: [(initials: String, tint: Color)] = [
        ("MT", Color(hex: 0xC4B5FD)),  // light purple
        ("AR", AppColor.accentLight),
        ("JK", AppColor.accentPrimary),
    ]

    var body: some View {
        HStack(spacing: Spacing.sm) {
            stack
            Text("+10,000 users")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background {
            Capsule()
                .fill(AppColor.surfaceSecondary.opacity(0.7))
                .overlay {
                    Capsule().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .liquidGlass(.capsule)
    }

    private var stack: some View {
        HStack(spacing: -10) {
            ForEach(Array(avatars.enumerated()), id: \.offset) { _, avatar in
                ZStack {
                    Circle()
                        .fill(avatar.tint.opacity(0.30))
                        .overlay {
                            Circle().strokeBorder(AppColor.background, lineWidth: 1.5)
                        }
                    Text(avatar.initials)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(avatar.tint)
                }
                .frame(width: 26, height: 26)
            }
        }
    }
}

private struct TestimonialCard: View {
    let testimonial: ReviewPromptPage.Testimonial

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            avatar

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(testimonial.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)

                HStack(spacing: 2) {
                    ForEach(0..<5) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(reviewStarGold)
                    }
                }

                Text(testimonial.quote)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
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
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(testimonial.tint)
        }
        .frame(width: 40, height: 40)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ScrollView {
            ReviewPromptPage()
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.xl)
        }
    }
    .preferredColorScheme(.dark)
}
