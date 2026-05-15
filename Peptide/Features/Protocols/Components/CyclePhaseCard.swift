import SwiftUI

/// Visual indicator of where a protocol sits in its cycle right
/// now. Renders the phase title + day-of-phase, a progress bar
/// across the current phase, and a "next change in N days"
/// timestamp for the upcoming boundary. Hidden when the protocol
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

    // Non-Sendable Foundation formatter; thread-safe for read-only
    // use after configuration. nonisolated(unsafe) is the Swift 6
    // escape hatch for this pattern.
    nonisolated(unsafe) private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            progressBar
            footer
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.18), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                }
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cycleNumberCopy)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(tint.opacity(0.85))
                Text(labels.title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(labels.subtitle)
                    .font(.system(size: 13))
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

    @ViewBuilder
    private var progressBar: some View {
        switch status.phase {
        case .completed:
            // Solid filled bar — protocol is done.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.45))
                .frame(height: 6)
        case .upcoming:
            // No progress yet — render the bare track.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.7))
                .frame(height: 6)
        case .onCycle, .washout:
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.7))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint)
                        .frame(width: max(6, proxy.size.width * status.phaseProgress))
                }
            }
            .frame(height: 6)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: status.phaseProgress)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
            Text(footerCopy)
                .font(.system(size: 11))
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
    }

    private var footerCopy: String {
        switch status.phase {
        case .completed:
            return String(localized: "Tap edit to start a new cycle.")
        case .upcoming:
            return String(
                localized: "Starts \(Self.relative.localizedString(for: status.phaseEndDate, relativeTo: Date()))",
                comment: "Cycle-phase footer — when the protocol starts."
            )
        case .onCycle:
            return String(
                localized: "Wash-out begins \(Self.relative.localizedString(for: status.phaseEndDate, relativeTo: Date()))",
                comment: "Cycle-phase footer — when the wash-out window opens."
            )
        case .washout:
            return String(
                localized: "Next cycle starts \(Self.relative.localizedString(for: status.phaseEndDate, relativeTo: Date()))",
                comment: "Cycle-phase footer — when the next on-cycle starts."
            )
        }
    }

    private var accessibilityLabel: String {
        "\(labels.title). \(labels.subtitle). \(footerCopy)"
    }
}
