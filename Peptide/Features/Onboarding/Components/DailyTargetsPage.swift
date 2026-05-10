import SwiftUI

/// Shows the calorie + macro targets derived from the previous step's body
/// stats. Numbers update live if the user goes back, edits, and returns —
/// the calculation is a pure function of `metrics`. Persisted to the
/// profile when the user completes onboarding.
///
/// Numbers are reference targets only; the disclaimer makes that explicit.
struct DailyTargetsPage: View {
    let metrics: BodyMetrics

    var body: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("Your daily targets")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Calculated from your stats. Tweak any time on the Lifestyle tab.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            DailyTargetsCard(targets: NutritionMath.dailyTargets(for: metrics))

            Text("For reference only. Not medical advice.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Reusable presentation: large calorie value on top, 2×2 macro grid
/// below. Used by the onboarding step and the Lifestyle tab.
struct DailyTargetsCard: View {
    let targets: NutritionTargets?

    var body: some View {
        GlassCard(cornerRadius: Spacing.cardCornerRadius, tinted: true) {
            VStack(spacing: Spacing.lg) {
                calorieBlock

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Spacing.sm),
                        GridItem(.flexible(), spacing: Spacing.sm),
                    ],
                    spacing: Spacing.sm
                ) {
                    macroTile(label: "Protein", grams: targets?.proteinG, tint: AppColor.accentLight)
                    macroTile(label: "Carbs",   grams: targets?.carbsG,   tint: OnboardingTint.fatLoss)
                    macroTile(label: "Fat",     grams: targets?.fatG,     tint: OnboardingTint.antiAging)
                    macroTile(label: "Fiber",   grams: targets?.fiberG,   tint: OnboardingTint.muscleRecovery)
                }
            }
        }
    }

    private var calorieBlock: some View {
        VStack(spacing: 2) {
            Text(targets.map { "\($0.calories)" } ?? "—")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.accentPrimary)
                .contentTransition(.numericText())
                .animation(AppAnimation.springSmooth, value: targets?.calories)

            Text("kcal / day")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity)
    }

    private func macroTile(label: LocalizedStringKey, grams: Int?, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(grams.map { "\($0) g" } ?? "—")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(AppAnimation.springSmooth, value: grams)

            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 0.5)
                }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        DailyTargetsPage(
            metrics: BodyMetrics(
                weightKg: 75,
                heightCm: 180,
                age: 30,
                sex: .male,
                activityLevel: .moderate,
                unit: .metric
            )
        )
        .padding(.horizontal, Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
