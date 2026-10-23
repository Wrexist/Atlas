import SwiftUI

/// Bevel-style biometric tile: icon + value + unit + status pill on
/// the left, vertical personal-range indicator on the right.
/// Lightweight so a 2-column grid of them stays scannable —
/// hierarchy comes from the status pill colour, not from card
/// chrome.
struct BiometricCard: View {
    let icon: String
    let label: LocalizedStringKey
    let value: String
    let unit: String
    /// The unit as VoiceOver should say it ("beats per minute", not "b p m").
    let spokenUnit: LocalizedStringKey
    let sample: HealthRangeService.Sample?
    var onTap: (() -> Void)?

    /// Only a real button when there's somewhere to go — a Button with
    /// no action reads to VoiceOver as a control that does nothing.
    @ViewBuilder
    var body: some View {
        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(ScalePressStyle())
                .accessibilityElement(children: .combine)
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                    Text(label)
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .accessibilityLabel(spokenUnit)
                }

                statusPill

                // An old reading matters more than an early range.
                if let caption = sample?.staleCaption() ?? sample?.confidenceCaption {
                    Text(caption)
                        .font(AppFont.badgeSmall)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let sample {
                // The status pill already speaks the range position.
                PersonalRangeIndicator(
                    fraction: sample.positionInRange,
                    tint: tint(for: sample)
                )
                .accessibilityHidden(true)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    // MARK: - Status pill

    private var statusPill: some View {
        HStack(spacing: 4) {
            if let sample {
                Image(systemName: statusIcon(for: sample))
                    .font(AppFont.scaled(11, weight: .heavy))
                    .accessibilityHidden(true)
                Text(statusLabel(for: sample))
                    .font(AppFont.scaled(11, weight: .heavy))
                    .accessibilityLabel(spokenStatus(for: sample))
            } else {
                Image(systemName: "minus")
                    .font(AppFont.scaled(11, weight: .heavy))
                    .accessibilityHidden(true)
                Text("No data")
                    .font(AppFont.scaled(11, weight: .heavy))
            }
        }
        .foregroundStyle(sample.map { tint(for: $0) } ?? AppColor.textSecondary)
    }

    private func statusLabel(for sample: HealthRangeService.Sample) -> LocalizedStringKey {
        switch sample.status {
        case .lower:  return String(localized: "Lower")
        case .normal: return String(localized: "Normal")
        case .higher: return String(localized: "Higher")
        }
    }

    private func spokenStatus(for sample: HealthRangeService.Sample) -> LocalizedStringKey {
        switch sample.status {
        case .lower:  return "Below your usual range"
        case .normal: return "Within your usual range"
        case .higher: return "Above your usual range"
        }
    }

    private func statusIcon(for sample: HealthRangeService.Sample) -> String {
        switch sample.status {
        case .lower:  return "arrow.down.circle.fill"
        case .normal: return "checkmark.circle.fill"
        case .higher: return "arrow.up.circle.fill"
        }
    }

    /// Direction-aware tint. For a "higher is better" metric like
    /// HRV, "Higher" reads green and "Lower" reads blue/cautionary.
    /// For "lower is better" RHR, the colours flip — lower is the
    /// desirable state.
    private func tint(for sample: HealthRangeService.Sample) -> Color {
        switch (sample.direction, sample.status) {
        case (.higherIsBetter, .higher), (.lowerIsBetter, .lower):
            return AppColor.success
        case (_, .normal):
            return AppColor.success
        case (.higherIsBetter, .lower), (.lowerIsBetter, .higher):
            return AppColor.belowRange             // soft blue — cautionary, not danger
        case (.neutral, _):
            return AppColor.accentLight
        }
    }
}

#Preview {
    let hrvSample = HealthRangeService.Sample(
        latest: 58, p10: 35, p25: 42, p75: 60, p90: 70, direction: .higherIsBetter
    )
    let rhrSample = HealthRangeService.Sample(
        latest: 53, p10: 50, p25: 55, p75: 65, p90: 70, direction: .lowerIsBetter
    )
    let emergingSleepSample = HealthRangeService.Sample(
        latest: 7.2, p10: 6.0, p25: 6.5, p75: 7.8, p90: 8.3, direction: .higherIsBetter,
        confidence: .emergingBaseline
    )
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack {
            HStack(spacing: Spacing.sm) {
                BiometricCard(icon: "waveform.path.ecg", label: "HRV", value: "58", unit: "ms", spokenUnit: "milliseconds", sample: hrvSample)
                BiometricCard(icon: "heart.fill", label: "RHR", value: "53", unit: "bpm", spokenUnit: "beats per minute", sample: rhrSample)
            }
            HStack(spacing: Spacing.sm) {
                BiometricCard(icon: "bed.double.fill", label: "Sleep", value: "7.2", unit: "h", spokenUnit: "hours", sample: emergingSleepSample)
            }
            HStack(spacing: Spacing.sm) {
                BiometricCard(icon: "bed.double.fill", label: "Sleep", value: "7.8", unit: "h", spokenUnit: "hours", sample: nil)
                BiometricCard(icon: "waveform.path.ecg", label: "HRV", value: "—", unit: "", spokenUnit: "", sample: nil)
            }
        }
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
