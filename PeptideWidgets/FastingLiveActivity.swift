import ActivityKit
import SwiftUI
import WidgetKit

/// Lock-screen + Dynamic Island Live Activity for the fast in progress.
/// Built on the bones of `WorkoutLiveActivity`: one status enum drives
/// every surface, so the pill, the expanded island and the lock screen
/// can't tell different stories.
///
/// States:
///   • fasting      — elapsed clock, time left, ring filling to the goal
///   • goalReached  — green, the clock keeps counting
///   • ended        — "Fast ended" summary beat, dismissed by the system
///
/// Every clock and ring is drawn from absolute dates with the system's
/// timer views, so nothing here needs a push to keep moving. Started,
/// updated and ended by `FastingLiveActivityService`.
struct FastingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            FastingLockView(attributes: context.attributes, state: context.state)
                .widgetURL(WidgetDeepLink.meals)
        } dynamicIsland: { context in
            buildDynamicIsland(context: context)
        }
    }

    private func buildDynamicIsland(
        context: ActivityViewContext<FastingActivityAttributes>
    ) -> DynamicIsland {
        let state = context.state
        let accent = FastingActivityStyle.accent(for: state)
        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                ZStack {
                    Circle().fill(accent.opacity(0.20))
                    Image(systemName: FastingActivityStyle.glyph(for: state))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
            }
            DynamicIslandExpandedRegion(.trailing) {
                VStack(alignment: .trailing, spacing: 0) {
                    FastingClock(state: state)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 80)
                    Text(state.endedAt == nil ? LocalizedStringKey("elapsed") : "fasted")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            DynamicIslandExpandedRegion(.center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Fasting · \(context.attributes.protocolName)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(FastingActivityStyle.subtitle(for: state))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(spacing: 8) {
                    GoalProgress(state: state, accent: accent)
                    if state.endedAt == nil {
                        EndFastButton(fastId: context.attributes.fastId, accent: accent)
                    }
                }
            }
        } compactLeading: {
            Image(systemName: FastingActivityStyle.glyph(for: state))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
        } compactTrailing: {
            FastingClock(state: state)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .frame(maxWidth: 56)
        } minimal: {
            GoalRing(state: state, accent: accent, lineWidth: 2.5)
        }
        .widgetURL(WidgetDeepLink.meals)
        .keylineTint(accent)
    }
}

// MARK: - Style

/// Status → colour, glyph and copy, in one place.
private enum FastingActivityStyle {
    /// Brand emerald while fasting, matching the Meals tab's fasting
    /// ring; green once the goal is reached and on the ended beat.
    static func accent(for state: FastingActivityAttributes.ContentState) -> Color {
        switch state.status() {
        case .fasting: WidgetPalette.brand
        case .goalReached, .ended: WidgetPalette.done
        }
    }

    static func glyph(for state: FastingActivityAttributes.ContentState) -> String {
        switch state.status() {
        case .fasting: "moon.zzz.fill"
        case .goalReached: "checkmark.seal.fill"
        case .ended: "checkmark.circle.fill"
        }
    }

    static func subtitle(for state: FastingActivityAttributes.ContentState) -> LocalizedStringKey {
        switch state.status() {
        case .fasting:
            "Goal at \(state.targetEnd.formatted(date: .omitted, time: .shortened))"
        case .goalReached:
            "Goal reached · keep going or end your fast"
        case .ended:
            "Fast ended"
        }
    }

    /// "16:05" — hours and minutes, not wrapped at 24, like the in-app
    /// fasting ring.
    static func clock(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(max(0, interval) / 60)
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}

// MARK: - Lock screen

private struct FastingLockView: View {
    let attributes: FastingActivityAttributes
    let state: FastingActivityAttributes.ContentState

    private var accent: Color { FastingActivityStyle.accent(for: state) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.30), accent.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 12) {
                topRow
                GoalProgress(state: state, accent: accent)
                if state.endedAt == nil {
                    EndFastButton(fastId: attributes.fastId, accent: accent)
                }
            }
            .padding(14)
        }
        .activityBackgroundTint(Color.black.opacity(0.05))
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                GoalRing(state: state, accent: accent, lineWidth: 5)
                Image(systemName: FastingActivityStyle.glyph(for: state))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 56, height: 56)
            // The progress row below says what the ring shows.
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Fasting · \(attributes.protocolName)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(FastingActivityStyle.subtitle(for: state))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 0) {
                FastingClock(state: state)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(state.endedAt == nil ? Color.primary : accent)
                    .frame(maxWidth: 100)
                Text(state.endedAt == nil ? LocalizedStringKey("elapsed") : "fasted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared pieces

/// Time fasted: a live count-up from the start while the fast runs,
/// the frozen total once it has ended.
private struct FastingClock: View {
    let state: FastingActivityAttributes.ContentState

    var body: some View {
        Group {
            if let endedAt = state.endedAt {
                Text(FastingActivityStyle.clock(state.window.elapsed(at: endedAt)))
            } else {
                Text(timerInterval: state.window.elapsedInterval, countsDown: false)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Fills from the start to the goal on its own between pushes, as the
/// dose activity's window ring does; full once the goal is reached.
private struct GoalRing: View {
    let state: FastingActivityAttributes.ContentState
    let accent: Color
    let lineWidth: CGFloat

    var body: some View {
        if state.status() == .fasting {
            ProgressView(timerInterval: state.window.goalInterval, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(accent)
        } else {
            Circle()
                .stroke(accent, lineWidth: lineWidth)
                .padding(lineWidth / 2)
        }
    }
}

/// A bar toward the goal with the time left beside it, or the goal
/// marked reached once past it.
private struct GoalProgress: View {
    let state: FastingActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                switch state.status() {
                case .fasting:
                    Text(timerInterval: state.window.countdownInterval(from: Date()), countsDown: true)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 64, alignment: .leading)
                    Text("left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                case .goalReached, .ended:
                    Label("Goal reached", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 0)
                Text("Goal \(FastingActivityStyle.clock(state.window.targetDuration))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if state.status() == .fasting {
                ProgressView(timerInterval: state.window.goalInterval, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(accent)
            } else {
                ProgressView(value: 1)
                    .tint(accent)
            }
        }
    }
}

/// Ends the fast from the lock screen. The intent ends the activity on
/// its summary beat at once and the app records the end time.
private struct EndFastButton: View {
    let fastId: UUID
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(intent: EndFastLiveActivityIntent(fastId: fastId)) {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .accessibilityHidden(true)
                Text("End fast")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(labelColor(on: accent, in: colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(accent))
        }
        .buttonStyle(.plain)
    }
}
