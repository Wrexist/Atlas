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
///   • ended        — "Fast ended" summary beat, dismissed by the system;
///                    green only when the fast reached its goal
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
                    FastActionButton(state: state, fastId: context.attributes.fastId, accent: accent)
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
    /// The theme accent while fasting, matching the Meals tab's fasting
    /// ring; green once the goal is reached, and on the ended beat only
    /// when the fast got there.
    static func accent(for state: FastingActivityAttributes.ContentState) -> Color {
        switch state.status() {
        case .fasting: WidgetPalette.accent
        case .goalReached: WidgetPalette.done
        case .ended: state.reachedGoal() ? WidgetPalette.done : WidgetPalette.accent
        }
    }

    static func glyph(for state: FastingActivityAttributes.ContentState) -> String {
        switch state.status() {
        case .fasting: "moon.zzz.fill"
        case .goalReached: "checkmark.seal.fill"
        case .ended: state.reachedGoal() ? "checkmark.circle.fill" : "stop.circle.fill"
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

    /// "2:13:45" — the shape `Text(timerInterval:)` draws while the fast
    /// runs, so the clock doesn't change form on the ended beat. Hours
    /// don't wrap at 24.
    static func clock(_ interval: TimeInterval) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = interval >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(Int(max(0, interval))).formatted(.time(pattern: pattern))
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
                FastActionButton(state: state, fastId: attributes.fastId, accent: accent)
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
/// dose activity's window ring does; full once the goal is reached, and
/// frozen at the share fasted when a fast ends short of it.
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
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.25), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: state.goalProgress())
                    .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: 64, alignment: .leading)
                    Text("left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                case .goalReached, .ended:
                    if state.reachedGoal() {
                        Label("Goal reached", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                    } else {
                        Text("Ended early")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text("Goal \(WidgetFormat.duration(minutes: goalMinutes))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Goal \(WidgetFormat.spokenDuration(minutes: goalMinutes))"))
            }
            if state.status() == .fasting {
                ProgressView(timerInterval: state.window.goalInterval, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(accent)
            } else {
                ProgressView(value: state.goalProgress())
                    .tint(accent)
            }
        }
    }

    /// The goal as a length ("16h"), so it can't read as the clock time
    /// the subtitle's "Goal at 08:00" shows.
    private var goalMinutes: Int { Int(state.window.targetDuration / 60) }
}

/// The lock screen's action. One tap ends a fast that reached its goal;
/// an unfinished fast opens the app instead, where ending early asks
/// first, so a stray tap can't cost the streak day. Nothing once ended.
private struct FastActionButton: View {
    let state: FastingActivityAttributes.ContentState
    let fastId: UUID
    let accent: Color

    var body: some View {
        switch state.status() {
        case .goalReached:
            EndFastButton(fastId: fastId, accent: accent)
        case .fasting:
            if let meals = WidgetDeepLink.meals {
                Link(destination: meals) {
                    ActionCapsule(title: "Open fast", systemImage: "arrow.up.forward.app.fill", accent: accent)
                }
            }
        case .ended:
            EmptyView()
        }
    }
}

/// The full-width capsule both lock-screen actions share.
private struct ActionCapsule: View {
    let title: LocalizedStringKey
    let systemImage: String
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .heavy))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(labelColor(on: accent, in: colorScheme))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Capsule().fill(accent))
    }
}

/// Ends the fast from the lock screen. The intent ends the activity on
/// its summary beat at once and the app records the end time.
private struct EndFastButton: View {
    let fastId: UUID
    let accent: Color

    var body: some View {
        Button(intent: EndFastLiveActivityIntent(fastId: fastId)) {
            ActionCapsule(title: "End fast", systemImage: "stop.fill", accent: accent)
        }
        .buttonStyle(.plain)
    }
}
