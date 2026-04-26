import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One-time, one-shot welcome offer presented during onboarding. Shown only
/// when `StoreService.isEligibleForOnboardingTrial` is true. Activating starts
/// a local 3-day Pro trial; declining permanently dismisses the offer.
struct LiquidGlassOfferView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var shimmerPhase: CGFloat = -1
    @State private var orbScale: CGFloat = 0.92

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.xl) {
                    Spacer(minLength: Spacing.lg)

                    glassOrb
                        .padding(.bottom, Spacing.sm)

                    headline
                    offerCard
                    valueRows

                    Spacer(minLength: Spacing.lg)
                }
                .padding(.horizontal, Spacing.screenPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionStack
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.md)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                orbScale = 1.04
            }
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.4
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private var glassOrb: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppColor.accentPrimary.opacity(0.55),
                            AppColor.accentPrimary.opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
                .frame(width: 280, height: 280)
                .blur(radius: 30)

            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            AppColor.accentLight.opacity(0.7),
                            AppColor.accentPrimary.opacity(0.0),
                            AppColor.accentLight.opacity(0.7),
                        ],
                        center: .center
                    ),
                    lineWidth: 1.2
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(shimmerPhase * 180))

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColor.accentLight.opacity(0.35),
                            AppColor.accentPrimary.opacity(0.15),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 150, height: 150)
                .overlay {
                    Circle()
                        .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.6)
                }
                .liquidGlass(.circle, tint: AppColor.accentPrimary.opacity(0.4), interactive: false)
                .scaleEffect(orbScale)

            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.accentLight, AppColor.accentPrimary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: AppColor.accentPrimary.opacity(0.6), radius: 12, x: 0, y: 6)
        }
        .frame(height: 220)
    }

    private var headline: some View {
        VStack(spacing: Spacing.sm) {
            Text("ENGÅNGSERBJUDANDE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(AppColor.accentLight)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xxs)
                .background {
                    Capsule()
                        .fill(AppColor.glassTint)
                        .overlay {
                            Capsule().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                }
                .liquidGlass(.capsule, tint: AppColor.accentPrimary.opacity(0.35), interactive: false)

            Text("3 dagar gratis")
                .font(AppFont.largeTitle)
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.textPrimary, AppColor.accentLight],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .multilineTextAlignment(.center)

            Text("Lås upp PeptideX Pro direkt — utan kort, utan auto-förnyelse")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)
        }
    }

    private var offerCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColor.accentPrimary.opacity(0.22),
                            AppColor.surfaceSecondary.opacity(0.7),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    AppColor.accentLight.opacity(0.55),
                                    AppColor.glassBorder,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }

            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppColor.accentLight)
                        .shadow(color: AppColor.accentPrimary.opacity(0.5), radius: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PeptideX Pro")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Hela biblioteket. Inga gränser.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                }

                Divider().background(AppColor.glassBorder)

                HStack(spacing: Spacing.lg) {
                    counterPill(value: "3", label: "dagar")
                    counterPill(value: "0 kr", label: "att betala")
                    counterPill(value: "∞", label: "protokoll")
                }
            }
            .padding(Spacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .liquidGlass(.rect(cornerRadius: 28), tint: AppColor.accentPrimary.opacity(0.4), interactive: false)
        .overlay { shimmerOverlay }
    }

    private func counterPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.accentLight)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var shimmerOverlay: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [
                    .clear,
                    AppColor.accentLight.opacity(0.18),
                    .clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: proxy.size.width * 0.5)
            .offset(x: proxy.size.width * shimmerPhase)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var valueRows: some View {
        VStack(spacing: Spacing.sm) {
            valueRow(icon: "infinity", text: "Obegränsade protokoll och peptider")
            valueRow(icon: "brain.head.profile.fill", text: "AI-insikter och smart återhämtning")
            valueRow(icon: "chart.xyaxis.line", text: "Full analys, export och Apple Watch")
            valueRow(icon: "lock.shield.fill", text: "Avbryt när som helst — inget kort krävs")
        }
    }

    private func valueRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(AppColor.glassTint)
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                }

            Text(text)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    private var actionStack: some View {
        VStack(spacing: Spacing.sm) {
            GlassButton(
                title: "Aktivera 3 dagar gratis",
                icon: "sparkles",
                style: .primary,
                isFullWidth: true
            ) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onAccept()
            }

            GlassButton(title: "Inte nu", style: .ghost, isFullWidth: true) {
                onDecline()
            }

            Text("Erbjudandet visas bara en gång — det förnyas inte automatiskt.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.xs)
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        LiquidGlassOfferView(onAccept: {}, onDecline: {})
    }
    .preferredColorScheme(.dark)
}
