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
    @State private var urlError: String?
    @State private var hasSubmitted: Bool = false

    @FocusState private var handleFocused: Bool

    /// Hard caps applied at the INPUT boundary via .onChange so a
    /// paste flood can't balloon the bound @State or render a
    /// 50 KB string in the multi-line field (audit security #2).
    /// Same numbers as the submit-time guard for consistency.
    private let handleCap = 64
    private let urlCap = 512
    private let notesCap = 500

    private var canSubmit: Bool {
        !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && urlError == nil
        && !hasSubmitted
    }

    /// Validates the channel URL. Empty input is valid (the field is
    /// optional). Non-empty input must parse as an http:// or
    /// https:// URL — `javascript:`, `data:`, `file:`, custom-scheme
    /// URIs are rejected (audit security #1).
    private func validateURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else {
            return "Use a full https:// link."
        }
        return nil
    }

    /// Scrubs control characters from a free-form text field so a
    /// `\u{0000}` paste doesn't ride to the backend row (audit
    /// security #2). Newlines in `notes` are intentionally
    /// preserved — the field is multi-line.
    private func scrub(_ raw: String, allowingNewlines: Bool) -> String {
        var disallowed = CharacterSet.controlCharacters
        if allowingNewlines { disallowed.subtract(.newlines) }
        return String(raw.unicodeScalars.filter { !disallowed.contains($0) })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        header
                        formCard
                        prefillDisclosure
                        perks
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.lg)
                }
            }
            .navigationTitle("Join the creator program")
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
            // Input-time clamps so a paste flood can't balloon the
            // bound state, and live URL validation so the user sees
            // the error inline instead of on submit (audit M).
            .onChange(of: handle) { _, new in
                if new.count > handleCap { handle = String(new.prefix(handleCap)) }
            }
            .onChange(of: channelURL) { _, new in
                if new.count > urlCap { channelURL = String(new.prefix(urlCap)) }
                urlError = validateURL(channelURL)
            }
            .onChange(of: notes) { _, new in
                if new.count > notesCap { notes = String(new.prefix(notesCap)) }
            }
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

    /// Small disclosure row above Submit so the user explicitly sees
    /// that the form will piggy-back their onboarding name + email.
    /// Originally the prefill happened silently inside submit() and
    /// the security audit flagged it as a hidden-PII issue.
    private var prefillDisclosure: some View {
        let nameLine = userName.isEmpty ? nil : "Name: \(userName)"
        let emailLine = userEmail.map { "Email: \($0)" }
        return Group {
            if nameLine != nil || emailLine != nil {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("We'll include:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColor.textSecondary)
                        if let nameLine {
                            Text(nameLine)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        if let emailLine {
                            Text(emailLine)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.4))
                )
            }
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
                    .accessibilityLabel("Handle or name")
            }

            field(label: "Main channel") {
                Picker("Main channel", selection: $channel) {
                    ForEach(AffiliateApplication.Channel.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(AppColor.accentLight)
                .accessibilityLabel("Main channel")
            }

            field(label: "Audience size") {
                Picker("Audience size", selection: $audienceBand) {
                    ForEach(AffiliateApplication.AudienceBand.allCases) { band in
                        Text(band.displayName).tag(band)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(AppColor.accentLight)
                .accessibilityLabel("Audience size")
            }

            field(label: "Channel URL (optional)") {
                TextField("https://…", text: $channelURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityLabel("Channel URL")
                if let urlError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                        Text(urlError)
                            .font(AppFont.caption)
                    }
                    .foregroundStyle(AppColor.destructive)
                    .transition(.opacity)
                }
            }

            field(label: "Anything else? (optional)") {
                TextField("Audience demographics, post cadence, etc.", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityLabel("Additional notes")
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
            Divider()
                .background(AppColor.glassBorder)
                .padding(.vertical, 2)
            Text("We'll review and reply within 5 business days.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
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
        // Idempotency guard — Submit disables on first tap so a
        // double-tap can't fire two funnel events or two writes
        // (audit security #1.5). canSubmit checks `!hasSubmitted`.
        guard !hasSubmitted else { return }

        // Final boundary scrub: trim whitespace, scrub control
        // characters (newlines preserved on notes only), reject if
        // the URL still doesn't validate (defensive — onChange
        // should have already caught this).
        let cleanHandle = scrub(handle, allowingNewlines: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHandle.isEmpty else { return }
        let cleanURL = scrub(channelURL, allowingNewlines: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateURL(cleanURL) == nil else {
            urlError = "Use a full https:// link."
            return
        }
        let cleanNotes = scrub(notes, allowingNewlines: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        hasSubmitted = true
        let application = AffiliateApplication(
            handle: String(cleanHandle.prefix(handleCap)),
            channel: channel,
            audienceBand: audienceBand,
            channelURL: cleanURL.isEmpty ? nil : String(cleanURL.prefix(urlCap)),
            notes: cleanNotes.isEmpty ? nil : String(cleanNotes.prefix(notesCap)),
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
