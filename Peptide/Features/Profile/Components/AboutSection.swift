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

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("About", systemImage: "info.circle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                VStack(spacing: Spacing.md) {
                    AboutRow(title: "Version", value: Self.appVersion)
                    Divider().foregroundStyle(AppColor.glassBorder)
                    AboutRow(title: "Build", value: Self.buildNumber)
                    Divider().foregroundStyle(AppColor.glassBorder)
                    AboutRow(title: "Peptide Database", value: "\(PeptideDatabase.shared.count) peptides")
                    Divider().foregroundStyle(AppColor.glassBorder)
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
                        }
                    }
                    .buttonStyle(.plain)
                    Divider().foregroundStyle(AppColor.glassBorder)
                    Button { showDisclaimer = true } label: {
                        HStack {
                            Text("Medical Disclaimer")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AppFont.scaled(11, weight: .semibold))
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Divider().foregroundStyle(AppColor.glassBorder)
                    Button { showWhatsNewReplay = true } label: {
                        HStack {
                            Label("Replay What's New tour", systemImage: "sparkles")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.accentLight)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AppFont.scaled(11, weight: .semibold))
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Spacer()
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: "atom")
                            .font(AppFont.scaled(24))
                            .foregroundStyle(AppColor.accentPrimary)
                            .pulse()

                        Text("Atlas")
                            .font(AppFont.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppColor.accentPrimary, AppColor.accentLight],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
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
                pages: WhatsNewPage.v21,
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
                        .font(.system(size: 40))
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
            .navigationTitle("Medical Disclaimer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
