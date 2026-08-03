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
    let onAddWater: (Int) -> Void

    init(
        targets: NutritionTargets,
        consumed: DailyConsumption,
        breakdown: LifestyleDataLogic.CategoryBreakdown? = nil,
        onAddWater: @escaping (Int) -> Void
    ) {
        self.targets = targets
        self.consumed = consumed
        self.breakdown = breakdown
        self.onAddWater = onAddWater
    }

    private static let waterTargetOz: Int = 100

    private var caloriesProgress: Double {
        guard targets.calories > 0 else { return 0 }
        return min(1, Double(consumed.caloriesKcal) / Double(targets.calories))
    }

    private var proteinProgress: Double {
        guard targets.proteinG > 0 else { return 0 }
        return min(1, Double(consumed.proteinG) / Double(targets.proteinG))
    }

    private var waterProgress: Double {
        min(1, Double(consumed.waterOz) / Double(Self.waterTargetOz))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.lg) {
                ringStack
                    .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    legend(
                        title: "Calories",
                        value: "\(consumed.caloriesKcal)",
                        target: "/\(targets.calories) kcal",
                        color: AppColor.accentPrimary
                    )
                    legend(
                        title: "Protein",
                        value: "\(consumed.proteinG)",
                        target: "/\(targets.proteinG) g",
                        color: AppColor.macroProtein
                    )
                    legend(
                        title: "Water",
                        value: "\(consumed.waterOz)",
                        target: "/\(Self.waterTargetOz) oz",
                        color: AppColor.macroWaterLight
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .overlay(AppColor.glassBorder)

            HStack(spacing: Spacing.sm) {
                quickAddButton(label: "+250 mL", oz: 8)
                quickAddButton(label: "+500 mL", oz: 17)
                quickAddButton(label: "+1 L", oz: 34)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
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
                    colors: [AppColor.accentLight, AppColor.accentPrimary]
                )
            }

            ringTrack(diameter: 96, lineWidth: 12)
            ringFill(
                diameter: 96,
                lineWidth: 12,
                progress: proteinProgress,
                colors: [AppColor.macroProteinLight, AppColor.macroProtein]
            )

            ringTrack(diameter: 60, lineWidth: 12)
            ringFill(
                diameter: 60,
                lineWidth: 12,
                progress: waterProgress,
                colors: [AppColor.macroWaterLight, AppColor.macroWater]
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

    private func ringFill(diameter: CGFloat, lineWidth: CGFloat, progress: Double, colors: [Color]) -> some View {
        Circle()
            .trim(from: 0, to: progress)
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
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: progress)
    }

    private func legend(title: LocalizedStringKey, value: String, target: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(AppFont.scaled(20, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(target)
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func quickAddButton(label: LocalizedStringKey, oz: Int) -> some View {
        Button {
            Haptics.impact(.light)
            onAddWater(oz)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(AppFont.scaled(11, weight: .bold))
                Text(label)
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
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.94))
        .accessibilityLabel("Add \(oz) ounces of water")
        .accessibilityAddTraits(.isButton)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
            .fill(AppColor.surfaceSecondary.opacity(0.6))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.accentPrimary.opacity(0.08),
                                Color.clear,
                            ],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
            }
    }

    private var accessibilitySummary: String {
        let calorieLine = "Calories \(consumed.caloriesKcal) of \(targets.calories)"
        let proteinLine = "Protein \(consumed.proteinG) of \(targets.proteinG) grams"
        let waterLine = "Water \(consumed.waterOz) of \(Self.waterTargetOz) ounces"
        return "\(calorieLine). \(proteinLine). \(waterLine)."
    }
}
