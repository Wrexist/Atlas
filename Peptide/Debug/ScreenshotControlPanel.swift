import SwiftUI

/// Hidden control surface for App Store screenshot capture. Reachable
/// in DEBUG and TestFlight builds (per `ScreenshotTools.isAvailable`)
/// by tapping the Version row in Profile → About 7 times. Unreachable
/// in App Store Release builds — the trigger renders as plain text.
///
/// Operations:
/// - **Seed all** — wipes the data store and replaces with the curated
///   3-protocol / 35-day-history state.
/// - **Wipe** — drops everything back to a clean install.
/// - **Toggle screenshot mode** — flips Pro on, hides debug chrome.
/// - **Reset achievements** — re-runs the achievement check from current
///   data, useful after a manual edit.
struct ScreenshotControlPanel: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var screenshotMode = ScreenshotMode.shared
    @State private var lastAction: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    statusCard
                    actionsCard
                    if let lastAction {
                        Text(lastAction)
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    Text("Reachable in DEBUG and TestFlight only. App Store Release hides the trigger. See docs/SCREENSHOT_SEED_DATA_AND_FIXES.md.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.md)
                }
                .padding(Spacing.screenPadding)
            }
            .background(AppColor.background)
            .navigationTitle("Screenshot Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statusCard: some View {
        GlassCard(tinted: screenshotMode.isActive) {
            HStack(spacing: Spacing.md) {
                Image(systemName: screenshotMode.isActive ? "camera.fill" : "camera")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(screenshotMode.isActive ? "Screenshot mode ON" : "Screenshot mode OFF")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(screenshotMode.isActive
                         ? "Pro is force-unlocked. Debug chrome is hidden."
                         : "Toggle on before capturing screenshots.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private var actionsCard: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                actionButton(
                    title: "Seed all (3 protocols + 35-day history)",
                    icon: "wand.and.stars",
                    role: .primary
                ) {
                    ScreenshotSeeder.seedAll(into: dataStore)
                    lastAction = "Seeded \(dataStore.protocols.count) protocols, \(dataStore.entries.count) entries."
                }

                actionButton(
                    title: screenshotMode.isActive ? "Turn screenshot mode OFF" : "Turn screenshot mode ON",
                    icon: screenshotMode.isActive ? "camera.fill" : "camera",
                    role: .secondary
                ) {
                    screenshotMode.toggle()
                    lastAction = "Screenshot mode \(screenshotMode.isActive ? "ON" : "OFF")."
                }

                actionButton(
                    title: "Re-run achievement check",
                    icon: "arrow.triangle.2.circlepath",
                    role: .secondary
                ) {
                    AchievementService.shared.checkAchievements(
                        totalDoses: dataStore.totalDoses,
                        currentStreak: dataStore.currentStreak,
                        bestStreak: dataStore.bestStreak,
                        protocolCount: dataStore.protocols.count,
                        daysLogged: dataStore.totalDaysLogged
                    )
                    lastAction = "Achievements rechecked: \(AchievementService.shared.unlockedCount) of \(AchievementService.shared.totalCount) unlocked."
                }

                actionButton(
                    title: "Wipe everything",
                    icon: "trash",
                    role: .destructive
                ) {
                    ScreenshotSeeder.wipe(dataStore)
                    lastAction = "Data wiped. Screenshot mode OFF."
                }
            }
        }
    }

    private enum ButtonRole {
        case primary, secondary, destructive
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        icon: String,
        role: ButtonRole,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24)
                Text(title)
                    .font(AppFont.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(foregroundColor(for: role))
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius)
                    .fill(backgroundColor(for: role))
            }
        }
        .buttonStyle(.plain)
    }

    private func foregroundColor(for role: ButtonRole) -> Color {
        switch role {
        case .primary: AppColor.background
        case .secondary: AppColor.textPrimary
        case .destructive: AppColor.destructive
        }
    }

    private func backgroundColor(for role: ButtonRole) -> Color {
        switch role {
        case .primary: AppColor.accentPrimary
        case .secondary: AppColor.surfaceElevated
        case .destructive: AppColor.destructive.opacity(0.12)
        }
    }
}

/// Tap counter that opens `ScreenshotControlPanel` after 7 successive
/// taps within a short window. Mirrors the iOS Settings → About "tap
/// version 7 times to enable developer mode" pattern.
struct ScreenshotControlPanelTapCounter: ViewModifier {
    @State private var tapCount = 0
    @State private var lastTap = Date.distantPast
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                let now = Date()
                if now.timeIntervalSince(lastTap) > 1.5 {
                    tapCount = 1
                } else {
                    tapCount += 1
                }
                lastTap = now
                if tapCount >= 7 {
                    tapCount = 0
                    isPresented = true
                }
            }
            .sheet(isPresented: $isPresented) {
                ScreenshotControlPanel()
            }
    }
}

extension View {
    /// Wraps a view in a 7-tap counter that opens the screenshot control
    /// panel. The counter is only attached when
    /// `ScreenshotTools.isAvailable` (DEBUG or TestFlight) — in App Store
    /// Release builds the modifier is a passthrough.
    @ViewBuilder
    func screenshotControlPanelTrigger() -> some View {
        if ScreenshotTools.isAvailable {
            modifier(ScreenshotControlPanelTapCounter())
        } else {
            self
        }
    }
}
