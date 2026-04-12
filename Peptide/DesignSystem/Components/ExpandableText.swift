import SwiftUI

struct ExpandableText: View {
    let text: String
    var lineLimit: Int = 4
    var accentColor: Color = AppColor.accentLight
    var highlightKeywords: Bool = true

    @State private var isExpanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool {
        guard collapsedHeight > 0 else { return false }
        return fullHeight > collapsedHeight + 1
    }

    private static let gradientHeight: CGFloat = 24

    private var renderedText: Text {
        if highlightKeywords {
            return Text(KeywordHighlighter.highlight(text, accentColor: accentColor))
        }
        return Text(text)
            .font(AppFont.body)
            .foregroundStyle(AppColor.textSecondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            renderedText
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
                            .frame(height: Self.gradientHeight)
                            .transition(.opacity)
                        }
                    }
                }

            if isTruncated {
                Button {
                    withAnimation(AppAnimation.springSmooth) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(isExpanded ? "Show less" : "Read more")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentPrimary)
                }
                .accessibilityHint(isExpanded ? "Collapse text" : "Expand full text")
                .transition(.opacity)
            }
        }
        .background(
            ZStack {
                renderedText
                    .lineSpacing(4)
                    .lineLimit(lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        collapsedHeight = $0
                    }

                renderedText
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        fullHeight = $0
                    }
            }
            .hidden()
            .accessibilityHidden(true)
        )
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
