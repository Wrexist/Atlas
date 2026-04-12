import SwiftUI

struct BenefitTag: View {
    let text: String
    var icon: String? = nil
    var color: Color = AppColor.accentPrimary

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(AppFont.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background {
            RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                .fill(color.opacity(0.15))
                .shadow(color: color.opacity(0.2), radius: 4)
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                        .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                }
        }
    }
}

struct BenefitTagFlow: View {
    let benefits: [String]
    var color: Color = AppColor.accentPrimary

    var body: some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(Array(benefits.enumerated()), id: \.element) { index, benefit in
                let style = BenefitStyleMap.style(for: benefit, fallbackColor: color)
                BenefitTag(text: benefit, icon: style.icon, color: style.color)
                    .staggeredAppear(index: index)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            BenefitTagFlow(
                benefits: ["Tissue Repair", "Gut Healing", "Anti-Inflammatory", "Joint Support", "Tendon Recovery"],
                color: PeptideCategory.growth.color
            )
            BenefitTagFlow(
                benefits: ["Focus", "Memory", "Neuroprotection", "BDNF", "Mood"],
                color: PeptideCategory.cognitive.color
            )
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
