import SwiftUI

struct LockScreenView: View {
    let onUnlock: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var biometricService = BiometricService.shared
    @State private var isAuthenticating = false
    @State private var shakeOffset: CGFloat = 0
    @State private var iconBounce = 0

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
            }

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

        if await biometricService.authenticate() {
            Haptics.success()
            onUnlock()
        } else {
            Haptics.error()
            iconBounce &+= 1
            await shakeIcon()
        }
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
    LockScreenView(onUnlock: {})
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
