import SwiftUI

struct LockScreenView: View {
    let onUnlock: () -> Void

    @State private var biometricService = BiometricService.shared
    @State private var isAuthenticating = false

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColor.accentPrimary)

            VStack(spacing: Spacing.sm) {
                Text("PeptideX is Locked")
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
                        .font(.system(size: 20))
                    Text("Unlock with \(biometricService.biometryName)")
                        .font(AppFont.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(AppColor.accentPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
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
            onUnlock()
        }
    }
}

#Preview {
    LockScreenView(onUnlock: {})
        .preferredColorScheme(.dark)
}
