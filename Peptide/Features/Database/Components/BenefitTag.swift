import SwiftUI

struct BenefitTag: View {
    let text: String
    var icon: String?
    var color: Color = AppColor.accentPrimary

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(AppFont.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background {
            RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                .fill(color.opacity(0.15))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                        .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                }
        }
        .shadow(color: color.opacity(0.15), radius: 3, y: 1)
    }
}

struct BenefitTagFlow: View {
    let benefits: [String]
    var color: Color = AppColor.accentPrimary

    var body: some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(benefits, id: \.self) { benefit in
                let style = BenefitStyleMap.style(for: benefit, fallbackColor: color)
                BenefitTag(text: benefit, icon: style.icon, color: style.color)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    struct Cache {
        var width: CGFloat?
        var items: [Placement] = []
        var size: CGSize = .zero
    }

    struct Placement {
        let position: CGPoint
        let size: CGSize
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        arrange(proposal: proposal, subviews: subviews, cache: &cache)
        return cache.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        arrange(proposal: proposal, subviews: subviews, cache: &cache)
        for (index, item) in cache.items.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + item.position.x, y: bounds.minY + item.position.y),
                proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let maxWidth = proposal.width ?? .infinity
        if cache.width == maxWidth, !cache.items.isEmpty { return }

        var items: [Placement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            // Propose the available row width so subviews wrap their text
            // (e.g. long benefit chips) instead of returning a too-wide ideal size.
            let widthProposal = maxWidth.isFinite ? maxWidth : nil
            let measured = subview.sizeThatFits(ProposedViewSize(width: widthProposal, height: nil))
            let cappedWidth = min(measured.width, maxWidth)
            let size = CGSize(width: cappedWidth, height: measured.height)

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            items.append(Placement(position: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        cache.width = maxWidth
        cache.items = items
        cache.size = CGSize(width: min(maxX, maxWidth), height: y + rowHeight)
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
