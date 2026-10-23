import SwiftUI

struct ProtocolCard: View {
    let protocol_: PeptideProtocol

    /// Wash-out day and length while an active protocol is between
    /// cycles — the on-cycle week, days left and bar would otherwise
    /// sit frozen at "Week 8 of 8 · 0d left · 100%" for the whole break.
    private var washout: (status: CyclePhaseEngine.Status, day: Int, total: Int)? {
        guard protocol_.status == .active, protocol_.washoutWeeks > 0 else { return nil }
        let status = CyclePhaseEngine.status(for: protocol_)
        guard case .washout(let day, let total) = status.phase else { return nil }
        return (status, day, total)
    }

    var body: some View {
        GlassCard(tinted: protocol_.status == .active) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(protocol_.name)
                            .font(AppFont.title3)
                            .foregroundStyle(AppColor.textPrimary)

                        HStack(spacing: Spacing.sm) {
                            StatusBadge(status: protocol_.status)

                            Text("^[\(protocol_.peptides.count) peptide](inflect: true)")
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }

                    Spacer()

                    if let washout {
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text("Wash-out")
                                .font(AppFont.headline)
                                .foregroundStyle(CyclePhaseEngine.tint(for: washout.status.phase))
                            Text("Day \(washout.day) of \(washout.total)")
                                .font(AppFont.caption2)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    } else if protocol_.status == .active {
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text("Week \(protocol_.weekNumber)")
                                .font(AppFont.headline)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(AppColor.accentLight)
                            Text("of \(protocol_.cycleLengthWeeks)")
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }
                }

                if let washout {
                    GlassProgressBar(
                        progress: washout.status.phaseProgress,
                        gradient: [CyclePhaseEngine.tint(for: washout.status.phase)]
                    )
                } else if protocol_.status == .active {
                    CycleProgressBar(protocol_: protocol_)
                }

                // Peptide icons row
                HStack(spacing: -6) {
                    ForEach(protocol_.peptides.prefix(4)) { peptide in
                        ZStack {
                            Circle()
                                .fill(peptide.category.color.opacity(0.2))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Circle()
                                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                }

                            Image(systemName: peptide.imageSystemName)
                                .font(AppFont.scaled(11))
                                .foregroundStyle(peptide.category.color)
                        }
                    }

                    if protocol_.peptides.count > 4 {
                        Text("+\(protocol_.peptides.count - 4)")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.leading, Spacing.sm)
                    }

                    Spacer()

                    if let washout {
                        Text("\(CyclePhaseEngine.daysUntilPhaseEnd(washout.status))d to next cycle")
                            .font(AppFont.caption2)
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textSecondary)
                    } else if protocol_.status == .active {
                        Text("\(protocol_.daysRemaining)d left")
                            .font(AppFont.caption2)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: protocol_.cycleProgress)
        // The peptide avatars are a visual summary of the count already
        // announced above, so they're hidden and the card reads as one item.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [protocol_.name, protocol_.status.displayName]
        parts.append(protocol_.peptides.count == 1 ? String(localized: "1 peptide") : String(localized: "\(protocol_.peptides.count) peptides"))
        if let washout {
            parts.append(String(localized: "wash-out, day \(washout.day) of \(washout.total)"))
            parts.append(String(localized: "\(CyclePhaseEngine.daysUntilPhaseEnd(washout.status)) days until the next cycle"))
        } else if protocol_.status == .active {
            parts.append(String(localized: "week \(protocol_.weekNumber) of \(protocol_.cycleLengthWeeks)"))
            parts.append(String(localized: "\(protocol_.daysRemaining) days left"))
        }
        return parts.joined(separator: ", ")
    }
}

struct StatusBadge: View {
    let status: ProtocolStatus

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: status.iconName)
                .font(AppFont.badge)
                .contentTransition(.symbolEffect(.replace))
            Text(status.displayName)
                .font(AppFont.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background {
            Capsule()
                .fill(status.color.opacity(0.15))
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.md) {
            ProtocolCard(protocol_: MockProtocols.recoveryStack)
            ProtocolCard(protocol_: MockProtocols.immuneBoost)
            ProtocolCard(protocol_: MockProtocols.cognitiveEnhancement)
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
