import SwiftUI

/// Segmented format picker for share sheets. Each segment draws the export
/// canvas's own shape as a small outline above its name, so "Story",
/// "Square" and "Wide" read at a glance. Same track, pill and motion as
/// `GlassSegmentedControl`; the glyph is why it isn't that control.
struct ShareFormatPicker<Format: ShareFormatDescribing>: View {
    let options: [Format]
    @Binding var selection: Format

    @Namespace private var pillNamespace

    /// Longest side of a glyph, in points.
    private static var glyphExtent: CGFloat { Spacing.xl }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(for: option)
            }
        }
        .padding(Spacing.xs)
        .glassControl(.capsule, interactive: false)
    }

    private func segment(for option: Format) -> some View {
        let isSelected = selection == option
        return Button {
            guard !isSelected else { return }
            Haptics.selection()
            AppAnimation.with(AppAnimation.springSnappy) {
                selection = option
            }
        } label: {
            VStack(spacing: Spacing.xs) {
                glyph(for: option)
                Text(option.title)
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
            .background {
                if isSelected {
                    pill.matchedGeometryEffect(id: "segment", in: pillNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(Text(option.title))
        .accessibilityValue(Text(option.detail))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("share-format-\(option.id)")
    }

    private func glyph(for option: Format) -> some View {
        let size = Self.glyphSize(aspectRatio: option.aspectRatio)
        return RoundedRectangle(cornerRadius: Spacing.xxs, style: .continuous)
            .strokeBorder(lineWidth: 1.5)
            .frame(width: size.width, height: size.height)
            .overlay {
                if let symbol = option.glyphSymbol {
                    Image(systemName: symbol)
                        .font(AppFont.scaled(8, weight: .bold))
                }
            }
            .frame(width: Self.glyphExtent, height: Self.glyphExtent)
            .accessibilityHidden(true)
    }

    /// Fits the canvas shape inside a square of `glyphExtent`.
    private static func glyphSize(aspectRatio: CGFloat) -> CGSize {
        aspectRatio >= 1
            ? CGSize(width: glyphExtent, height: glyphExtent / aspectRatio)
            : CGSize(width: glyphExtent * aspectRatio, height: glyphExtent)
    }

    /// A plain tinted capsule rather than a second glass surface, matching
    /// `GlassSegmentedControl`'s standard pill.
    private var pill: some View {
        Capsule(style: .continuous)
            .fill(AppColor.accentPrimary.opacity(0.18))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
            }
    }
}

#Preview {
    @Previewable @State var format = ShareFormat.story
    ZStack {
        AppColor.background.ignoresSafeArea()
        ShareFormatPicker(options: ShareFormat.allCases, selection: $format)
            .padding(Spacing.screenPadding)
    }
}
