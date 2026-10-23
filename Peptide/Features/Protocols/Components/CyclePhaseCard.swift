import SwiftUI

/// Visual indicator of where a protocol sits in its cycle right
/// now. Renders the phase title + day-of-phase, a progress bar
/// across the current phase, and a "next change in N days"
/// timestamp for the upcoming boundary. Drawn as a bare section of the
/// protocol header card (no surface of its own). Hidden when the protocol
/// doesn't carry wash-out info (`washoutWeeks == 0` and the
/// protocol is in its single on-cycle) since the existing
/// `CycleProgressBar` already covers that case.
struct CyclePhaseCard: View {
    let status: CyclePhaseEngine.Status

    private var labels: (title: String, subtitle: String) {
        CyclePhaseEngine.labels(for: status)
    }

    private var tint: Color { CyclePhaseEngine.tint(for: status.phase) }
    private var icon: String { CyclePhaseEngine.icon(for: status.phase) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            progressBar
            footer
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cycleNumberCopy)
                    .font(AppFont.eyebrow)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(tint)
                Text(labels.title)
                    .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(labels.subtitle)
                    .font(AppFont.scaled(13))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var cycleNumberCopy: LocalizedStringResource {
        if status.cycleNumber > 1 {
            return LocalizedStringResource(
                "Cycle \(status.cycleNumber)",
                comment: "Header eyebrow on the cycle-phase card showing 1-based cycle number for repeating protocols."
            )
        }
        return LocalizedStringResource("Phase")
    }

    private var progressBar: some View {
        GlassProgressBar(progress: barProgress, gradient: [tint])
    }

    private var barProgress: Double {
        switch status.phase {
        case .completed: 1
        case .upcoming: 0
        case .onCycle, .washout: status.phaseProgress
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(AppFont.badgeSmall)
                .foregroundStyle(AppColor.textSecondary)
            Text(footerCopy)
                .font(AppFont.badgeSmall)
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
    }

    /// Whole calendar days to the boundary, so the footer agrees with the
    /// "Day X of Y" subtitle instead of rounding to the largest unit.
    private var footerCopy: String {
        let days = CyclePhaseEngine.daysUntilPhaseEnd(status)
        switch status.phase {
        case .completed:
            return String(localized: "Tap Restart to start a new cycle.")
        case .upcoming:
            return days <= 1
                ? String(localized: "Starts tomorrow", comment: "Cycle-phase footer — the protocol starts tomorrow.")
                : String(localized: "Starts in \(days) days", comment: "Cycle-phase footer — whole days until the protocol starts (always 2 or more).")
        case .onCycle:
            return days <= 1
                ? String(localized: "Wash-out begins tomorrow", comment: "Cycle-phase footer — the wash-out opens tomorrow.")
                : String(localized: "Wash-out begins in \(days) days", comment: "Cycle-phase footer — whole days until the wash-out (always 2 or more).")
        case .washout:
            return days <= 1
                ? String(localized: "Next cycle starts tomorrow", comment: "Cycle-phase footer — the next on-cycle starts tomorrow.")
                : String(localized: "Next cycle starts in \(days) days", comment: "Cycle-phase footer — whole days until the next on-cycle (always 2 or more).")
        }
    }

    private var accessibilityLabel: String {
        "\(labels.title). \(labels.subtitle). \(footerCopy)"
    }
}
