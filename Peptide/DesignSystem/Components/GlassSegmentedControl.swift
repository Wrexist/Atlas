import SwiftUI

/// The app's one segmented control.
///
/// The selection pill is a window, not a sticker: the row is drawn twice,
/// once in quiet ink and once inverted on a solid ink fill, and the
/// inverted copy is masked to a capsule that glides to the chosen
/// segment's measured frame. So the label colour flips exactly at the
/// pill's edge while it moves, instead of cross-fading out of step.
///
/// - `.standard` sits on a card-surface track — for picking a mode inside
///   a card or sheet.
/// - `.prominent` drops the track — for a screen's top-level section
///   switcher. The pill is the same everywhere, so "selected" reads the
///   same at every level.
struct GlassSegmentedControl<T: Hashable>: View {
    enum Style {
        case standard
        case prominent
    }

    let options: [T]
    @Binding var selected: T
    var style: Style = .standard
    let label: (T) -> LocalizedStringKey
    var icon: ((T) -> String)?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        track
            .opacity(isEnabled ? 1 : AppOpacity.disabled)
            // One container, so an identifier on the control lands on the
            // group rather than on every segment button.
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var track: some View {
        switch style {
        case .standard:
            row
                .padding(Spacing.xs)
                .glassSurfaceCapsule()
        case .prominent:
            row
        }
    }

    private var spacing: CGFloat { style == .prominent ? Spacing.xs : 0 }

    private var row: some View {
        HStack(spacing: spacing) {
            ForEach(options, id: \.self) { option in
                segmentButton(for: option)
            }
        }
        .backgroundPreferenceValue(SelectedSegmentKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    pillShadow(in: proxy[anchor])
                }
            }
        }
        .overlayPreferenceValue(SelectedSegmentKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    selectedCopy(pill: proxy[anchor])
                }
            }
        }
    }

    private func segmentButton(for option: T) -> some View {
        let isSelected = selected == option
        return Button {
            guard !isSelected else { return }
            Haptics.selection()
            AppAnimation.with(AppAnimation.springSnappy) {
                selected = option
            }
        } label: {
            segmentLabel(for: option)
                .foregroundStyle(AppColor.textSecondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .anchorPreference(key: SelectedSegmentKey.self, value: .bounds) { isSelected ? $0 : nil }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The inverted row, visible only through the capsule at `pill`.
    private func selectedCopy(pill: CGRect) -> some View {
        HStack(spacing: spacing) {
            ForEach(options, id: \.self) { option in
                segmentLabel(for: option)
                    .foregroundStyle(AppColor.inverseInk)
            }
        }
        .background(AppColor.textPrimary)
        .mask(alignment: .topLeading) { capsule(at: pill) }
        .overlay(alignment: .topLeading) {
            Self.pillRim
                .frame(width: pill.width, height: pill.height)
                .offset(x: pill.minX, y: pill.minY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The pill's drop, drawn under the row so the lifted capsule casts
    /// it onto the track rather than onto its own label.
    private func pillShadow(in pill: CGRect) -> some View {
        capsule(at: pill)
            .appShadow(AppShadow.tileContact)
            .appShadow(AppShadow.tileDrop)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func capsule(at rect: CGRect) -> some View {
        Capsule(style: .continuous)
            .fill(AppColor.textPrimary)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    /// Light catching the pill's upper edge: the same lit rim the cards
    /// and icon tiles carry, so the pill reads as a raised key.
    private static var pillRim: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center),
                lineWidth: 1
            )
    }

    private func segmentLabel(for option: T) -> some View {
        HStack(spacing: Spacing.xs) {
            if let icon {
                Image(systemName: icon(option))
                    .font(AppFont.scaled(11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(label(option))
                .font(AppFont.subheadline)
                .fontWeight(.medium)
                // Equal-width segments can't fit a grown label on one
                // line; at accessibility sizes it wraps instead of
                // shrinking into an ellipsis.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
        }
        // Tight sides on the track so four labels like "Favorites" fit a
        // phone's width without truncating.
        .padding(.horizontal, style == .prominent ? Spacing.md : Spacing.xs)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: style == .prominent ? nil : CGFloat.infinity)
        .frame(minHeight: Spacing.minimumHitTarget)
    }
}

/// The selected segment's bounds, so the pill and its masked copy can sit
/// exactly on it and glide when the selection changes.
private struct SelectedSegmentKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

#Preview {
    @Previewable @State var selected = "Week"
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            GlassSegmentedControl(
                options: ["Week", "Month", "3 Months"],
                selected: $selected,
                label: { LocalizedStringKey($0) }
            )
            GlassSegmentedControl(
                options: ["Week", "Month", "3 Months"],
                selected: $selected,
                style: .prominent,
                label: { LocalizedStringKey($0) }
            )
        }
        .padding(Spacing.screenPadding)
    }
}
