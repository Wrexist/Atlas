import SwiftUI

struct AboutSection: View {
    @State private var showDisclaimer = false
    @State private var showWhatsNewReplay = false

    /// Read the marketing version + build straight from the bundle so
    /// the About card never drifts from what TestFlight / the App
    /// Store actually shipped. These were hardcoded to "1.0.0" / "1",
    /// which would silently lie the moment the build number bumped.
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private static let termsURL = URL.staticHTTPS("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    private static let privacyURL = URL.staticHTTPS("https://wrexist.github.io/Atlas/privacy.html")
    private static let supportURL = URL.staticHTTPS("mailto:support@peptidesai.com")
    /// A user-tapped "Rate" opens the App Store review page directly:
    /// `requestReview` is rate-limited by iOS and can silently show nothing.
    private static let writeReviewURL = AppConstants.appStoreURL
        .appending(queryItems: [URLQueryItem(name: "action", value: "write-review")])

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("About", systemImage: "info.circle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                // Rows carry their own 44pt height; tighter spacing keeps
                // the card's density.
                VStack(spacing: Spacing.xs) {
                    AboutRow(title: "Version", value: "\(Self.appVersion) (\(Self.buildNumber))")
                    Divider().overlay(AppColor.glassBorder)
                    NavigationLink {
                        PrivacySummaryView()
                    } label: {
                        HStack {
                            Text("Privacy at a glance")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AppFont.scaled(11, weight: .semibold))
                                .foregroundStyle(AppColor.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .aboutRowHitTarget()
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(AppColor.glassBorder)
                    Button { showDisclaimer = true } label: {
                        HStack {
                            Text("Medical disclaimer")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AppFont.scaled(11, weight: .semibold))
                                .foregroundStyle(AppColor.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .aboutRowHitTarget()
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(AppColor.glassBorder)
                    AboutLinkRow(title: "Terms of Use", destination: Self.termsURL)
                    Divider().overlay(AppColor.glassBorder)
                    AboutLinkRow(title: "Privacy Policy", destination: Self.privacyURL)
                    Divider().overlay(AppColor.glassBorder)
                    AboutLinkRow(title: "Contact Support", destination: Self.supportURL)
                    Divider().overlay(AppColor.glassBorder)
                    AboutLinkRow(title: "Rate Atlas", destination: Self.writeReviewURL)
                    Divider().overlay(AppColor.glassBorder)
                    Button { showWhatsNewReplay = true } label: {
                        HStack {
                            Label("Replay What's New tour", systemImage: "sparkles")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.accentLight)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AppFont.scaled(11, weight: .semibold))
                                .foregroundStyle(AppColor.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .aboutRowHitTarget()
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Spacer()
                    VStack(spacing: Spacing.xs) {
                        MilestoneArtwork(size: 32, style: .emblem, isActive: false, playsOnArrival: false)
                            .accessibilityHidden(true)

                        Text("Atlas")
                            .font(AppFont.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                }
                .padding(.top, Spacing.sm)
            }
        }
        .sheet(isPresented: $showDisclaimer) {
            MedicalDisclaimerSheet()
                .liquidGlassPresentation()
        }
        .sheet(isPresented: $showWhatsNewReplay) {
            // Doesn't mark-as-seen since this is a manual replay
            // initiated by the user — leaving the version stamp
            // alone keeps the auto-fire behaviour predictable
            // (the tour fires on next launch only if the user
            // actually bumps to a newer version).
            WhatsNewTourSheet(
                pages: WhatsNewPage.current,
                onComplete: { showWhatsNewReplay = false }
            )
        }
    }
}

struct MedicalDisclaimerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Image(systemName: "stethoscope")
                        .font(AppFont.scaled(40, relativeTo: .largeTitle))
                        .foregroundStyle(AppColor.accentPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(PeptideDatabase.disclaimer)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Atlas is a tracking and educational tool. It is not a medical device, and it does not provide medical advice, diagnosis, or treatment.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.screenPadding)
            }
            .background(AppColor.background)
            .navigationTitle("Medical disclaimer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AboutLinkRow: View {
    let title: LocalizedStringKey
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack {
                Text(title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .aboutRowHitTarget()
        }
        .buttonStyle(.plain)
    }
}

private struct AboutRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
        }
        .frame(minHeight: Spacing.minimumHitTarget)
    }
}

private extension View {
    /// A full-width 44pt tap target: the bare text line was about 20pt
    /// and only the glyphs themselves were hittable.
    func aboutRowHitTarget() -> some View {
        frame(minHeight: Spacing.minimumHitTarget).contentShape(Rectangle())
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        AboutSection()
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
