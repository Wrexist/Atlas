import SwiftUI

/// Nutrition hero on the Lifestyle tab. Three Apple-Activity-style
/// concentric rings render Calories (outer), Protein (middle), and
/// Water (inner) progress in a single glass card, with a legend row
/// underneath that exposes the live values + targets. Water quick-add
/// chips sit at the bottom so the most common action (logging a glass
/// of water) stays one tap from the card.
struct MacroSummaryRow: View {
    let targets: NutritionTargets
    let consumed: DailyConsumption
    /// Per-meal-category breakdown driving the outer calorie ring's
    /// segmentation. Optional — when nil, the ring falls back to the
    /// monochrome render so callers that haven't been upgraded
    /// (older snapshots, previews, tests) keep working unchanged.
    let breakdown: LifestyleDataLogic.CategoryBreakdown?
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
    @State private var waterFeedback = 0
    @State private var selectedWaterAmount: Double?
    /// Per-view-lifetime, so a tab switch back doesn't replay the fill.
    @State private var hasAppeared = false

    init(
        targets: NutritionTargets,
        consumed: DailyConsumption,
        breakdown: LifestyleDataLogic.CategoryBreakdown? = nil,
        unit: MeasurementUnit,
        onAddWater: @escaping (Double) -> Void,
        onUndoWater: (() -> Void)? = nil
    ) {
        self.targets = targets
        self.consumed = consumed
        self.breakdown = breakdown
        self.unit = unit
        self.onAddWater = onAddWater
        self.onUndoWater = onUndoWater
    }

    private static let waterTargetOz = TodayChecklistEngine.waterTargetOz

    private var caloriesProgress: Double {
        guard targets.calories > 0 else { return 0 }
        return min(1, Double(consumed.caloriesKcal) / Double(targets.calories))
    }

    private var proteinProgress: Double {
        guard targets.proteinG > 0 else { return 0 }
        return min(1, Double(consumed.proteinG) / Double(targets.proteinG))
    }

    private var waterProgress: Double {
        min(1, consumed.waterFluidOunces / Double(Self.waterTargetOz))
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
            HStack(alignment: .top, spacing: Spacing.lg) {
                ringStack
                    .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    legend(
                        title: "Calories",
                        value: consumed.caloriesKcal,
                        target: "/\(targets.calories) kcal",
                        // The outer ring is split by meal colour, so a single
                        // accent dot would name a colour the ring doesn't use.
                        color: breakdown == nil ? AppColor.accentPrimary : AppColor.textTertiary,
                        index: 0,
                        overBy: max(0, consumed.caloriesKcal - targets.calories)
                    )
                    legend(
                        title: "Protein",
                        value: consumed.proteinG,
                        target: "/\(targets.proteinG) g",
                        color: AppColor.macroProtein,
                        index: 1
                    )
                    legend(
                        title: "Water",
                        value: LifestyleDataLogic.displayedWater(consumed, unit: unit),
                        target: "/\(unit.volumeLabel(Self.waterTargetOz))",
                        color: AppColor.macroWaterLight,
                        index: 2
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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

    private var ringStack: some View {
        ZStack {
            // Outer ring: calories. When a breakdown is available,
            // segment it by meal category so the user can read what
            // they ate at a glance — breakfast slice, lunch slice,
            // etc. Falls back to the monochrome accent ring when no
            // breakdown is supplied so legacy callers (and previews)
            // keep working unchanged.
            if let breakdown {
                SegmentedCalorieRing(
                    breakdown: breakdown,
                    target: targets.calories,
                    lineWidth: 12
                )
                .frame(width: 132, height: 132)
            } else {
                ringTrack(diameter: 132, lineWidth: 12)
                ringFill(
                    diameter: 132,
                    lineWidth: 12,
                    progress: caloriesProgress,
                    colors: [AppColor.accentLight, AppColor.accentPrimary],
                    index: 0
                )
            }

            ringTrack(diameter: 96, lineWidth: 12)
            ringFill(
                diameter: 96,
                lineWidth: 12,
                progress: proteinProgress,
                colors: [AppColor.macroProteinLight, AppColor.macroProtein],
                index: 1
            )

            ringTrack(diameter: 60, lineWidth: 12)
            ringFill(
                diameter: 60,
                lineWidth: 12,
                progress: waterProgress,
                colors: [AppColor.macroWaterLight, AppColor.macroWater],
                index: 2
            )
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private func ringTrack(diameter: CGFloat, lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(AppColor.surfaceElevated.opacity(0.65), lineWidth: lineWidth)
            .frame(width: diameter, height: diameter)
    }

    private func ringFill(diameter: CGFloat, lineWidth: CGFloat, progress: Double, colors: [Color], index: Int) -> some View {
        Circle()
            .trim(from: 0, to: isRevealed ? progress : 0)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: colors + [colors.first ?? .clear]),
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .frame(width: diameter, height: diameter)
            .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: progress)
            .animation(revealAnimation(index: index), value: isRevealed)
    }

    /// The number rolls up from zero alongside its ring via `numericText`,
    /// so SwiftUI animates the glyphs; no per-frame timer.
    private func legend(title: LocalizedStringKey, value: Int, target: String, color: Color, index: Int, overBy: Int = 0) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(AppFont.eyebrow)
                    .foregroundStyle(AppColor.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    let shown = isRevealed ? value : 0
                    Text(String(shown))
                        .font(AppFont.scaled(20, weight: .semibold, design: .rounded))
                        .foregroundStyle(overBy > 0 && targets.calories > 0 ? AppColor.warning : AppColor.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shown)))
                        .animation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion), value: value)
                        .animation(revealAnimation(index: index), value: isRevealed)
                    Text(target)
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                        .monospacedDigit()
                }
                if overBy > 0 && targets.calories > 0 {
                    Text("+\(overBy) over")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.warning)
                        .monospacedDigit()
                }
            }
        }
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
                Image(systemName: "drop.fill")
                    .font(AppFont.scaled(11, weight: .bold))
                    .completionPulse(trigger: waterFeedback, isActive: selectedWaterAmount == option.fluidOunces)
                Text(option.label)
                    .font(AppFont.scaled(11, weight: .semibold))
            }
            .foregroundStyle(AppColor.macroWaterLight)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .glassControl(
                .capsule,
                tint: AppColor.macroWater.opacity(0.18),
                border: AppColor.macroWater.opacity(0.32)
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
                .padding(.vertical, 8)
                .glassControl(
                    .capsule,
                    tint: AppColor.surfaceElevated.opacity(0.3),
                    border: AppColor.glassBorder
                )
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.94))
        .accessibilityLabel("Undo last water")
    }

    private var accessibilitySummary: String {
        let calorieLine = "Calories \(consumed.caloriesKcal) of \(targets.calories)"
        let proteinLine = "Protein \(consumed.proteinG) of \(targets.proteinG) grams"
        let waterLine = "Water \(LifestyleDataLogic.displayedWater(consumed, unit: unit)) of \(unit.volumeValue(Self.waterTargetOz)) \(unit.volumeSpokenUnit)"
        return "\(calorieLine). \(proteinLine). \(waterLine)."
    }
}
