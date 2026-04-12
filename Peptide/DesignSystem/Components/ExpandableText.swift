import SwiftUI

struct ExpandableText: View {
    let text: String
    var lineLimit: Int = 4

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(text)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask {
                    VStack(spacing: 0) {
                        Rectangle()
                        if !isExpanded && isTruncated {
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 24)
                        }
                    }
                }
                .animation(AppAnimation.springSmooth, value: isExpanded)

            if isTruncated || isExpanded {
                Button {
                    withAnimation(AppAnimation.springSmooth) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(isExpanded ? "Show less" : "Read more")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .background(
            ZStack {
                Text(text)
                    .font(AppFont.body)
                    .lineSpacing(4)
                    .lineLimit(lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GeometryReader { limitedGeo in
                            Color.clear.preference(
                                key: CollapsedHeightKey.self,
                                value: limitedGeo.size.height
                            )
                        }
                    )

                Text(text)
                    .font(AppFont.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GeometryReader { fullGeo in
                            Color.clear.preference(
                                key: FullHeightKey.self,
                                value: fullGeo.size.height
                            )
                        }
                    )
            }
            .hidden()
        )
        .onPreferenceChange(CollapsedHeightKey.self) { collapsed in
            updateTruncation(collapsed: collapsed)
        }
        .onPreferenceChange(FullHeightKey.self) { full in
            updateTruncation(full: full)
        }
    }

    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private func updateTruncation(collapsed: CGFloat? = nil, full: CGFloat? = nil) {
        if let collapsed { collapsedHeight = collapsed }
        if let full { fullHeight = full }
        let c = collapsed ?? collapsedHeight
        let f = full ?? fullHeight
        if c > 0 && f > 0 {
            isTruncated = f > c + 1
        }
    }
}

private struct CollapsedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FullHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()

        VStack(spacing: Spacing.lg) {
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Label("About", systemImage: "info.circle.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    ExpandableText(
                        text: "BPC-157 is a synthetic peptide consisting of 15 amino acids. It is derived from a protective protein found in human gastric juice. Research has shown it promotes healing of various tissues including tendons, muscles, the nervous system, and the gastrointestinal tract. It has been studied for its regenerative properties and potential to accelerate recovery from injuries. BPC-157 demonstrates remarkable stability and does not require a carrier molecule for biological activity."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Label("Short text", systemImage: "text.justify.left")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    ExpandableText(text: "This is short text that fits in 4 lines.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
