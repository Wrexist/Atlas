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

    /// Animated number that drives both the ring fill and the displayed
    /// kcal count. Starts at the pre-log value, eases to the post-log
    /// value on appear, locking the user's eye to the change they
    /// just caused.
    @State private var displayed: Double = 0

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .stroke(AppColor.surfaceSecondary.opacity(0.8), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: ringTrim)
                    .stroke(
                        AppColor.accentPrimary,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: Spacing.xxs) {
                    Text("\(Int(displayed))")
                        .font(AppFont.scaled(22, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                    Text("of \(targetCalories) kcal")
                        .font(AppFont.scaled(10, weight: .medium))
                        .foregroundStyle(AppColor.textTertiary)
                        .monospacedDigit()
                }
            }
            .frame(width: 110, height: 110)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today's calories: \(totalCalories) of \(targetCalories)")
            .accessibilityValue("\(Int(ringTrim * 100)) percent")

            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .accessibilityHidden(true)
                Text("\(deltaCalories) kcal · \(productName)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .onAppear {
            // Start at "before". Animate to "after" so the eye sees
            // the ring fill in and the number tick up in sync.
            displayed = Double(max(0, totalCalories - deltaCalories))
            withAnimation(.easeOut(duration: 1.1)) {
                displayed = Double(totalCalories)
            }
        }
    }

    private var ringTrim: CGFloat {
        guard targetCalories > 0 else { return 0 }
        // Cap at 1.0 so going over target still shows a full ring
        // (rather than wrapping past the start and looking broken).
        // The number underneath still shows the actual value, so an
        // over-target day stays visible as a number even when the
        // ring is at max.
        return CGFloat(min(1.0, displayed / Double(targetCalories)))
    }
}
