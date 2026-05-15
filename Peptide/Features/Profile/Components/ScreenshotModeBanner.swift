import SwiftUI

/// Floating "you're in screenshot mode" reminder that pins to the
/// bottom of every tab while `ScreenshotMode.isEnabled` is true.
/// Tap to exit immediately — no scroll-to-Profile, no menu drill.
///
/// Deliberately positioned via `safeAreaInset(.bottom)` so it
/// rides above the tab bar without overlapping content. Hidden
/// from screenshots themselves by the host's
/// `accessibilityHidden(true)` and the fact that screenshot
/// captures usually happen from inside a single tab — but if the
/// user does want to include the banner in a capture for
/// debugging, it's fully visible.
struct ScreenshotModeBanner: View {
    @Environment(DataStore.self) private var dataStore
    @State private var screenshotMode = ScreenshotMode.shared

    private var accent: Color {
        Color(red: 0.55, green: 0.50, blue: 0.92)
    }

    var body: some View {
        if screenshotMode.isEnabled && screenshotMode.isBannerVisible {
            HStack(spacing: Spacing.sm) {
                Button {
                    if dataStore.profile.hapticFeedbackEnabled {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    screenshotMode.deactivate(in: dataStore)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.25))
                                .frame(width: 26, height: 26)
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(accent)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Screenshot mode")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(AppColor.textPrimary)
                            Text("Tap to exit · your real data is safe")
                                .font(.system(size: 11))
                                .foregroundStyle(AppColor.textSecondary)
                        }

                        Spacer(minLength: 0)

                        Text("Exit")
                            .font(.system(size: 12, weight: .heavy))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(.white)
                            .background {
                                Capsule().fill(accent)
                            }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.97))

                // Close button — hides the banner for this session
                // so the user can capture clean screenshots without
                // the reminder in the frame. Banner reappears on
                // the next launch (as long as demo mode is still
                // on) so the safety net is never permanently lost.
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        screenshotMode.isBannerVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 28, height: 28)
                        .background {
                            Circle()
                                .fill(AppColor.surfaceSecondary.opacity(0.8))
                                .overlay {
                                    Circle().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide screenshot mode reminder")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(accent.opacity(0.4), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.sm)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
