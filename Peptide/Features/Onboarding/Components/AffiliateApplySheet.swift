import SwiftUI

/// "Apply to be an Atlas affiliate" form. Surfaced from the
/// onboarding creator step's secondary CTA so creators can express
/// interest in joining the program at the moment they're already
/// thinking about creator codes. The form is intentionally short
/// (handle + channel + audience band + optional URL + optional
/// notes) — a long form here would kill the conversion.
///
/// Submission persists to `profile.affiliateApplication`. A future
/// backend drain replays the row 1:1 to the application-intake
/// endpoint; until then it's local-only.
struct AffiliateApplySheet: View {
    /// Pre-filled from the onboarding profile so the user doesn't
    /// re-type what we already have.
    let userName: String
    let userEmail: String?
    let onSubmit: (AffiliateApplication) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var handle: String = ""
    @State private var channel: AffiliateApplication.Channel = .instagram
    @State private var audienceBand: AffiliateApplication.AudienceBand = .k1to10
    @State private var channelURL: String = ""
    @State private var notes: String = ""

    @FocusState private var handleFocused: Bool

    private var canSubmit: Bool {
        !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        header
                        formCard
                        perks
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.lg)
                }
            }
            .navigationTitle("Become an affiliate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit", action: submit)
                        .disabled(!canSubmit)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { handleFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 72, height: 72)
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            Text("Earn for every Pro signup")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text("Approved creators get a personal code, a revenue share, and a creator-only Atlas dashboard.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
    }

    // MARK: - Form

    private var formCard: some View {
        VStack(spacing: Spacing.md) {
            field(label: "Handle / name") {
                TextField("@yourhandle", text: $handle)
                    .focused($handleFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            field(label: "Main channel") {
                Picker("", selection: $channel) {
                    ForEach(AffiliateApplication.Channel.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColor.accentLight)
            }

            field(label: "Audience size") {
                Picker("", selection: $audienceBand) {
                    ForEach(AffiliateApplication.AudienceBand.allCases) { band in
                        Text(band.displayName).tag(band)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColor.accentLight)
            }

            field(label: "Channel URL (optional)") {
                TextField("https://…", text: $channelURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }

            field(label: "Anything else? (optional)") {
                TextField("Audience demographics, post cadence, etc.", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1)
                .foregroundStyle(AppColor.textTertiary)
            content()
                .font(AppFont.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Perks

    private var perks: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            perkRow(icon: "percent",            text: "Personal discount code you can share")
            perkRow(icon: "creditcard.fill",    text: "Revenue share on every Pro signup you drive")
            perkRow(icon: "chart.line.uptrend.xyaxis", text: "Creator dashboard with installs + conversions")
            perkRow(icon: "envelope.fill",      text: "Direct line to the Atlas team")
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(AppColor.accentPrimary.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func perkRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 22)
            Text(text)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Submit

    private func submit() {
        let trimmedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHandle.isEmpty else { return }
        let trimmedURL = channelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let application = AffiliateApplication(
            handle: String(trimmedHandle.prefix(64)),
            channel: channel,
            audienceBand: audienceBand,
            channelURL: trimmedURL.isEmpty ? nil : String(trimmedURL.prefix(512)),
            notes: trimmedNotes.isEmpty ? nil : String(trimmedNotes.prefix(500)),
            submittedAt: Date(),
            name: userName.isEmpty ? nil : userName,
            email: userEmail
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSubmit(application)
        dismiss()
    }
}

#Preview {
    AffiliateApplySheet(
        userName: "Marcus",
        userEmail: "marcus@example.com",
        onSubmit: { _ in }
    )
}
