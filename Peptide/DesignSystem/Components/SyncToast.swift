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
///
/// An optional `action` adds one trailing button — "Undo" after a
/// one-tap log — which runs and dismisses the toast.
struct SyncToast: View {
    struct Action {
        let label: LocalizedStringResource
        let perform: @MainActor () -> Void
    }

    @Binding var isShowing: Bool
    var message: LocalizedStringResource = "Sync Complete"
    var autoDismissAfter: Duration = .milliseconds(2_400)
    var action: Action?

    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isShowing {
                HStack(spacing: Spacing.sm) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFont.scaled(13, weight: .bold))
                            .foregroundStyle(AppColor.success)
                        Text(message)
                            .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(message))
                    .accessibilityAddTraits(.isStaticText)
                    if let action {
                        actionButton(action)
                    }
                }
                .padding(.horizontal, Spacing.md)
                // The action button's 44pt hit area sets the height itself.
                .padding(.vertical, action == nil ? Spacing.sm : 0)
                .glassControl(
                    .capsule,
                    tint: AppColor.success.opacity(0.10),
                    border: AppColor.success.opacity(0.35),
                    interactive: false
                )
                .appShadow(AppShadow.toast)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    // Gone before VoiceOver focus could reach it, so say it.
                    AccessibilityNotification.Announcement(String(localized: message)).post()
                    scheduleDismiss()
                }
                .onDisappear { dismissTask?.cancel() }
                .accessibilityElement(children: .contain)
            }
        }
        .appAnimation(AppAnimation.toast, value: isShowing)
    }

    private func actionButton(_ action: Action) -> some View {
        Button {
            dismissTask?.cancel()
            action.perform()
            isShowing = false
        } label: {
            Label {
                Text(action.label)
            } icon: {
                Image(systemName: "arrow.uturn.backward")
            }
            .labelStyle(.titleAndIcon)
            .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
            .foregroundStyle(AppColor.textPrimary)
            .minimumHitArea()
        }
        .buttonStyle(.plain)
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
