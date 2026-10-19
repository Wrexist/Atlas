import SwiftUI

/// "What's driving it": every signal the estimate used, the years it is
/// pulling, and the reading behind it against its reference. Bars diverge
/// from a centre line — left is younger, right is older — on one shared
/// scale, so a long bar always means a big pull.
struct BioAgeDriversCard: View {
    let estimate: PerformanceAgeEngine.Estimate
    let unit: MeasurementUnit

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    /// The widest any single signal can swing, so bars share one scale.
    private static let scaleYears: Double = PerformanceAgeEngine.Driver.Kind.allCases
        .map(\.maxSwingYears).max() ?? 3

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            BiologySectionHeader(
                title: "What's driving it",
                subtitle: "How many years each signal adds or takes off."
            )

            GlassCard {
                VStack(spacing: Spacing.lg) {
                    ForEach(Array(estimate.drivers.enumerated()), id: \.element.id) { index, driver in
                        row(driver, index: index)
                    }
                    legend
                }
            }
        }
        .onAppear {
            guard !grown else { return }
            withAnimation(reduceMotion ? nil : AppAnimation.springSmooth) { grown = true }
        }
    }

    private func row(_ driver: PerformanceAgeEngine.Driver, index: Int) -> some View {
        let kind = driver.kind
        let shownDelta = grown ? driver.deltaYears : 0
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: kind.icon)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 32, height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                            .fill(kind.tint.opacity(0.15))
                    }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(kind.displayName)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    if let detailText = detail(for: driver) {
                        Text(detailText)
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: Spacing.sm)

                Text(BioAgeFormat.years(shownDelta))
                    .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                    .foregroundStyle(tint(for: driver.deltaYears))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: shownDelta))
            }

            DivergingBar(
                fraction: grown ? min(1, abs(driver.deltaYears) / Self.scaleYears) : 0,
                towardOlder: driver.deltaYears > 0,
                tint: tint(for: driver.deltaYears)
            )
        }
        .animation(
            reduceMotion ? nil : AppAnimation.springSmooth.delay(Double(min(index, 8)) * AppAnimation.staggerDelay * 2),
            value: grown
        )
        .animation(reduceMotion ? nil : AppAnimation.springSmooth, value: driver.deltaYears)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([kind.displayName, detail(for: driver)].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityValue(Text(BioAgeFormat.spokenYears(driver.deltaYears)))
    }

    /// "48 ms · Typical for your age: 41 ms"
    private func detail(for driver: PerformanceAgeEngine.Driver) -> String? {
        guard let value = driver.value else { return nil }
        let reading = driver.kind.formattedValue(value, unit: unit)
        guard let reference = driver.reference else { return reading }
        return "\(reading) · \(driver.kind.formattedReference(reference, unit: unit))"
    }

    private var legend: some View {
        HStack {
            Label("Younger", systemImage: "arrow.left")
            Spacer()
            Label("Older", systemImage: "arrow.right")
                .labelStyle(TrailingIconLabelStyle())
        }
        .font(AppFont.scaled(11, weight: .semibold))
        .foregroundStyle(AppColor.textTertiary)
        .accessibilityHidden(true)
    }

    private func tint(for delta: Double) -> Color {
        if abs(delta) < 0.05 { return AppColor.textSecondary }
        return delta < 0 ? AppColor.positive : AppColor.negative
    }
}

/// A hairline track with a centre tick; the fill grows from the centre
/// toward "younger" (left) or "older" (right).
private struct DivergingBar: View {
    let fraction: Double
    let towardOlder: Bool
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let length = half * CGFloat(fraction)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColor.glassBorder)
                    .frame(height: 4)
                Capsule()
                    .fill(tint)
                    .frame(width: length, height: 4)
                    .offset(x: towardOlder ? half : half - length)
                Capsule()
                    .fill(AppColor.textTertiary)
                    .frame(width: 2, height: 12)
                    .offset(x: half - 1)
            }
            .frame(height: 12)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xs) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    ScrollView {
        BioAgeDriversCard(
            estimate: .init(
                biologicalAge: 33.2,
                confidence: 0.92,
                drivers: [
                    .init(kind: .vo2Max, deltaYears: -2.1, value: 46.4, reference: 42.2),
                    .init(kind: .hrv, deltaYears: -1.1, value: 58, reference: 40),
                    .init(kind: .sleep, deltaYears: 0.6, value: 6.9, reference: 7.5),
                    .init(kind: .steps, deltaYears: -0.4, value: 8_200, reference: 7_000),
                ]
            ),
            unit: .metric
        )
        .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
}
