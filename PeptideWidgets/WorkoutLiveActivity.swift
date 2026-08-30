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
/// `RestTimerOverlay` and its local notification already run on, so
/// nothing here can drift from what the app shows.
@available(iOS 16.1, *)
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockView(attributes: context.attributes, state: context.state)
                .widgetURL(WorkoutActivityStyle.deepLink)
        } dynamicIsland: { context in
            buildDynamicIsland(context: context)
        }
    }

    @available(iOS 16.1, *)
    private func buildDynamicIsland(
        context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> DynamicIsland {
        let accent = WorkoutActivityStyle.accent(for: context.state)
        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                IslandGlyph(state: context.state, accent: accent)
            }
            DynamicIslandExpandedRegion(.trailing) {
                IslandTimer(
                    attributes: context.attributes,
                    state: context.state,
                    accent: accent
                )
            }
            DynamicIslandExpandedRegion(.center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.state.displayName)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(WorkoutActivityStyle.subtitle(for: context.state))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DynamicIslandExpandedRegion(.bottom) {
                SetProgressBar(state: context.state, accent: accent)
            }
        } compactLeading: {
            Image(systemName: WorkoutActivityStyle.glyph(for: context.state))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
        } compactTrailing: {
            CompactTiming(
                attributes: context.attributes,
                state: context.state,
                accent: accent
            )
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
    static func accent(for state: WorkoutActivityAttributes.ContentState) -> Color {
        switch state.status() {
        case .lifting:  return Color(red: 0.216, green: 0.541, blue: 0.867)
        case .resting:  return Color(red: 1.00, green: 0.70, blue: 0.20)
        case .finished: return Color(red: 0.36, green: 0.78, blue: 0.55)
        }
    }

    static func glyph(for state: WorkoutActivityAttributes.ContentState) -> String {
        switch state.status() {
        case .lifting:  return "figure.strengthtraining.traditional"
        case .resting:  return "hourglass"
        case .finished: return "checkmark.circle.fill"
        }
    }

    /// The line under the workout name. Falls back to the set count
    /// when there's no exercise to name yet.
    static func subtitle(for state: WorkoutActivityAttributes.ContentState) -> String {
        switch state.status() {
        case .finished:
            return "\(state.completedSets) sets · done"
        case .resting, .lifting:
            if !state.currentExercise.isEmpty { return state.currentExercise }
            return state.exerciseCount == 0
                ? "Add your first exercise"
                : "\(state.completedSets)/\(state.totalSets) sets"
        }
    }
}

// MARK: - Lock screen

@available(iOS 16.1, *)
private struct WorkoutLockView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    private var accent: Color { WorkoutActivityStyle.accent(for: state) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.30), accent.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 12) {
                topRow
                SetProgressBar(state: state, accent: accent)
            }
            .padding(14)
        }
        .activityBackgroundTint(Color.black.opacity(0.05))
        .activitySystemActionForegroundColor(.white)
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
        case .lifting:
            VStack(alignment: .trailing, spacing: 0) {
                Text(attributes.startedAt, style: .timer)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: 88)
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
        case .resting:  return state.restProgress()
        case .finished: return 1
        case .lifting:  return state.setProgress
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.20), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: WorkoutActivityStyle.glyph(for: state))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
        }
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
            case .lifting:
                Text(attributes.startedAt, style: .timer)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.white)
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
        case .lifting:
            Text(attributes.startedAt, style: .timer)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .frame(maxWidth: 48)
        }
    }
}
