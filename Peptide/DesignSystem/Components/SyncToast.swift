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
///
/// Re-showing a toast that is still on screen (a second one-tap log)
/// needs a new `presentationID`: that restarts the timer and repeats the
/// VoiceOver announcement, which a mounted view would otherwise skip.
struct SyncToast: View {
    struct Action {
        let label: LocalizedStringResource
        let perform: @MainActor () -> Void
    }

    @Binding var isShowing: Bool
    var message: LocalizedStringResource = "Sync Complete"
    var autoDismissAfter: Duration = .milliseconds(2_400)
    var action: Action?
    var presentationID: Int = 0

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    /// How long the toast stays up. An action is a time-limited control
    /// (WCAG 2.2.1): a VoiceOver or Switch Control user needs far longer to
    /// reach the button than a glance, so it stays six times as long.
    static func dismissDelay(
        base: Duration,
        hasAction: Bool,
        assistiveTechRunning: Bool
    ) -> Duration {
        hasAction && assistiveTechRunning ? base * 6 : base
    }

    var body: some View {
        Group {
            if isShowing {
                HStack(spacing: Spacing.sm) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFont.scaled(13, weight: .bold))
                            .foregroundStyle(AppColor.success)
                        Text(message)
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(message))
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityActions {
                        if let action {
                            Button(String(localized: action.label)) { run(action) }
                        }
                    }
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
                .task(id: presentationID) { await announceThenDismiss() }
                .accessibilityElement(children: .contain)
            }
        }
        .appAnimation(AppAnimation.toast, value: isShowing)
    }

    private func actionButton(_ action: Action) -> some View {
        Button {
            run(action)
        } label: {
            Label {
                Text(action.label)
            } icon: {
                Image(systemName: "arrow.uturn.backward")
            }
            .labelStyle(.titleAndIcon)
            .font(AppFont.scaled(13, weight: .semibold))
            .foregroundStyle(AppColor.textPrimary)
            .minimumHitArea()
        }
        .buttonStyle(.plain)
    }

    private func run(_ action: Action) {
        action.perform()
        isShowing = false
    }

    /// Keyed on `presentationID`, so a re-show restarts it; unmounting the
    /// toast cancels it.
    private func announceThenDismiss() async {
        // Gone before VoiceOver focus could reach it, so say it.
        AccessibilityNotification.Announcement(String(localized: message)).post()
        let delay = Self.dismissDelay(
            base: autoDismissAfter,
            hasAction: action != nil,
            assistiveTechRunning: voiceOverEnabled || switchControlEnabled
        )
        do {
            try await Task.sleep(for: delay)
        } catch { return }
        isShowing = false
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
