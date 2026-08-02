import SwiftUI

/// Slot 8 of the App Store screenshot deck: a single-glance privacy
/// summary that turns Atlas's "no analytics, no backend" posture into
/// a marketing-ready surface. Reachable from Profile → About →
/// "Privacy at a glance."
///
/// The claims here must stay in lockstep with `PrivacyInfo.xcprivacy`
/// and the App Privacy questionnaire. If anything below changes, update
/// both at the same time.
struct PrivacySummaryView: View {
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
                                Divider().foregroundStyle(AppColor.glassBorder)
                            }
                        }
                    }
                }
                .sectionAppear(index: 1)

                manifestChip
                    .sectionAppear(index: 2)
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
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.accentLight, AppColor.accentPrimary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.top, Spacing.md)

            Text("Your data doesn't leave your phone")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Zero analytics SDKs. Zero advertising. Verified by privacy manifest.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
        .frame(maxWidth: .infinity)
    }

    private var manifestChip: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(AppColor.accentPrimary)
            Text("Privacy Nutrition Label: No data collected")
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
            title: "No analytics. No trackers.",
            detail: "Atlas does not embed Firebase, Mixpanel, or any third-party analytics or advertising SDK."
        ),
        .init(
            icon: "network.slash",
            title: "No backend. No remote push.",
            detail: "There's no Atlas server. Your protocols, doses, and notes never leave your device."
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
            icon: "square.and.arrow.up",
            title: "Export everything. Anytime.",
            detail: "Export your full history as CSV, JSON, or PDF and walk away with no lock-in."
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
        let title: String
        let detail: String
    }
}

#Preview {
    NavigationStack {
        PrivacySummaryView()
    }
    .preferredColorScheme(.dark)
}
