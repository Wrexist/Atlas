import ActivityKit
import SwiftUI
import WidgetKit

/// Lock-screen + Dynamic Island live activity for an in-progress dose
/// window. Spec'd in roadmap v2.5.3 — countdown to dose time on the
/// lock screen, compact Dynamic Island chip while the user is in
/// another app, expanded view on long-press.
///
/// The activity is started by `DoseLiveActivityService` from the iOS
/// app whenever a dose enters its "active window" (default: from
/// 30 min before doseTime to 90 min after). Dismissal is also driven
/// from the app via `end(_:dismissalPolicy:)` once the dose is logged
/// or the window passes.
@available(iOS 16.1, *)
struct DoseWindowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoseWindowAttributes.self) { context in
            // Lock-screen / banner presentation
            DoseWindowLockView(
                attributes: context.attributes,
                state: context.state
            )
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — the four region builders appear when the
                // user long-presses the compact pill.
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "syringe.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(hex: context.attributes.tintHex))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerText(for: context.state))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.peptideAbbreviation)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.doseDisplay)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Text(context.state.completed ? "Logged" : "Tap to log")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            } compactLeading: {
                Image(systemName: "syringe.fill")
                    .foregroundStyle(Color(hex: context.attributes.tintHex))
            } compactTrailing: {
                Text(timerText(for: context.state))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "syringe.fill")
                    .foregroundStyle(Color(hex: context.attributes.tintHex))
            }
            .keylineTint(Color(hex: context.attributes.tintHex))
        }
    }

    /// Drives the countdown text. While the dose hasn't been completed
    /// yet, render an auto-tween countdown to `doseTime`; once the
    /// user logs it, switch to a static "✓" so the badge confirms
    /// without continuing to tick.
    private func timerText(for state: DoseWindowAttributes.ContentState) -> Text {
        if state.completed { return Text("✓") }
        let now = Date()
        if state.doseTime > now {
            return Text(state.doseTime, style: .timer)
        }
        // Already past the scheduled time — render the elapsed offset
        // so the live activity reads "5m late" rather than freezing
        // at 00:00.
        return Text(state.doseTime, style: .relative)
    }
}

// MARK: - Lock-screen view

@available(iOS 16.1, *)
private struct DoseWindowLockView: View {
    let attributes: DoseWindowAttributes
    let state: DoseWindowAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: attributes.tintHex),
                                Color(hex: attributes.tintHex).opacity(0.7),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "syringe.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.peptideAbbreviation)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text(attributes.doseDisplay)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if state.completed {
                    Text("Logged")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: attributes.tintHex))
                } else if state.doseTime > Date() {
                    Text(state.doseTime, style: .timer)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                    Text("until dose")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text(state.doseTime, style: .relative)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                    Text("late")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Color helper

private extension Color {
    init(hex: UInt) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
