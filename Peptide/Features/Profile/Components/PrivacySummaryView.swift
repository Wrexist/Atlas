import SwiftUI

/// Slot 8 of the App Store screenshot deck: a single-glance privacy
/// summary that turns Atlas's "no ads, no tracking, no user-data backend" posture into
/// a marketing-ready surface. Reachable from Profile → About →
/// "Privacy at a glance."
///
/// The claims here must stay in lockstep with `PrivacyInfo.xcprivacy`
/// and the App Privacy questionnaire. If anything below changes, update
/// both at the same time.
struct PrivacySummaryView: View {
    @State private var aiConsentGranted = AIDataConsent.isGranted
    @AppStorage(OnboardingFunnelTracker.consentKey) private var shareOnboardingFunnel = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                header
                    .sectionAppear(index: 0)

                GlassCard {
                    VStack(spacing: Spacing.lg) {
                        ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                            PrivacyRow(row: row)
                            if index < Self.rows.count - 1 {
                                Divider().overlay(AppColor.glassBorder)
                            }
                        }
                    }
                }
                .sectionAppear(index: 1)

                aiSharingCard
                    .sectionAppear(index: 2)

                // Only rendered when the build carries a drain endpoint —
                // current builds don't, so the claims above hold.
                if OnboardingFunnelTracker.drainConfigured {
                    funnelConsentCard
                }

                manifestChip
                    .sectionAppear(index: 3)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.lg)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationTitle("Privacy at a glance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "lock.shield.fill")
                .font(AppFont.scaled(44, weight: .semibold, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.accentPrimary)
                .padding(.top, Spacing.md)
                .accessibilityHidden(true)

            Text("Your logs stay on your phone")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("No ads. No tracking. No data sold. Verified by privacy manifest.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
        .frame(maxWidth: .infinity)
    }

    private var aiSharingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                PrivacyRow(row: .init(
                    icon: "sparkles",
                    title: "AI features ask first.",
                    detail: "Research chat, meal photo and text logging, package scans, Fill with AI and barcode price estimates send what you submit to Claude, by Anthropic, through Atlas's server — only when you use them, and only after you allow it."
                ))
                if aiConsentGranted {
                    GlassButton(title: "Turn off AI data sharing", style: .secondary, isFullWidth: true) {
                        AIDataConsent.revoke()
                        Haptics.success()
                        aiConsentGranted = false
                    }
                    .transition(.opacity)
                } else {
                    Text("Off. Atlas asks before anything is sent.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textTertiary)
                        .transition(.opacity)
                }
            }
            .appAnimation(AppAnimation.springSmooth, value: aiConsentGranted)
        }
    }

    private var funnelConsentCard: some View {
        GlassCard {
            Toggle(isOn: $shareOnboardingFunnel) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Share onboarding diagnostics")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Off by default. When on, setup-flow step timings upload once under a random ID — never your name, email, or health data.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(AppColor.accentPrimary)
        }
    }

    private var manifestChip: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(AppColor.accentPrimary)
            Text("Privacy Nutrition Label: no tracking, nothing linked to you")
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            Capsule().fill(AppColor.glassTint)
        }
        .overlay {
            Capsule().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
        }
    }

    fileprivate static let rows: [PrivacyRow.Row] = [
        .init(
            icon: "shield.checkered",
            title: "No ads. No trackers.",
            detail: "Atlas embeds no advertising or cross-app tracking SDK, and never sells or shares your data."
        ),
        .init(
            icon: "network.slash",
            title: "No user-data backend.",
            detail: "Atlas runs no server that stores your logs. AI features you invoke send only what they need — a meal photo, weekly averages — to answer your request."
        ),
        .init(
            icon: "key.fill",
            title: "Sign in with Apple is optional.",
            detail: "If you sign in, only your Apple-issued identifier is stored — locally, in the iOS Keychain."
        ),
        .init(
            icon: "icloud.fill",
            title: "iCloud sync uses your private database.",
            detail: "When enabled, sync runs through your personal CloudKit container. We never see it."
        ),
        .init(
            icon: "lock.fill",
            title: "App lock is a privacy screen.",
            detail: "Face ID or Touch ID lock hides Atlas on launch. It doesn't add encryption beyond what iOS already gives your data."
        ),
        .init(
            icon: "square.and.arrow.up",
            title: "Your data is portable.",
            detail: "Atlas Pro exports your full history as CSV, JSON, or PDF, so you are never locked in."
        ),
    ]
}

private struct PrivacyRow: View {
    let row: Row

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Image(systemName: row.icon)
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(row.title)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(row.detail)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    struct Row {
        let icon: String
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
    }
}

#Preview {
    NavigationStack {
        PrivacySummaryView()
    }
    .preferredColorScheme(.dark)
}
