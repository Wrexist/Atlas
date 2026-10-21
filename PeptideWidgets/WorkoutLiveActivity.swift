import ActivityKit
import SwiftUI
import WidgetKit

/// Lock-screen + Dynamic Island Live Activity for the workout in
/// progress. Built on the same bones as `DoseWindowLiveActivity`: one
/// status enum drives every surface, so the pill, the expanded island
/// and the lock screen can't tell different stories.
///
/// States:
///   • lifting  — elapsed workout time, set progress
///   • resting  — the rest countdown takes the hero slot, amber ring
///   • finished — green summary beat, dismissed by the service
///
/// Started and updated by `WorkoutLiveActivityService`. The rest
/// countdown is rendered from `restEndsAt`, the same absolute date
/// the persisted workout rest and its local notification already run on, so
/// nothing here can drift from what the app shows.
@available(iOS 16.1, *)
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockView(
                attributes: context.attributes,
                state: context.state,
                isIdle: context.state.isIdle(isStale: context.isStale)
            )
            .widgetURL(WorkoutActivityStyle.deepLink)
        } dynamicIsland: { context in
            buildDynamicIsland(context: context)
        }
    }

    @available(iOS 16.1, *)
    private func buildDynamicIsland(
        context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> DynamicIsland {
        let idle = context.state.isIdle(isStale: context.isStale)
        let accent = WorkoutActivityStyle.accent(for: context.state, idle: idle)
        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                IslandGlyph(state: context.state, accent: accent)
            }
            DynamicIslandExpandedRegion(.trailing) {
                if idle {
                    Text("Idle")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    IslandTimer(
                        attributes: context.attributes,
                        state: context.state,
                        accent: accent
                    )
                }
            }
            DynamicIslandExpandedRegion(.center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.state.displayName)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(idle ? WorkoutActivityStyle.idleSubtitle : WorkoutActivityStyle.subtitle(for: context.state))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(spacing: 8) {
                    SetProgressBar(state: context.state, accent: accent)
                    if !idle {
                        WorkoutActionButton(sessionId: context.attributes.sessionId, state: context.state, accent: accent)
                    }
                }
            }
        } compactLeading: {
            Image(systemName: WorkoutActivityStyle.glyph(for: context.state))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
        } compactTrailing: {
            if idle {
                Text("Idle")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                CompactTiming(
                    attributes: context.attributes,
                    state: context.state,
                    accent: accent
                )
            }
        } minimal: {
            Image(systemName: WorkoutActivityStyle.glyph(for: context.state))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
        }
        .widgetURL(WorkoutActivityStyle.deepLink)
        .keylineTint(accent)
    }
}

// MARK: - Style

/// Status → colour, glyph and copy. One place, so a state added later
/// can't be handled in four views and missed in a fifth.
@available(iOS 16.1, *)
private enum WorkoutActivityStyle {
    /// The Train tab, where the active workout already lives. Routed by
    /// `DeepLinkRouter`.
    static let deepLink = URL(string: "peptidex://train")

    /// `Text(timerInterval:)` traps on a range whose bounds are
    /// inverted. `status()` samples the clock a hair before this does,
    /// so a rest expiring in that gap would otherwise crash the
    /// extension rather than just finishing.
    static func countdown(to endsAt: Date) -> ClosedRange<Date> {
        let now = Date()
        return now...max(endsAt, now)
    }

    /// Brand blue for training; amber while resting so a glance
    /// separates "move" from "wait"; green on the finish beat. Matched
    /// to the values `DoseWindowLiveActivity` uses for the same beats.
    static func accent(for state: WorkoutActivityAttributes.ContentState, idle: Bool) -> Color {
        if idle { return Color.gray }
        switch state.status() {
        case .paused:   return Color.gray
        case .lifting:  return Color(red: 0.216, green: 0.541, blue: 0.867)
        case .resting:  return Color(red: 1.00, green: 0.70, blue: 0.20)
        case .finished: return Color(red: 0.36, green: 0.78, blue: 0.55)
        }
    }

    /// The frozen clock, in the same H:MM:SS / M:SS shape the running
    /// timer and the training widget use.
    static func pausedTime(_ state: WorkoutActivityAttributes.ContentState) -> String {
        let seconds = max(0, state.pausedElapsedSeconds ?? 0)
        return Duration.seconds(seconds).formatted(
            .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond)
        )
    }

    static func glyph(for state: WorkoutActivityAttributes.ContentState) -> String {
        switch state.status() {
        case .paused:   return "pause.fill"
        case .lifting:  return "figure.strengthtraining.traditional"
        case .resting:  return "hourglass"
        case .finished: return "checkmark.circle.fill"
        }
    }

    /// Replaces the subtitle once the activity has gone stale with
    /// nobody touching the workout.
    static let idleSubtitle = String(localized: "Workout idle · Tap to resume")

    /// The line under the workout name. Falls back to the set count
    /// when there's no exercise to name yet.
    static func subtitle(for state: WorkoutActivityAttributes.ContentState) -> String {
        switch state.status() {
        case .paused:
            return String(localized: "Workout paused")
        case .finished:
            return String(localized: "\(state.completedSets) sets · done")
        case .resting, .lifting:
            if !state.currentExercise.isEmpty { return state.currentExercise }
            return state.exerciseCount == 0
                ? String(localized: "Add your first exercise")
                : String(localized: "\(state.completedSets)/\(state.totalSets) sets")
        }
    }
}

// MARK: - Lock screen

@available(iOS 16.1, *)
private struct WorkoutLockView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    /// Stale and untouched: the clock and the action button would
    /// describe a workout nobody is doing.
    let isIdle: Bool

    private var accent: Color { WorkoutActivityStyle.accent(for: state, idle: isIdle) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.30), accent.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if isIdle {
                idleRow
                    .padding(14)
            } else {
                VStack(spacing: 12) {
                    topRow
                    SetProgressBar(state: state, accent: accent)
                    WorkoutActionButton(sessionId: attributes.sessionId, state: state, accent: accent)
                }
                .padding(14)
            }
        }
        .activityBackgroundTint(Color.black.opacity(0.05))
        .activitySystemActionForegroundColor(.white)
    }

    /// Neutral layout for a forgotten workout. The whole view still
    /// deep-links to the Train tab, so tapping resumes it.
    private var idleRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "zzz")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.displayName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(WorkoutActivityStyle.idleSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 14) {
            LockRing(state: state, accent: accent)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.displayName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(WorkoutActivityStyle.subtitle(for: state))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            timerColumn
        }
    }

    @ViewBuilder
    private var timerColumn: some View {
        switch state.status() {
        case .finished:
            VStack(alignment: .trailing, spacing: 0) {
                Text("Done")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                Text("\(state.completedSets) sets")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .resting:
            VStack(alignment: .trailing, spacing: 0) {
                // Counts down against the rest target without the
                // extension being woken once per second.
                if let endsAt = state.restEndsAt {
                    Text(timerInterval: WorkoutActivityStyle.countdown(to: endsAt), countsDown: true)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(accent)
                        .frame(maxWidth: 78)
                }
                Text("rest")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        case .paused:
            VStack(alignment: .trailing, spacing: 0) {
                Text(WorkoutActivityStyle.pausedTime(state))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Paused at \(WorkoutActivityStyle.pausedTime(state))")
                Text("paused")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        case .lifting:
            VStack(alignment: .trailing, spacing: 0) {
                Text(state.activeTimerStartedAt ?? attributes.startedAt, style: .timer)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 100)
                Text("elapsed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared pieces

/// Rest countdown when resting, set completion otherwise — the ring
/// always shows the progress the user is actually waiting on.
@available(iOS 16.1, *)
private struct LockRing: View {
    let state: WorkoutActivityAttributes.ContentState
    let accent: Color

    private var progress: Double {
        switch state.status() {
        case .finished: return 1
        case .resting, .lifting, .paused: return state.setProgress
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.20), lineWidth: 5)
            ring
            Image(systemName: WorkoutActivityStyle.glyph(for: state))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
        }
    }

    /// A Live Activity only redraws on a push, so a rest arc drawn from
    /// `Date()` would freeze between pushes; the system timer view keeps
    /// filling on its own, as the dose activity's window ring does.
    @ViewBuilder
    private var ring: some View {
        if case .resting = state.status(), let restInterval = state.restInterval {
            ProgressView(timerInterval: restInterval, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(accent)
        } else {
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// One button for what the user is waiting to do next: end the rest
/// early, or tick off the set they just finished. Hidden while paused,
/// finished, or once every planned set is done.
private struct WorkoutActionButton: View {
    let sessionId: UUID
    let state: WorkoutActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        switch state.status() {
        case .resting:
            button(.skipRest, title: "Skip rest", systemImage: "forward.fill")
        case .lifting where state.completedSets < state.totalSets:
            button(.completeSet, title: "Complete set", systemImage: "checkmark")
        default:
            EmptyView()
        }
    }

    private func button(_ action: WorkoutActivityAction, title: LocalizedStringKey, systemImage: String) -> some View {
        Button(intent: WorkoutActivityActionIntent(sessionId: sessionId, action: action)) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .heavy))
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(accent.opacity(0.85)))
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 16.1, *)
private struct SetProgressBar: View {
    let state: WorkoutActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(state.totalSets > 0
                     ? "\(state.completedSets) of \(state.totalSets) sets"
                     : "No sets planned")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if state.exerciseCount > 0 {
                    Text(state.exerciseCount == 1
                         ? "1 exercise"
                         : "\(state.exerciseCount) exercises")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: state.setProgress)
                .tint(accent)
        }
    }
}

@available(iOS 16.1, *)
private struct IslandGlyph: View {
    let state: WorkoutActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.20))
            Image(systemName: WorkoutActivityStyle.glyph(for: state))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent)
        }
        .frame(width: 38, height: 38)
    }
}

@available(iOS 16.1, *)
private struct IslandTimer: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            switch state.status() {
            case .finished:
                Text("Done")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
            case .resting:
                if let endsAt = state.restEndsAt {
                    Text(timerInterval: WorkoutActivityStyle.countdown(to: endsAt), countsDown: true)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(accent)
                        .frame(maxWidth: 64)
                }
                Text("rest")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            case .paused:
                Text(WorkoutActivityStyle.pausedTime(state))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .accessibilityLabel("Paused at \(WorkoutActivityStyle.pausedTime(state))")
                Text("paused")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityHidden(true)
            case .lifting:
                Text(state.activeTimerStartedAt ?? attributes.startedAt, style: .timer)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 72)
                Text("elapsed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// The compact pill has room for one number: whichever clock the user
/// is watching right now.
@available(iOS 16.1, *)
private struct CompactTiming: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        switch state.status() {
        case .finished:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(accent)
        case .resting:
            if let endsAt = state.restEndsAt {
                Text(timerInterval: WorkoutActivityStyle.countdown(to: endsAt), countsDown: true)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .frame(maxWidth: 44)
            }
        case .paused:
            Image(systemName: "pause.fill")
                .foregroundStyle(accent)
                .accessibilityLabel("Workout paused")
        case .lifting:
            Text(state.activeTimerStartedAt ?? attributes.startedAt, style: .timer)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 56)
        }
    }
}
