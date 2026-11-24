import SwiftUI

/// The top of a fresh workout recap: the training level ring fills with
/// the XP this workout earned and, when it crosses the line, rolls over
/// to the next level. One accent, one moment, then it settles.
struct RecapLevelHero: View {
    let gain: TrainingLevelEngine.Gain
    let name: String
    let date: Date?
    /// Called the moment the ring rolls over, for the screen's own burst.
    let onLevelUp: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: Int
    @State private var fill: Double
    @State private var earned = 0
    @State private var levelledUp = false
    @State private var played = false
    @State private var pulse = false

    private static let diameter: CGFloat = 148
    private static let stroke: CGFloat = 12

    init(gain: TrainingLevelEngine.Gain, name: String, date: Date?, onLevelUp: @escaping () -> Void) {
        self.gain = gain
        self.name = name
        self.date = date
        self.onLevelUp = onLevelUp
        _level = State(initialValue: gain.before.level)
        _fill = State(initialValue: gain.before.fraction)
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            ring
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                    Text("Workout saved")
                }
                .font(AppFont.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                Text("+\(earned) XP")
                    .accessibilityLabel(Text("Earned \(gain.earnedXP) XP"))
                    .font(AppFont.largeTitle)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(earned)))
                    .foregroundStyle(AppColor.textPrimary)
                Text(progressLine)
                    .font(AppFont.headline)
                    .foregroundStyle(levelledUp ? AppColor.accentPrimary : AppColor.textSecondary)
                    .contentTransition(.opacity)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Spacing.xxs) {
                Text(name).font(AppFont.subheadline.weight(.semibold))
                if let date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFont.footnote).foregroundStyle(AppColor.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .task { await play() }
        // An edit from the summary re-derives the XP; show it without replaying.
        .onChange(of: gain) { showFinalState() }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(AppColor.track, lineWidth: Self.stroke)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(AppColor.accentPrimary, style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("Level")
                    .font(AppFont.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.textSecondary)
                Text("\(level)")
                    .font(AppFont.statValue)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(level)))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(Self.stroke * 2)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .scaleEffect(pulse ? 1.05 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Level \(gain.after.level), \(gain.after.xpToNextLevel) XP to level \(gain.after.level + 1)"))
    }

    private var progressLine: String {
        if levelledUp {
            return String(localized: "Level up! You reached level \(gain.after.level)")
        }
        return String(localized: "\(gain.after.xpToNextLevel) XP to level \(gain.after.level + 1)")
    }

    /// Fill to the end of each level crossed, roll the number over, then
    /// fill into the new level. Reduce Motion shows the end state at once.
    private func play() async {
        guard !played else { return }
        played = true
        guard !reduceMotion else {
            showFinalState()
            if gain.levelsGained > 0 { onLevelUp() }
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        AppAnimation.with(AppAnimation.draw) { earned = gain.earnedXP }
        for _ in 0..<gain.levelsGained {
            AppAnimation.with(AppAnimation.springGentle) { fill = 1 }
            try? await Task.sleep(for: .milliseconds(850))
            fill = 0
            AppAnimation.with(AppAnimation.springBouncy) {
                level += 1
                levelledUp = true
                pulse = true
            }
            Haptics.impact(.heavy)
            onLevelUp()
            try? await Task.sleep(for: .milliseconds(250))
        }
        AppAnimation.with(AppAnimation.springGentle) {
            fill = gain.after.fraction
            pulse = false
        }
        if !levelledUp { Haptics.impact(.light) }
    }

    private func showFinalState() {
        level = gain.after.level
        fill = gain.after.fraction
        earned = gain.earnedXP
        levelledUp = gain.levelsGained > 0
    }
}
