import SwiftUI

struct ProtocolCard: View {
    let protocol_: PeptideProtocol

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

                            Text("\(protocol_.peptides.count) peptides")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }

                    Spacer()

                    if protocol_.status == .active {
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text("Week \(protocol_.weekNumber)")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.accentLight)
                            Text("of \(protocol_.cycleLengthWeeks)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }
                }

                if protocol_.status == .active {
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
                                        .strokeBorder(AppColor.surfaceElevated, lineWidth: 2)
                                }

                            Image(systemName: peptide.imageSystemName)
                                .font(AppFont.scaled(11))
                                .foregroundStyle(peptide.category.color)
                        }
                    }

                    if protocol_.peptides.count > 4 {
                        Text("+\(protocol_.peptides.count - 4)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.leading, Spacing.sm)
                    }

                    Spacer()

                    if protocol_.status == .active {
                        Text("\(protocol_.daysRemaining)d left")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
        // The peptide avatars are a visual summary of the count already
        // announced above, so they're hidden and the card reads as one item.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [protocol_.name, protocol_.status.displayName]
        parts.append("\(protocol_.peptides.count) peptides")
        if protocol_.status == .active {
            parts.append("week \(protocol_.weekNumber) of \(protocol_.cycleLengthWeeks)")
            parts.append("\(protocol_.daysRemaining) days left")
        }
        return parts.joined(separator: ", ")
    }
}

private struct StatusBadge: View {
    let status: ProtocolStatus

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: status.iconName)
                .font(AppFont.scaled(8))
            Text(status.displayName)
                .font(AppFont.caption)
                .fontWeight(.medium)
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
