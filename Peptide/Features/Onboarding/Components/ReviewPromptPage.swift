import SwiftUI

private let reviewStarGold = Color(red: 0.961, green: 0.620, blue: 0.043) // #F59E0B

struct ReviewPromptPage: View {
    @State private var stagger = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.md) {
                Text("Join 10,000+ biohackers tracking smarter")
                    .font(AppFont.largeTitle)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColor.textPrimary, AppColor.accentLight],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text("Built for people serious about their protocols.")
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
    private struct Avatar {
        let initials: String
        let tint: Color
    }

    private var avatars: [Avatar] {
        [
            Avatar(initials: "MT", tint: AppColor.accentPrimary),
            Avatar(initials: "AR", tint: AppColor.accentLight),
            Avatar(initials: "JK", tint: Color(hex: 0xC4B5FD)),
        ]
    }

    private let diameter: CGFloat = 28
    private let overlap: CGFloat = 10

    var body: some View {
        HStack(spacing: Spacing.sm) {
            stack
            Text("+10,000 users")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.leading, Spacing.sm)
        .padding(.trailing, Spacing.md)
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

    /// Avatars overlap by `overlap` pt. Each is an opaque tinted disc with
    /// a 2 pt ring matching the page background so the underlying disc
    /// reads as cleanly punched out from the one above — no bleed-through
    /// like the previous semi-transparent fill produced.
    private var stack: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(avatars.enumerated()), id: \.offset) { _, avatar in
                ZStack {
                    Circle().fill(AppColor.background)

                    Circle()
                        .fill(avatar.tint.opacity(0.85))
                        .padding(2)

                    Text(avatar.initials)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
                }
                .frame(width: diameter, height: diameter)
            }
        }
    }
}

private struct TestimonialCard: View {
    let testimonial: ReviewPromptPage.Testimonial

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
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
                }

                Spacer(minLength: 0)
            }

            Text(testimonial.quote)
                .font(.system(size: 14))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(Spacing.lg)
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

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(testimonial.tint.opacity(0.9))
            Text(testimonial.initials)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
        }
        .frame(width: 40, height: 40)
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        }
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
