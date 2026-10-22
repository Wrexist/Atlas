import SwiftUI

/// Apple-Activity-style calorie ring with per-meal-category
/// segments. Replaces the outer monochrome calorie ring on
/// `MacroSummaryRow`'s legacy three-ring stack — each segment's
/// length is proportional to that meal's calorie share of the
/// day's target, drawn in the same warm-to-cool palette
/// (`MealCategory.tint`) the breakdown card uses. The visual
/// payoff: a user can glance at the ring and see "I ate breakfast
/// and lunch but no dinner yet" without reading labels.
///
/// Empty days render the bare track. Over-target days clip the
/// total fill at 1.0 with a faint glow indicator so the user
/// knows they crossed but the ring doesn't overdraw.
struct SegmentedCalorieRing: View {
    let breakdown: LifestyleDataLogic.CategoryBreakdown
    let target: Int
    let lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Per-view-lifetime, so a tab switch back doesn't replay the sweep.
    @State private var hasAppeared = false

    init(
        breakdown: LifestyleDataLogic.CategoryBreakdown,
        target: Int,
        lineWidth: CGFloat = 12
    ) {
        self.breakdown = breakdown
        self.target = target
        self.lineWidth = lineWidth
    }

    /// Segments to render, in order around the ring. Empty buckets
    /// are dropped so the ring doesn't waste angular space on zero-
    /// calorie meals. "Other" (legacy aggregate-only logs) inherits
    /// the secondary text tint so it reads as out-of-band data.
    private var segments: [Segment] {
        guard target > 0 else { return [] }
        let totalLogged = max(0, breakdown.totalCalories)
        // Cap progress at 1.0 to keep the ring from overdrawing past
        // full. A separate "over target" indicator is rendered below
        // when the user crosses.
        let progressCap = min(1.0, Double(totalLogged) / Double(target))
        // Per-segment proportion within the consumed total, scaled
        // by the overall progress cap. e.g. if the user ate 110% of
        // target, every segment shrinks proportionally so the ring
        // closes exactly at full.
        guard totalLogged > 0 else { return [] }

        let entries: [(Color, Int)] = [
            (MealCategory.breakfast.tint, breakdown.breakfast.calories),
            (MealCategory.lunch.tint,     breakdown.lunch.calories),
            (MealCategory.dinner.tint,    breakdown.dinner.calories),
            (MealCategory.snack.tint,     breakdown.snack.calories),
            (AppColor.textSecondary,      breakdown.other.calories),
        ]
        let actualTotal = Double(totalLogged)
        var accumulator: Double = 0
        var output: [Segment] = []
        for (tint, calories) in entries where calories > 0 {
            let proportion = Double(calories) / actualTotal
            let start = accumulator * progressCap
            accumulator += proportion
            let end = accumulator * progressCap
            output.append(Segment(tint: tint, start: start, end: end))
        }
        return output
    }

    /// Total fill ratio capped at 1.0 — when over target the ring
    /// reads "full" rather than overdrawing back around the start.
    private var totalProgress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(max(0, breakdown.totalCalories)) / Double(target))
    }

    /// How far past the target the day went, as a fraction of a second
    /// lap (capped at one full lap). Zero when on or under target.
    private var overflowProgress: Double {
        guard target > 0, breakdown.totalCalories > target else { return 0 }
        return min(1.0, Double(breakdown.totalCalories - target) / Double(target))
    }

    /// 0 → 1 multiplier on every segment's trim, so the first appear
    /// sweeps the ring from empty. Reduce Motion skips straight to full.
    private var reveal: Double {
        hasAppeared || reduceMotion ? 1 : 0
    }

    var body: some View {
        ZStack {
            track
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                arc(for: segment)
            }
            if overflowProgress > 0 {
                overflowLap
            }
        }
        .appAnimation(AppAnimation.springSmooth, value: totalProgress)
        .appAnimation(AppAnimation.springSmooth, value: overflowProgress)
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
    }

    private var track: some View {
        Circle()
            .stroke(AppColor.surfaceElevated.opacity(0.65), lineWidth: lineWidth)
    }

    /// The gradient keeps the segment's final angles so the sweep
    /// uncovers it rather than stretching it.
    private func arc(for segment: Segment) -> some View {
        Circle()
            .trim(from: segment.start * reveal, to: segment.end * reveal)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [segment.tint.opacity(0.85), segment.tint]),
                    center: .center,
                    startAngle: .degrees(-90 + 360 * segment.start),
                    endAngle: .degrees(-90 + 360 * segment.end)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )
            .rotationEffect(.degrees(-90))
    }

    /// A thin second lap in the warning tint for calories past target,
    /// Activity-ring style, so going over reads as "past the line"
    /// rather than as an error glow.
    private var overflowLap: some View {
        Circle()
            .trim(from: 0, to: overflowProgress * reveal)
            .stroke(AppColor.warning, style: StrokeStyle(lineWidth: lineWidth / 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    private var accessibilityDescription: String {
        if target == 0 {
            return String(localized: "Calorie ring. No target set.")
        }
        if breakdown.totalCalories == 0 {
            return String(localized: "Calorie ring. No meals logged.")
        }
        let parts: [(MealCategory?, Int)] = [
            (.breakfast, breakdown.breakfast.calories),
            (.lunch,     breakdown.lunch.calories),
            (.dinner,    breakdown.dinner.calories),
            (.snack,     breakdown.snack.calories),
            (nil,        breakdown.other.calories),
        ]
        let nonZero = parts.filter { $0.1 > 0 }
        let segmentsCopy = nonZero.map { (category, kcal) -> String in
            let name = category?.displayName ?? String(localized: "Other")
            return "\(name) \(kcal)"
        }.joined(separator: ", ")
        let totals = String(
            localized: "\(breakdown.totalCalories) of \(target) kilocalories",
            comment: "Headline portion of the ring's VoiceOver readout."
        )
        return "\(totals). \(segmentsCopy)."
    }

    private struct Segment {
        let tint: Color
        let start: Double
        let end: Double
    }
}
