import SwiftUI

/// Calorie-ring micro-update shown on the barcode scanner's `.logged`
/// success screen. Animates "before → after" so the user feels their
/// progress against today's target the moment they finish logging.
///
/// The ring is purely visual feedback — it has no input controls. The
/// "before" value is computed by subtracting the just-logged delta
/// from `DataStore.consumption()` (which already includes the new
/// entry by the time this view appears). The actual current value
/// drives the ring's final position; the animation interpolates.
struct LoggedCaloriePanel: View {
    let productName: String
    let deltaCalories: Int
    let totalCalories: Int
    let targetCalories: Int
    var date: Date = Date()

    /// Animated number that drives both the ring fill and the displayed
    /// kcal count. Starts at the pre-log value, eases to the post-log
    /// value on appear, locking the user's eye to the change they
    /// just caused.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Grows with Dynamic Type so the scaled numbers stay inside the stroke.
    @ScaledMetric(relativeTo: .title2) private var ringDiameter: CGFloat = 110
    @State private var hasRevealed = false

    // State records presentation, never a copy of the caller's calorie total.
    private var displayed: Double {
        Double(reduceMotion || hasRevealed ? totalCalories : max(0, totalCalories - deltaCalories))
    }

    private var finalProgress: Double {
        guard targetCalories > 0 else { return 0 }
        return min(1, max(0, Double(totalCalories) / Double(targetCalories)))
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .stroke(AppColor.surfaceSecondary.opacity(0.8), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: ringTrim)
                    .stroke(
                        AppColor.macroCalories,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: Spacing.xxs) {
                    Text("\(Int(displayed))")
                        .font(AppFont.scaled(20, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Group {
                        if targetCalories > 0 {
                            Text("of \(targetCalories) kcal")
                        } else {
                            Text("kcal")
                        }
                    }
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, Spacing.md)
            }
            .frame(width: ringDiameter, height: ringDiameter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSummary)
            .accessibilityValue(targetCalories > 0 ? Text("\(Int(finalProgress * 100)) percent") : Text(verbatim: ""))

            budgetLine

            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .accessibilityHidden(true)
                Text("\(deltaCalories) kcal · \(productName)")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: totalCalories)
        .task {
            guard !hasRevealed else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion)) {
                hasRevealed = true
            }
        }
    }

    private var spokenSummary: Text {
        let day = date.formatted(date: .abbreviated, time: .omitted)
        return targetCalories > 0
            ? Text("Calories for \(day): \(totalCalories) of \(targetCalories)")
            : Text("Calories for \(day): \(totalCalories)")
    }

    /// Where the day stands against its calorie target. Landing within 5%
    /// either side counts as reached; further over is reported as over,
    /// never as a success.
    enum Budget: Equatable {
        case left(Int)
        case reached
        case over(Int)
    }

    nonisolated static func budget(total: Int, target: Int) -> Budget? {
        guard target > 0 else { return nil }
        let remaining = target - total
        let band = Int((Double(target) * 0.05).rounded())
        if remaining > band { return .left(remaining) }
        if remaining < -band { return .over(-remaining) }
        return .reached
    }

    /// What the meal leaves of the day's budget, so the success screen
    /// ends on where the day stands rather than only on what was added.
    @ViewBuilder
    private var budgetLine: some View {
        switch Self.budget(total: totalCalories, target: targetCalories) {
        case .some(.left(let remaining)):
            Label {
                Text("\(remaining) kcal left").monospacedDigit()
            } icon: {
                Image(systemName: "flag.checkered")
            }
            .font(AppFont.scaled(13, weight: .semibold))
            .foregroundStyle(AppColor.textPrimary)
        case .some(.reached):
            Label("Daily target reached", systemImage: "checkmark.seal.fill")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.success)
        case .some(.over(let over)):
            Text("\(over) kcal over")
                .font(AppFont.scaled(13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppColor.macroCalories)
        case .none:
            EmptyView()
        }
    }

    private var ringTrim: CGFloat {
        guard targetCalories > 0 else { return 0 }
        // Cap at 1.0 so going over target still shows a full ring
        // (rather than wrapping past the start and looking broken).
        // The number underneath still shows the actual value, so an
        // over-target day stays visible as a number even when the
        // ring is at max.
        return CGFloat(min(1.0, max(0, displayed / Double(targetCalories))))
    }
}
