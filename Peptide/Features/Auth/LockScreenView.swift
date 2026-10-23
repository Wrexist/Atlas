import SwiftUI

struct LockScreenView: View {
    let onUnlock: () -> Void
    /// The device has no passcode, so this lock can never be cleared.
    let onUnavailable: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var biometricService = BiometricService.shared
    @State private var isAuthenticating = false
    @State private var shakeOffset: CGFloat = 0
    @State private var iconBounce = 0
    @State private var failureMessage: String?

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(AppFont.scaled(48, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.accentPrimary)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : iconBounce)
                .accessibilityHidden(true)
                .offset(x: shakeOffset)

            VStack(spacing: Spacing.sm) {
                Text("Atlas is locked")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)

                Text("Authenticate to access your data")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                if let failureMessage {
                    Text(failureMessage)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.destructive)
                        .transition(.opacity)
                }
            }
            .multilineTextAlignment(.center)

            Spacer()

            PrimaryCTAButton(
                title: "Unlock with \(biometricService.biometryName)",
                icon: biometricService.biometryIcon
            ) {
                Task { await unlock() }
            }
            .disabled(isAuthenticating)
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, Spacing.xxxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
        .task { await unlock() }
    }

    private func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        switch await biometricService.authenticate() {
        case .success:
            Haptics.success()
            onUnlock()
        case .cancelled:
            // A deliberate cancel isn't an error; the Unlock button stays.
            break
        case .unavailable:
            onUnavailable()
        case .failed:
            showFailure()
            await shakeIcon()
        }
    }

    /// Said as well as shown, so a VoiceOver user or someone with haptics
    /// off learns the attempt failed (B292).
    private func showFailure() {
        let message = String(localized: "Couldn't verify it's you. Try again.")
        AppAnimation.with(AppAnimation.fadeIn) { failureMessage = message }
        AccessibilityNotification.Announcement(message).post()
        Haptics.error()
        iconBounce &+= 1
    }

    /// Three-step horizontal shake (8 → -8 → 0) over ~280 ms. Disabled under
    /// Reduce Motion — the haptic + icon bounce already convey the failure.
    private func shakeIcon() async {
        guard !reduceMotion else { return }
        AppAnimation.with(AppAnimation.shake) { shakeOffset = 8 }
        try? await Task.sleep(for: .milliseconds(80))
        AppAnimation.with(AppAnimation.shake) { shakeOffset = -8 }
        try? await Task.sleep(for: .milliseconds(80))
        AppAnimation.with(AppAnimation.shakeSettle) { shakeOffset = 0 }
    }
}

#Preview {
    LockScreenView(onUnlock: {}, onUnavailable: {})
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
