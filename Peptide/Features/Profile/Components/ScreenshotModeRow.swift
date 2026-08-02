import SwiftUI

/// Profile → Settings row that toggles App Store screenshot mode.
/// When on, the app shows a polished demo state (a believable
/// "successful long-running user") so the user can capture the
/// premium screenshots App Store Connect needs. Real protocols /
/// labs / meals on disk are untouched — the demo state lives
/// entirely in memory while the toggle is on.
///
/// Visual treatment intentionally non-default: indigo accent +
/// "DEMO" badge so the row never reads like a feature the user
/// would normally turn on. The descriptive subtitle spells out
/// the trade-off (real data hidden until toggle off) in plain
/// language so a user who lands here accidentally doesn't lose
/// confidence in their data.
struct ScreenshotModeRow: View {
    @Environment(DataStore.self) private var dataStore
    @State private var screenshotMode = ScreenshotMode.shared
    @State private var showConfirmation = false

    private var accent: Color {
        AppColor.recap
    }

    var body: some View {
        Button {
            if screenshotMode.isEnabled {
                // Turning off is a low-stakes action — just swap
                // back to real data with no confirmation.
                Haptics.selection()
                screenshotMode.deactivate(in: dataStore)
            } else {
                // Turning on overrides the visible state — confirm
                // so a curious tap doesn't surprise the user.
                showConfirmation = true
            }
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "camera.viewfinder")
                        .font(AppFont.scaled(16, weight: .heavy))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text("Screenshot mode")
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("DEMO")
                            .font(AppFont.scaled(8, weight: .heavy))
                            .tracking(0.5)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .foregroundStyle(AppColor.onAccent)
                            .background {
                                Capsule().fill(accent)
                            }
                    }
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.sm)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { screenshotMode.isEnabled },
                        set: { newValue in
                            if newValue {
                                showConfirmation = true
                            } else {
                                screenshotMode.deactivate(in: dataStore)
                            }
                        }
                    )
                )
                .labelsHidden()
                .tint(accent)
            }
            .padding(Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(accent.opacity(0.30), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .confirmationDialog(
            "Show demo data?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Show demo data") {
                Haptics.success()
                screenshotMode.activate(in: dataStore)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Replaces every tab with polished demo data so you can capture App Store screenshots. Your real protocols, labs, and meals stay safe on disk — toggle off any time to bring them back.")
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: LocalizedStringKey {
        if screenshotMode.isEnabled {
            return "On — every tab shows demo data. Toggle off to restore your real protocols."
        }
        return "Replace every tab with polished demo data for App Store screenshots. Your real data stays safe."
    }
}
