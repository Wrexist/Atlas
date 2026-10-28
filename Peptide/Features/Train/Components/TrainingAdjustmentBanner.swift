import SwiftUI

/// Says when today's suggestions are lowered for low recovery or a deload
/// week, and lets the user go back to the normal ones (and return).
struct TrainingAdjustmentBanner: View {
    let adjustment: ProgressionEngine.Adjustment
    let readiness: ReadinessEngine.Reason
    let deload: DeloadEngine.Reason?
    let isApplied: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: adjustment == .deload ? "arrow.down.circle.fill" : "battery.25percent")
                .foregroundStyle(AppColor.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                if let detail {
                    Text(detail)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.xs)
            Button {
                Haptics.selection()
                onToggle()
            } label: {
                Text(toggleTitle)
                    .font(AppFont.callout.weight(.semibold))
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.accentPrimary)
            .accessibilityHint(Text("Switches between lowered and normal suggestions"))
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
    }

    /// Keys, not formatted strings: the literal "%" must not pass through
    /// a format call.
    private var title: LocalizedStringKey {
        switch (adjustment, isApplied) {
        case (.lowRecovery, true): return "Low recovery today: suggestions lowered 10%"
        case (.lowRecovery, false): return "Low recovery today: normal suggestions"
        case (.deload, true): return "Deload week: suggestions at about 60% volume"
        case (.deload, false): return "Deload week suggested: normal suggestions"
        }
    }

    private var toggleTitle: LocalizedStringKey {
        isApplied ? "Use normal" : "Use lighter"
    }

    private var detail: String? {
        if adjustment == .deload, let deload {
            switch deload {
            case .risingVolume:
                return String(localized: "Your training volume has risen \(DeloadEngine.risingWeeks) weeks in a row.")
            case .stalledLifts:
                return String(localized: "Most of your lifts have stalled over their last few sessions.")
            }
        }
        switch readiness {
        case .hrvBelowBaseline: return String(localized: "Your HRV is well below your baseline.")
        case .restingHeartRateAboveBaseline: return String(localized: "Your resting heart rate is above your baseline.")
        case .shortSleep: return String(localized: "You slept under \(Int(ReadinessEngine.shortSleepHours)) hours last night.")
        case .hrvAboveBaseline, .typical, .noData: return nil
        }
    }
}
