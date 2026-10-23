import SwiftUI

/// "Data behind it": how sure the estimate is, which signals it counted,
/// and — for each one it couldn't — the single thing that would add it.
/// The same card serves the building state, where it is the answer to
/// "why don't I have a number yet?".
struct BioAgeCoverageCard: View {
    let inputs: PerformanceAgeEngine.Inputs
    let healthConnected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var presentKinds: [PerformanceAgeEngine.Driver.Kind] {
        PerformanceAgeEngine.drivers(for: inputs).map(\.kind)
    }

    /// Missing signals first: each carries the one step that would add
    /// it, and those steps are what this card is for. Counted ones
    /// follow, in the engine's order.
    private var orderedKinds: [PerformanceAgeEngine.Driver.Kind] {
        let present = Set(presentKinds)
        let all = PerformanceAgeEngine.Driver.Kind.allCases
        return all.filter { !present.contains($0) } + all.filter { present.contains($0) }
    }

    private var confidence: Double {
        PerformanceAgeEngine.confidenceScore(
            coverage: PerformanceAgeEngine.coverage(of: presentKinds),
            healthDataDays: inputs.healthDataDays
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            BiologySectionHeader(
                title: "Data behind it",
                subtitle: "More signals and more days make the estimate steadier."
            )

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    confidenceHeader
                    VStack(spacing: Spacing.md) {
                        ForEach(Array(orderedKinds.enumerated()), id: \.element) { index, kind in
                            signalRow(kind, index: index)
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? nil : AppAnimation.springSmooth) { appeared = true }
        }
    }

    private var confidenceHeader: some View {
        let total = PerformanceAgeEngine.Driver.Kind.allCases.count
        let ready = confidence >= PerformanceAgeEngine.minConfidence
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(ready ? BioAgeHeroSection.confidenceLabel(confidence) : String(localized: "Not enough data yet"))
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("\(presentKinds.count) of \(total) signals")
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
            GlassProgressBar(progress: confidence)
            Text("\(min(inputs.healthDataDays, PerformanceAgeEngine.windowDays)) of \(PerformanceAgeEngine.windowDays) days of heart and sleep data")
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func signalRow(_ kind: PerformanceAgeEngine.Driver.Kind, index: Int) -> some View {
        let present = presentKinds.contains(kind)
        return HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: kind.icon)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(present ? kind.tint : AppColor.textTertiary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                        .fill(present ? kind.tint.opacity(0.15) : AppColor.surfaceSecondary)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(kind.displayName)
                    .font(AppFont.scaled(16, weight: present ? .semibold : .regular))
                    .foregroundStyle(present ? AppColor.textPrimary : AppColor.textSecondary)
                if !present {
                    Text(guidance(for: kind))
                        .font(AppFont.scaled(13))
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: present ? "checkmark.circle.fill" : "circle.dashed")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(present ? AppColor.positive : AppColor.textTertiary)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : AppAnimation.staggered(index: index), value: appeared)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(present ? String(localized: "Counted") : String(localized: "Not counted")))
    }

    private func guidance(for kind: PerformanceAgeEngine.Driver.Kind) -> String {
        if kind.comesFromHealth && !healthConnected {
            return String(localized: "Connect Apple Health to include this.")
        }
        return kind.guidance
    }
}

#Preview {
    ScrollView {
        BioAgeCoverageCard(
            inputs: .init(chronologicalAge: 35, hrvMedian30d: 48, rhrMedian30d: 58,
                          sleepHoursMedian30d: 7.1, stepsMedian30d: 8_400, healthDataDays: 22),
            healthConnected: true
        )
        .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
}
