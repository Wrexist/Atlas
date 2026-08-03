import SwiftUI

/// Top-of-screen "Sync Complete" pill that auto-dismisses after a
/// short delay. Mirrors Bevel's checkmark pill — quiet
/// reassurance that data is fresh, especially after the user has
/// pulled to refresh or a HealthKit observer fired.
///
/// Drives off a binding so the caller decides when to show the
/// toast (e.g. after HealthKit returns a new snapshot, or after
/// CloudKit completes a sync). The toast manages its own dismiss
/// timer so callers don't have to schedule one.
struct SyncToast: View {
    @Binding var isShowing: Bool
    var message: LocalizedStringKey = "Sync Complete"
    var autoDismissAfter: Duration = .milliseconds(2_400)

    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isShowing {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.scaled(13, weight: .bold))
                        .foregroundStyle(AppColor.success)
                    Text(message)
                        .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 8)
                .glassControl(
                    .capsule,
                    tint: AppColor.success.opacity(0.10),
                    border: AppColor.success.opacity(0.35),
                    interactive: false
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear { scheduleDismiss() }
                .onDisappear { dismissTask?.cancel() }
                .accessibilityElement()
                .accessibilityLabel(message)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isShowing)
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: autoDismissAfter)
            guard !Task.isCancelled else { return }
            isShowing = false
        }
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var showing = true
        var body: some View {
            ZStack(alignment: .top) {
                AppColor.background.ignoresSafeArea()
                SyncToast(isShowing: $showing)
                    .padding(.top, 60)
                Button("Show toast") { showing = true }
                    .padding(.top, 200)
            }
            .preferredColorScheme(.dark)
        }
    }
    return PreviewHost()
}
