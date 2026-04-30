import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Conversion-optimized 3-day free trial paywall surfaced at the end of
/// onboarding. Calls `StoreService.startMonthlyTrial()` which delegates to
/// `Product.purchase()` — Apple presents the intro offer sheet and, after the
/// 3-day free period, auto-renews the monthly subscription until cancellation.
struct TrialOfferView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var storeService = StoreService.shared
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var sparklePhase = 0.0
    @State private var ctaPulse = false
    @State private var didReveal = false

    private var monthlyPrice: String {
        storeService.monthlyProduct?.displayPrice ?? "$9.99"
    }

    private var trialDays: Int {
        guard let intro = storeService.monthlyProduct?.subscription?.introductoryOffer,
              intro.paymentMode == .freeTrial
        else { return 3 }
        return intro.period.value * intro.periodCount
    }

    var body: some View {
        ZStack {
            sparkleField

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    Spacer(minLength: Spacing.lg)

                    heroBadge
                    headline
                    benefitsCard
                    socialProof

                    Spacer(minLength: Spacing.md)
                }
                .padding(.horizontal, Spacing.screenPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.md)
            }
        }
        .task {
            await storeService.loadProducts()
            withAnimation(AppAnimation.springBouncy) { didReveal = true }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                sparklePhase = 1
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                ctaPulse = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Hero

    private var heroBadge: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .strokeBorder(AppColor.accentPrimary.opacity(0.35), lineWidth: 1)
                    .frame(width: 130, height: 130)
                    .scaleEffect(didReveal ? 1.0 + CGFloat(ring) * 0.18 : 0.6)
                    .opacity(didReveal ? 0.55 - Double(ring) * 0.15 : 0)
            }

            Image(systemName: "gift.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.accentLight, AppColor.accentPrimary],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .symbolEffect(.bounce, value: didReveal)
                .scaleEffect(didReveal ? 1 : 0.4)
                .opacity(didReveal ? 1 : 0)
        }
        .frame(height: 140)
    }

    private var headline: some View {
        VStack(spacing: Spacing.xs) {
            Text("YOUR WELCOME GIFT")
                .font(.system(size: 12, weight: .heavy))
                .tracking(2)
                .foregroundStyle(AppColor.accentLight)

            Text("\(trialDays) Days Free")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.textPrimary, AppColor.accentLight],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .contentTransition(.numericText())

            Text("Then \(monthlyPrice)/month — cancel anytime")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
        .multilineTextAlignment(.center)
        .opacity(didReveal ? 1 : 0)
        .offset(y: didReveal ? 0 : 12)
    }

    // MARK: - Benefits

    private var benefitsCard: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { index, benefit in
                    benefitRow(icon: benefit.0, title: benefit.1, index: index)
                }
            }
        }
        .opacity(didReveal ? 1 : 0)
        .offset(y: didReveal ? 0 : 16)
    }

    private let benefits: [(String, LocalizedStringKey)] = [
        ("infinity", "Unlimited protocols & stacks"),
        ("chart.xyaxis.line", "Full analytics + HealthKit correlation"),
        ("brain.head.profile.fill", "AI insights & smart recommendations"),
        ("icloud.fill", "Cloud sync across all your devices"),
    ]

    private func benefitRow(icon: String, title: LocalizedStringKey, index: Int) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .symbolEffect(.bounce, value: didReveal)
            }
            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.accentPrimary)
        }
        .opacity(didReveal ? 1 : 0)
        .offset(x: didReveal ? 0 : -16)
        .animation(
            AppAnimation.springSmooth.delay(0.15 + Double(index) * 0.06),
            value: didReveal
        )
    }

    private var socialProof: some View {
        HStack(spacing: Spacing.xs) {
            HStack(spacing: -8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(LinearGradient(
                            colors: [
                                AppColor.accentLight.opacity(0.9 - Double(i) * 0.1),
                                AppColor.accentPrimary.opacity(0.7),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(AppColor.background, lineWidth: 1.5))
                }
            }
            Text("Join thousands tracking smarter")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .opacity(didReveal ? 1 : 0)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            if let errorMessage {
                Text(errorMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.destructive)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Button(action: startTrial) {
                HStack(spacing: Spacing.sm) {
                    if isPurchasing {
                        ProgressView()
                            .tint(AppColor.textPrimary)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .bold))
                        Text("Start My \(trialDays)-Day Free Trial")
                            .font(AppFont.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md + 2)
                .padding(.horizontal, Spacing.xl)
                .foregroundStyle(AppColor.textPrimary)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentPrimary, AppColor.accentLight],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .overlay(Capsule().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5))
                }
                .scaleEffect(ctaPulse && !isPurchasing ? 1.02 : 1.0)
                .shadow(color: AppColor.accentPrimary.opacity(0.4), radius: ctaPulse ? 18 : 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
            .accessibilityLabel("Start \(trialDays)-day free trial")

            Button(action: declineTrial) {
                Text("Maybe later")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.vertical, Spacing.xs)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)

            Text("No charge for \(trialDays) days. Then \(monthlyPrice)/month, auto-renews until cancelled. Cancel anytime in Settings.")
                .font(.system(size: 10))
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)

            HStack(spacing: Spacing.md) {
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Text("·").foregroundStyle(AppColor.textTertiary)
                Link("Privacy Policy", destination: URL(string: "https://wrexist.github.io/Peptide-ai/privacy.html")!)
            }
            .font(.system(size: 10))
            .foregroundStyle(AppColor.accentLight)
        }
    }

    // MARK: - Sparkles

    private var sparkleField: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<14, id: \.self) { index in
                    sparkle(index: index, in: proxy.size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func sparkle(index: Int, in size: CGSize) -> some View {
        let seed = Double(index)
        let xRatio = (sin(seed * 1.7) + 1) / 2
        let yBase = (cos(seed * 2.3) + 1) / 2
        let drift = (sparklePhase + seed / 14).truncatingRemainder(dividingBy: 1)
        let y = (yBase + drift).truncatingRemainder(dividingBy: 1)
        let scale = 0.5 + (sin(seed) + 1) / 2 * 0.6
        return Image(systemName: "sparkle")
            .font(.system(size: 10))
            .foregroundStyle(AppColor.accentLight.opacity(0.35))
            .scaleEffect(scale)
            .position(x: size.width * xRatio, y: size.height * (1 - y))
    }

    // MARK: - Actions

    private func startTrial() {
        guard !isPurchasing else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        errorMessage = nil
        isPurchasing = true
        Task {
            do {
                let success = try await storeService.startMonthlyTrial()
                isPurchasing = false
                if success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onAccept()
                }
            } catch {
                isPurchasing = false
                withAnimation { errorMessage = "Couldn't start the trial. Please try again." }
            }
        }
    }

    private func declineTrial() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onDecline()
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        TrialOfferView(onAccept: {}, onDecline: {})
    }
    .preferredColorScheme(.dark)
}
