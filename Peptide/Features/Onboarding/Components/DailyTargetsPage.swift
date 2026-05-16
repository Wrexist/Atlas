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
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.md) {
                Text("Your daily targets")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Calculated from your stats. Tweak any time on the Meals tab.")
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

    /// Cool, harmonised macro accents — slightly desaturated so the card
    /// reads as a unified system rather than four random highlight chips.
    private let proteinTint = Color(hex: 0xF472B6)   // rose-400
    private let carbsTint   = Color(hex: 0xFB923C)   // orange-400
    private let fatTint     = Color(hex: 0xFBBF24)   // amber-400
    private let fiberTint   = Color(hex: 0x60A5FA)   // blue-400

    var body: some View {
        GlassCard(cornerRadius: Spacing.cardCornerRadius, tinted: true) {
            VStack(spacing: Spacing.xl) {
                calorieBlock

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Spacing.md),
                        GridItem(.flexible(), spacing: Spacing.md),
                    ],
                    spacing: Spacing.md
                ) {
                    macroTile(label: "Protein", grams: targets?.proteinG, tint: proteinTint)
                    macroTile(label: "Carbs",   grams: targets?.carbsG,   tint: carbsTint)
                    macroTile(label: "Fat",     grams: targets?.fatG,     tint: fatTint)
                    macroTile(label: "Fiber",   grams: targets?.fiberG,   tint: fiberTint)
                }
            }
        }
    }

    private var calorieBlock: some View {
        VStack(spacing: 4) {
            Text(targets.map { "\($0.calories)" } ?? "—")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.accentLight, AppColor.accentPrimary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .contentTransition(.numericText())
                .animation(AppAnimation.springSmooth, value: targets?.calories)

            Text("kcal / day")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
                .tracking(1.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func macroTile(label: LocalizedStringKey, grams: Int?, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(grams.map { "\($0) g" } ?? "—")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(AppAnimation.springSmooth, value: grams)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
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
