import SwiftUI

/// Nutrition hero on the Lifestyle tab. Three Apple-Activity-style
/// concentric rings render Calories (outer), Protein (middle), and
/// Water (inner) progress in a single glass card. Each ring owns one
/// colour, shared by its legend dot, and going past a goal laps the
/// ring in a deeper shade of that same colour, so "over" never borrows
/// another metric's colour. A legend row
/// underneath that exposes the live values + targets. Carbs and fat
/// have no ring, so they sit in a compact row below. Water quick-add
/// chips sit at the bottom so the most common action (logging a glass
/// of water) stays one tap from the card.
struct MacroSummaryRow: View {
    let targets: NutritionTargets
    let consumed: DailyConsumption
    /// Water is stored in fluid ounces; this decides what the legend and
    /// the quick-add chips say. They used to disagree with each other.
    let unit: MeasurementUnit
    /// Exact fluid ounces, so a metric +1 L is 33.81 oz rather than a
    /// rounded 34 (which read back as 1005 mL).
    let onAddWater: (Double) -> Void
    /// Non-nil while the last quick-add can still be undone; shows an
    /// Undo chip beside the quick-adds.
    let onUndoWater: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var waterFeedback = 0
    @State private var selectedWaterAmount: Double?
    /// Per-view-lifetime, so a tab switch back doesn't replay the fill.
    @State private var hasAppeared = false
    /// Grows with the eyebrow it marks, so it stays a dot, not a speck,
    /// but stops at 12pt so accessibility sizes don't swell it into a disc.
    @ScaledMetric(relativeTo: .caption2) private var scaledLegendDotSize: CGFloat = 8
    private var legendDotSize: CGFloat { min(scaledLegendDotSize, 12) }

    init(
        targets: NutritionTargets,
        consumed: DailyConsumption,
        unit: MeasurementUnit,
        onAddWater: @escaping (Double) -> Void,
        onUndoWater: (() -> Void)? = nil
    ) {
        self.targets = targets
        self.consumed = consumed
        self.unit = unit
        self.onAddWater = onAddWater
        self.onUndoWater = onUndoWater
    }

    private static let waterTargetOz = TodayChecklistEngine.waterTargetOz

    /// Uncapped: past 1 the ring laps (see `ringFill`).
    private var caloriesProgress: Double {
        Self.fraction(consumed.caloriesKcal, of: targets.calories) ?? 0
    }

    private var proteinProgress: Double {
        Self.fraction(consumed.proteinG, of: targets.proteinG) ?? 0
    }

    private var waterProgress: Double {
        consumed.waterFluidOunces / Double(Self.waterTargetOz)
    }

    /// The water target in the unit shown: whole ounces, or millilitres
    /// rounded to 100 so the 100 oz goal reads 3000 mL, not 2957 mL.
    private var waterTargetDisplay: Int {
        let value = unit.volumeValue(Double(Self.waterTargetOz))
        return unit == .metric ? Int((Double(value) / 100).rounded()) * 100 : value
    }

    /// Rings and numbers start at zero until the first appear; Reduce
    /// Motion shows final values from the first frame.
    private var isRevealed: Bool {
        hasAppeared || reduceMotion
    }

    private func revealAnimation(index: Int) -> Animation? {
        AppAnimation.motionAware(AppAnimation.staggered(index: index), reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // At accessibility sizes the legend gets the full width under
            // the rings instead of ~180 pt beside them.
            let ringsAndLegend = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .center, spacing: Spacing.lg))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.lg))
            ringsAndLegend {
                ringStack
                    .frame(width: Self.ringDiameter, height: Self.ringDiameter)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    legend(
                        title: "Calories",
                        value: consumed.caloriesKcal,
                        target: Self.targetText(targets.calories, unit: "kcal"),
                        color: AppColor.macroCalories,
                        index: 0,
                        overBy: max(0, consumed.caloriesKcal - targets.calories),
                        remaining: targets.calories > 0 ? targets.calories - consumed.caloriesKcal : nil
                    )
                    legend(
                        title: "Protein",
                        value: consumed.proteinG,
                        target: Self.targetText(targets.proteinG, unit: "g"),
                        color: AppColor.macroProtein,
                        index: 1,
                        goalMet: targets.proteinG > 0 && consumed.proteinG >= targets.proteinG
                    )
                    legend(
                        title: "Water",
                        value: LifestyleDataLogic.displayedWater(consumed, unit: unit),
                        // Same unit as the number beside it: "1000/3000 mL",
                        // never "1000/3,0 L".
                        target: Self.targetText(waterTargetDisplay, unit: unit == .metric ? "mL" : "oz"),
                        color: AppColor.macroWater,
                        index: 2,
                        goalMet: consumed.waterFluidOunces >= Double(Self.waterTargetOz)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            carbsAndFat

            Divider()
                .overlay(AppColor.glassBorder)

            HStack(spacing: Spacing.sm) {
                ForEach(quickAddOptions) { option in
                    quickAddButton(option)
                }
                if let onUndoWater {
                    undoWaterButton(onUndoWater)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .appAnimation(AppAnimation.springSnappy, value: onUndoWater != nil)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius, tinted: true)
        .onAppear { hasAppeared = true }
        .onChange(of: consumed.waterFluidOunces) { oldValue, newValue in
            if selectedWaterAmount != nil && newValue > oldValue { waterFeedback &+= 1 }
        }
    }

    /// Same legend style as the ring rows, on the same grid: carbs under
    /// the rings, fat under the Calories / Protein / Water column.
    private var carbsAndFat: some View {
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.lg))
        return layout {
            legend(
                title: "Carbs",
                value: consumed.carbsG,
                target: Self.targetText(targets.carbsG, unit: "g"),
                color: AppColor.macroCarbs,
                index: 3,
                progress: Self.fraction(consumed.carbsG, of: targets.carbsG)
            )
            .frame(width: isStacked ? nil : Self.ringDiameter, alignment: .leading)
            .frame(maxWidth: isStacked ? .infinity : nil, alignment: .leading)
            legend(
                title: "Fat",
                value: consumed.fatG,
                target: Self.targetText(targets.fatG, unit: "g"),
                color: AppColor.macroFat,
                index: 4,
                progress: Self.fraction(consumed.fatG, of: targets.fatG)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "/2400 kcal", or just the unit when no target is set — never "/0".
    private static func targetText(_ target: Int, unit: String) -> String {
        target > 0 ? "/\(target) \(unit)" : " \(unit)"
    }

    /// Carbs and fat have no ring, so a bar shows how far along they
    /// are; nil without a target, where there is nothing to fill toward.
    private static func fraction(_ value: Int, of target: Int) -> Double? {
        target > 0 ? Double(value) / Double(target) : nil
    }

    private var ringStack: some View {
        ZStack {
            ring(diameter: 132, progress: caloriesProgress, colors: [AppColor.macroCaloriesLight, AppColor.macroCalories], index: 0)
            ring(diameter: 96, progress: proteinProgress, colors: [AppColor.macroProteinLight, AppColor.macroProtein], index: 1)
            ring(diameter: 60, progress: waterProgress, colors: [AppColor.macroWaterLight, AppColor.macroWater], index: 2)
        }
        .tiltParallax(depth: 3)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private static let ringDiameter: CGFloat = 132
    private static let ringLineWidth: CGFloat = 12

    /// Track and fill both sit inside `diameter`, so the outer ring lines
    /// up with the card's content edge instead of bleeding past it.
    private func ring(diameter: CGFloat, progress: Double, colors: [Color], index: Int) -> some View {
        ZStack {
            // Sunk as a groove the arc stands out of, like Today's rings.
            Circle()
                .strokeBorder(
                    colors[1].opacity(0.16).shadow(.inner(color: AppColor.ringGroove, radius: Self.ringLineWidth * 0.18, y: Self.ringLineWidth * 0.12)),
                    lineWidth: Self.ringLineWidth
                )
            ringFill(progress: min(1, progress), colors: colors, index: index, diameter: diameter)
                .appShadow(AppShadow.ringRaise)
            RaisedRingFinish(
                progress: isRevealed ? min(1, progress) : 0,
                diameter: diameter - Self.ringLineWidth,
                strokeWidth: Self.ringLineWidth,
                tipColor: colors[1]
            )
            .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: progress)
            .animation(revealAnimation(index: index), value: isRevealed)
            // Past the goal the ring keeps going, Activity style: a second
            // lap in a deeper shade of the same colour, with a soft shadow
            // under its leading cap so the overlap reads as "one more lap".
            if progress > 1 {
                ringFill(progress: min(1, progress - 1), colors: [colors[1], colors[1].mix(with: .black, by: 0.35)], index: index, diameter: diameter)
                    .appShadow(AppShadow.ringLap)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func ringFill(progress: Double, colors: [Color], index: Int, diameter: CGFloat) -> some View {
        // The gradient starts a cap's width behind 0° so the round start
        // cap samples the first stop, not the clamped last one. The fill is
        // inset by half a stroke, so its centre line is a stroke narrower.
        let capDegrees = RingGeometry.capDegrees(strokeWidth: Self.ringLineWidth, diameter: diameter - Self.ringLineWidth)
        return Circle()
            .inset(by: Self.ringLineWidth / 2)
            .trim(from: 0, to: isRevealed ? progress : 0)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: colors),
                    center: .center,
                    startAngle: .degrees(-capDegrees),
                    endAngle: .degrees(360 * max(progress, 0.01))
                ),
                style: StrokeStyle(lineWidth: Self.ringLineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: progress)
            .animation(revealAnimation(index: index), value: isRevealed)
    }

    /// The number rolls up from zero alongside its ring via `numericText`,
    /// so SwiftUI animates the glyphs; no per-frame timer. `remaining`
    /// says how much of the calorie budget is left, `goalMet` closes a
    /// ring the user has filled, and `progress` draws a bar for the
    /// macros that have no ring.
    private func legend(
        title: LocalizedStringKey,
        value: Int,
        target: String,
        color: Color,
        index: Int,
        overBy: Int = 0,
        remaining: Int? = nil,
        goalMet: Bool = false,
        progress: Double? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The dot rides the eyebrow's centre line at every text
            // size, rather than sitting on its baseline like a period.
            HStack(alignment: .center, spacing: Spacing.xs) {
                Circle()
                    .fill(color)
                    .frame(width: legendDotSize, height: legendDotSize)
                Text(title)
                    .font(AppFont.eyebrow)
                    .foregroundStyle(AppColor.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                let shown = isRevealed ? value : 0
                Text(String(shown))
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .fixedSize()
                    .contentTransition(.numericText(value: Double(shown)))
                    .animation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion), value: value)
                    .animation(revealAnimation(index: index), value: isRevealed)
                Text(target)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if goalMet && isRevealed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(AppColor.success)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Goal reached")
                }
            }
            .appAnimation(AppAnimation.springSnappy, value: goalMet)
            if overBy > 0 && targets.calories > 0 {
                Text("+\(overBy) over")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            } else if let remaining, remaining > 0 {
                Text("\(remaining) kcal left")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            if let progress {
                GlassProgressBar(progress: progress, height: 4, gradient: [color])
                    .padding(.top, Spacing.xxs)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Quick-add amounts, chosen per unit so both systems get round
    /// numbers. Metric amounts convert to exact (fractional) ounces, so
    /// "+1 L" records 1000 mL, not the 1005 mL a whole 34 oz came to.
    private var quickAddOptions: [QuickAddOption] {
        unit == .metric
            ? [.init(label: "+250 mL", millilitres: 250),
               .init(label: "+500 mL", millilitres: 500),
               .init(label: "+1 L", millilitres: 1_000)]
            : [.init(label: "+8 oz", fluidOunces: 8),
               .init(label: "+16 oz", fluidOunces: 16),
               .init(label: "+32 oz", fluidOunces: 32)]
    }

    private struct QuickAddOption: Identifiable {
        let label: String
        let fluidOunces: Double
        var id: String { label }

        init(label: String, fluidOunces: Double) {
            self.label = label
            self.fluidOunces = fluidOunces
        }

        init(label: String, millilitres: Double) {
            self.init(label: label, fluidOunces: LifestyleDataLogic.fluidOunces(millilitres: millilitres))
        }

        /// The amount in the unit the label is written in, for VoiceOver.
        func spokenAmount(in unit: MeasurementUnit) -> Int {
            unit == .metric
                ? LifestyleDataLogic.millilitres(fluidOunces: fluidOunces)
                : Int(fluidOunces.rounded())
        }
    }

    private func quickAddButton(_ option: QuickAddOption) -> some View {
        Button {
            Haptics.impact(.light)
            selectedWaterAmount = option.fluidOunces
            onAddWater(option.fluidOunces)
        } label: {
            HStack(spacing: Spacing.xs) {
                // Only the drop keeps the water data colour: the chips are
                // secondary to Log food, so their fill and label stay neutral.
                Image(systemName: "drop.fill")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.macroWaterInk)
                    .completionPulse(trigger: waterFeedback, isActive: selectedWaterAmount == option.fluidOunces)
                Text(option.label)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            // ScalePressStyle owns the press; interactive glass would run a
            // second, competing scale on iOS 26.
            .glassControl(
                .capsule,
                tint: AppColor.surfaceElevated.opacity(0.3),
                border: AppColor.glassBorder,
                interactive: false
            )
            .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.94))
        .accessibilityLabel("Add \(option.spokenAmount(in: unit)) \(unit.volumeSpokenUnit) of water")
        .accessibilityAddTraits(.isButton)
    }

    private func undoWaterButton(_ undo: @escaping () -> Void) -> some View {
        Button(action: undo) {
            Image(systemName: "arrow.uturn.backward")
                .font(AppFont.scaled(11, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .glassControl(
                    .capsule,
                    tint: AppColor.surfaceElevated.opacity(0.3),
                    border: AppColor.glassBorder,
                    interactive: false
                )
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.94))
        .accessibilityLabel("Undo last water")
    }

    private var accessibilitySummary: String {
        let water = LifestyleDataLogic.displayedWater(consumed, unit: unit)
        let waterTarget = waterTargetDisplay
        // No targets yet: read the intake alone rather than "of 0".
        guard targets.calories > 0 else {
            return String(
                localized: "Calories \(consumed.caloriesKcal). Protein \(consumed.proteinG) grams. Water \(water) of \(waterTarget) \(unit.volumeSpokenUnit).",
                comment: "VoiceOver summary of the day's calories, protein and water when no nutrition targets are set."
            )
        }
        return String(
            localized: "Calories \(consumed.caloriesKcal) of \(targets.calories). Protein \(consumed.proteinG) of \(targets.proteinG) grams. Water \(water) of \(waterTarget) \(unit.volumeSpokenUnit).",
            comment: "VoiceOver summary of the day's calories, protein and water against targets."
        )
    }
}
