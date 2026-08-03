import SwiftUI

struct LockScreenView: View {
    let onUnlock: () -> Void

    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var biometricService = BiometricService.shared
    @State private var isAuthenticating = false
    @State private var shakeOffset: CGFloat = 0
    @State private var iconBounce = 0

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColor.accentPrimary)
                .symbolEffect(.bounce, value: iconBounce)
                .offset(x: shakeOffset)

            VStack(spacing: Spacing.sm) {
                Text("Atlas is Locked")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)

                Text("Authenticate to access your data")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Button {
                Task { await unlock() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: biometricService.biometryIcon)
                        .font(AppFont.scaled(20))
                    Text("Unlock with \(biometricService.biometryName)")
                        .font(AppFont.headline)
                }
                .foregroundStyle(AppColor.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(AppColor.accentFill)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.controlCornerRadius))
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.97))
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
        withAnimation(.spring(response: 0.12, dampingFraction: 0.45)) { shakeOffset = 8 }
        try? await Task.sleep(for: .milliseconds(80))
        withAnimation(.spring(response: 0.12, dampingFraction: 0.45)) { shakeOffset = -8 }
        try? await Task.sleep(for: .milliseconds(80))
        withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) { shakeOffset = 0 }
    }
}

#Preview {
    LockScreenView(onUnlock: {})
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
