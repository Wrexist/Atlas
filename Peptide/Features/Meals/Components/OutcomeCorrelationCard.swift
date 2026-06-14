import SwiftUI

/// "What's actually working?" surface — reads the
/// `OutcomeCorrelationEngine` headline and renders it as a single
/// declarative insight ("Your sleep is 0.7 points higher on dosing
/// days"). Hidden entirely until the engine returns a result —
/// which means enough samples in each bucket and a delta above
/// noise. The early days of an install have nothing to say, so the
/// card stays silent rather than displaying premature speculation.
///
/// The bar chart underneath shows the on-dose vs off-dose averages
/// for the headline dimension so a user who's skeptical of the
/// claim can see the math at a glance.
struct OutcomeCorrelationCard: View {
    let headline: OutcomeCorrelationEngine.DimensionCorrelation
    /// Total outcomes feeding the analysis. Surfaced in the
    /// footnote so "5 check-ins" reads as different signal than
    /// "60 check-ins".
    let sampleSize: Int

    private var dimension: OutcomeDimension { headline.dimension }
    private var delta: Double { headline.delta ?? 0 }
    private var deltaPhrase: String {
        let value = (delta * 10).rounded() / 10  // one decimal
        // %+ signs both directions — a hardcoded "+" rendered a negative
        // delta as "+-0.8".
        return String(format: "%+.1f", value)
    }

    var body: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                headerRow
                comparisonChart
                footnote
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(dimension.tint.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: dimension.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(dimension.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Pattern detected")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(dimension.tint.opacity(0.85))
                Text(headlineCopy)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(deltaPhrase)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(dimension.tint)
        }
    }

    private var headlineCopy: LocalizedStringResource {
        LocalizedStringResource(
            "Your \(dimension.displayName.lowercased()) score is higher on dosing days.",
            comment: "Outcome correlation headline. Dimension display name is lowercased to read naturally inside the sentence."
        )
    }

    /// Two stacked bars: on-dose-day average vs. off-dose-day average.
    /// Scaled so the longer bar fills the row. Lets the user
    /// validate the headline with their own eyes before trusting it.
    private var comparisonChart: some View {
        let onValue = headline.onDoseDays ?? 0
        let offValue = headline.offDoseDays ?? 0
        let scaleRef = max(onValue, offValue, 1)   // floor prevents /0
        return VStack(spacing: Spacing.xs) {
            bar(
                label: String(localized: "Dosing days"),
                value: onValue,
                fraction: onValue / scaleRef,
                count: headline.doseDayCount,
                tint: dimension.tint
            )
            bar(
                label: String(localized: "Off days"),
                value: offValue,
                fraction: offValue / scaleRef,
                count: headline.offDayCount,
                tint: AppColor.textSecondary
            )
        }
    }

    private func bar(label: String, value: Double, fraction: Double, count: Int, tint: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 84, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.55))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint.opacity(0.75))
                        .frame(width: max(6, proxy.size.width * fraction))
                }
            }
            .frame(height: 10)
            Text(String(format: "%.1f", value))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 32, alignment: .trailing)
            Text("\(count)d")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) average \(String(format: "%.1f", value)) over \(count) days")
    }

    private var footnote: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text("Based on \(sampleSize) check-ins. Correlations aren't causation — but they're a useful nudge.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppColor.textSecondary)
    }
}
