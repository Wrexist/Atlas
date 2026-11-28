import SwiftUI

/// The live workout's completion bar: percent of working sets done, one
/// segment per exercise, and a line that answers each checked set with
/// what it earned — a gain on last time, a finished exercise, a
/// milestone. The bar never changes height, so checking a set never moves
/// the next tap.
struct WorkoutProgressHeader: View {
    let session: WorkoutSession
    let unit: MeasurementUnit
    /// Last session's sets for an exercise id, for the "on last time" line.
    let previousSets: (String) -> [SetEntry]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var shown: ShownReward?
    @State private var setTrigger = 0
    @State private var milestoneTrigger = 0

    private struct ShownReward: Equatable {
        let id = UUID()
        let reward: WorkoutProgressEngine.Reward
    }

    /// Long enough to read between racking the weight and sitting up.
    private static let rewardHold: Duration = .milliseconds(2800)
    /// The milestone beat lands after the check's own tap, not on top of it.
    private static let milestoneBeat: Duration = .milliseconds(220)

    var body: some View {
        let progress = WorkoutProgressEngine.progress(of: session)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.md))
            layout {
                percentLabel(progress)
                message(progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(progress.done) of \(progress.total) sets")
                    .font(AppFont.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fixedSize()
            }
            SessionProgressBar(segments: progress.segments, currentID: session.selectedExercise?.id)
        }
        .appAnimation(AppAnimation.springSmooth, value: progress.done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout progress")
        .accessibilityValue(Text(accessibilityValue(progress)))
        .accessibilityIdentifier("workout-progress")
        .onChange(of: session) { before, after in react(before: before, after: after) }
        .task(id: shown?.id) {
            guard shown != nil else { return }
            do { try await Task.sleep(for: Self.rewardHold) } catch { return }
            AppAnimation.with(AppAnimation.toast) { shown = nil }
        }
    }

    // MARK: - Pieces

    private func percentLabel(_ progress: WorkoutProgressEngine.Progress) -> some View {
        Text(Double(progress.percent) / 100, format: .percent.precision(.fractionLength(0)))
            .font(AppFont.statHeader)
            .foregroundStyle(progress.remaining == 0 && progress.total > 0 ? AppColor.accentPrimary : AppColor.textPrimary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .fixedSize()
            .completionPulse(trigger: setTrigger)
            .milestoneMotion(trigger: milestoneTrigger, playsOnArrival: false, style: .shine)
    }

    @ViewBuilder
    private func message(_ progress: WorkoutProgressEngine.Progress) -> some View {
        Group {
            if let shown {
                Label {
                    Text(rewardText(shown.reward))
                } icon: {
                    Image(systemName: rewardIcon(shown.reward))
                }
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .id(shown.id)
            } else {
                Text(statusText(WorkoutProgressEngine.status(for: progress)))
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .minimumScaleFactor(0.85)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Reacting to a checked set

    private func react(before: WorkoutSession, after: WorkoutSession) {
        guard let done = WorkoutProgressEngine.newlyCompleted(before: before, after: after) else { return }
        let old = WorkoutProgressEngine.progress(of: before)
        let new = WorkoutProgressEngine.progress(of: after)
        let previous = PreviousSetEngine.hints(for: done.entry.sets, previous: previousSets(done.entry.exerciseID))
        let gain = WorkoutProgressEngine.gain(done.set, over: previous[done.set.id])
        setTrigger &+= 1
        if WorkoutProgressEngine.milestone(from: old.percent, to: new.percent) != nil {
            milestoneTrigger &+= 1
            // A finished exercise already lands the success haptic.
            if !done.entry.workingSetsDone {
                Task {
                    try? await Task.sleep(for: Self.milestoneBeat)
                    Haptics.impact(.heavy)
                }
            }
        }
        let reward = WorkoutProgressEngine.reward(entry: done.entry, gain: gain, before: old, after: new)
        AppAnimation.with(AppAnimation.toast) { shown = reward.map { ShownReward(reward: $0) } }
    }

    // MARK: - Copy

    private func statusText(_ status: WorkoutProgressEngine.Status) -> String {
        switch status {
        case .start: String(localized: "Every set moves this bar.")
        case .setsToGo(let count): String(localized: "\(count) sets to go")
        case .pastHalfway(let count): String(localized: "Past halfway · \(count) sets to go")
        case .almostThere(let count): String(localized: "Almost there · \(count) sets left")
        case .lastSet: String(localized: "Last set. Finish strong.")
        case .allDone: String(localized: "Every set done. Strong work.")
        }
    }

    private func rewardText(_ reward: WorkoutProgressEngine.Reward) -> String {
        switch reward {
        case .exerciseDone: return String(localized: "Exercise complete. On to the next.")
        case .gain(.weight(let kg)):
            let amount = "\(unit.weightValue(kg, fractionDigits: 0...1)) \(unit.weightSuffix)"
            return String(localized: "+\(amount) on last time")
        case .gain(.reps(let count)):
            return count == 1 ? String(localized: "+1 rep on last time") : String(localized: "+\(count) reps on last time")
        case .gain(.matched): return String(localized: "Matched last time")
        case .milestone(25): return String(localized: "A quarter done")
        case .milestone(50): return String(localized: "Halfway there")
        case .milestone: return String(localized: "Three quarters done")
        case .set(let variant):
            switch variant {
            case 0: return String(localized: "Nice set.")
            case 1: return String(localized: "Strong set.")
            default: return String(localized: "One more in the bank.")
            }
        }
    }

    private func rewardIcon(_ reward: WorkoutProgressEngine.Reward) -> String {
        switch reward {
        case .exerciseDone: "checkmark.circle.fill"
        case .gain(.matched): "equal.circle.fill"
        case .gain: "arrow.up.circle.fill"
        case .milestone: "flag.fill"
        case .set: "checkmark"
        }
    }

    private func accessibilityValue(_ progress: WorkoutProgressEngine.Progress) -> String {
        let percent = (Double(progress.percent) / 100).formatted(.percent.precision(.fractionLength(0)))
        let line = shown.map { rewardText($0.reward) } ?? statusText(WorkoutProgressEngine.status(for: progress))
        return String(localized: "\(percent), \(progress.done) of \(progress.total) sets. \(line)")
    }
}

/// One segment per exercise, each as wide as its share of the working
/// sets, so the filled length is exactly the percent beside it. The
/// current exercise's segment stands a little taller.
private struct SessionProgressBar: View {
    let segments: [WorkoutProgressEngine.Segment]
    let currentID: UUID?

    private static let height: CGFloat = 6
    private static let currentHeight: CGFloat = 10
    private static let gap: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let total = max(1, segments.reduce(0) { $0 + $1.total })
            let usable = max(0, geometry.size.width - Self.gap * CGFloat(max(0, segments.count - 1)))
            HStack(spacing: Self.gap) {
                ForEach(segments) { segment in
                    let width = usable * CGFloat(segment.total) / CGFloat(total)
                    let fill = segment.total == 0 ? 0 : CGFloat(segment.done) / CGFloat(segment.total)
                    let height = segment.id == currentID ? Self.currentHeight : Self.height
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColor.track)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: width * fill)
                    }
                    .frame(width: width, height: height)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(height: Self.currentHeight)
        .appAnimation(AppAnimation.springSnappy, value: currentID)
        .accessibilityHidden(true)
    }
}
