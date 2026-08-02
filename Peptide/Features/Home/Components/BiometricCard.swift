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
    let sample: HealthRangeService.Sample?
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                        Text(label)
                            .font(AppFont.scaled(12, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(AppFont.scaled(22, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(unit)
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    statusPill
                }

                Spacer(minLength: 0)

                if let sample {
                    PersonalRangeIndicator(
                        fraction: sample.positionInRange,
                        tint: tint(for: sample)
                    )
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Status pill

    private var statusPill: some View {
        HStack(spacing: 4) {
            if let sample {
                Image(systemName: statusIcon(for: sample))
                    .font(AppFont.scaled(10, weight: .heavy))
                Text(statusLabel(for: sample))
                    .font(AppFont.scaled(11, weight: .heavy))
            } else {
                Image(systemName: "minus")
                    .font(AppFont.scaled(10, weight: .heavy))
                Text("No data")
                    .font(AppFont.scaled(11, weight: .heavy))
            }
        }
        .foregroundStyle(sample.map { tint(for: $0) } ?? AppColor.textSecondary)
    }

    private func statusLabel(for sample: HealthRangeService.Sample) -> String {
        switch sample.status {
        case .lower:  return "Lower"
        case .normal: return "Normal"
        case .higher: return "Higher"
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
            return AppColor.macroWaterLight        // soft blue — cautionary, not danger
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
    return ZStack {
        AppColor.background.ignoresSafeArea()
        VStack {
            HStack(spacing: Spacing.sm) {
                BiometricCard(icon: "waveform.path.ecg", label: "HRV", value: "58", unit: "ms", sample: hrvSample)
                BiometricCard(icon: "heart.fill", label: "RHR", value: "53", unit: "bpm", sample: rhrSample)
            }
            HStack(spacing: Spacing.sm) {
                BiometricCard(icon: "bed.double.fill", label: "Sleep", value: "7.8", unit: "h", sample: nil)
                BiometricCard(icon: "waveform.path.ecg", label: "HRV", value: "—", unit: "", sample: nil)
            }
        }
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
