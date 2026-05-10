import SwiftUI

/// Row of consumption rings under the Meal Scan banner: a protein ring on
/// the left and a stacked Calories-bar / Water-with-quick-add panel on
/// the right. Targets come from `profile.nutritionTargets`; today's
/// consumed values come from `dataStore.consumption()`. The ring and
/// bar both animate when the consumed values change so the feedback
/// from a meal scan or water tap reads as live.
struct MacroSummaryRow: View {
    let targets: NutritionTargets
    let consumed: DailyConsumption
    let onAddWater: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            proteinCard
                .frame(maxWidth: .infinity)
            VStack(spacing: Spacing.md) {
                caloriesCard
                waterCard
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Protein

    private var proteinCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text("Protein")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
            } icon: {
                Image(systemName: "fish.fill")
                    .foregroundStyle(Color(hex: 0xEF9F27))
            }

            ZStack {
                let progress = targets.proteinG > 0
                    ? min(1, Double(consumed.proteinG) / Double(targets.proteinG))
                    : 0
                Circle()
                    .stroke(AppColor.surfaceElevated, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [AppColor.accentLight, AppColor.accentPrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)

                VStack(spacing: 0) {
                    Text("\(consumed.proteinG)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("/ \(targets.proteinG) g")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .frame(height: 130)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - Calories

    private var caloriesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text("Calories")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
            } icon: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(AppColor.accentPrimary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(consumed.caloriesKcal)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/\(targets.calories) kcal")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            GeometryReader { proxy in
                let progress = targets.calories > 0
                    ? min(1, Double(consumed.caloriesKcal) / Double(targets.calories))
                    : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.surfaceElevated)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentLight, AppColor.accentPrimary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * progress)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - Water

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text("Water")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
            } icon: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Color(red: 0.216, green: 0.541, blue: 0.866)) // #378ADD
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(consumed.waterOz)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("oz / 100 oz")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            HStack(spacing: Spacing.xs) {
                quickAddButton(label: "+250 mL", oz: 8)
                quickAddButton(label: "+500 mL", oz: 17)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func quickAddButton(label: LocalizedStringKey, oz: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onAddWater(oz)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background {
                    Capsule()
                        .fill(AppColor.accentPrimary.opacity(0.15))
                        .overlay {
                            Capsule().strokeBorder(AppColor.accentPrimary.opacity(0.35), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
            .fill(AppColor.surfaceSecondary.opacity(0.6))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
            }
    }
}
