import SwiftUI

/// The app's one segmented control. The selection pill slides between
/// segments via `matchedGeometryEffect`, mirroring the system tab bar.
///
/// - `.standard` sits on a glass track with a tinted pill — for picking a
///   mode inside a card or sheet.
/// - `.prominent` drops the track and fills the pill with the accent — for
///   a screen's top-level section switcher.
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

    @Namespace private var pillNamespace
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    /// Light mode selects with a solid ink pill on a paper track: on the
    /// warm page a faint accent wash barely reads as "chosen".
    private var inkSelection: Bool { style == .standard && colorScheme == .light }

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
            if inkSelection {
                segments(spacing: 0)
                    .padding(Spacing.xs)
                    .glassSurfaceCapsule()
            } else {
                segments(spacing: 0)
                    .padding(Spacing.xs)
                    .glassControl(.capsule, interactive: false)
            }
        case .prominent:
            segments(spacing: Spacing.sm)
        }
    }

    private func segments(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(options, id: \.self) { option in
                segment(for: option)
            }
        }
    }

    private func segment(for option: T) -> some View {
        let isSelected = selected == option
        return Button {
            guard !isSelected else { return }
            Haptics.selection()
            AppAnimation.with(AppAnimation.springSnappy) {
                selected = option
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon(option))
                        .font(AppFont.scaled(11, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(label(option))
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    // Equal-width segments can't fit a grown label on one
                    // line; at accessibility sizes it wraps instead of
                    // shrinking into an ellipsis.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(foreground(isSelected: isSelected))
            // Tight sides on the track so four labels like "Favorites"
            // fit a phone's width without truncating.
            .padding(.horizontal, style == .prominent ? Spacing.lg : Spacing.xs)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: style == .prominent ? nil : CGFloat.infinity)
            .frame(minHeight: Spacing.minimumHitTarget)
            .background {
                if isSelected {
                    pill.matchedGeometryEffect(id: "segment", in: pillNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func foreground(isSelected: Bool) -> Color {
        guard isSelected else { return AppColor.textSecondary }
        return style == .prominent || inkSelection ? AppColor.onAccent : AppColor.textPrimary
    }

    /// The moving pill. On the standard track it's a plain tinted capsule
    /// rather than a second glass surface — stacking `glassEffect` inside an
    /// already-glass track is what made the control read as a muddy grey
    /// slab on iOS 26.
    @ViewBuilder
    private var pill: some View {
        switch style {
        case .standard where inkSelection:
            Capsule(style: .continuous)
                .fill(AppColor.textPrimary)
        case .standard:
            Capsule(style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.18))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                }
        case .prominent:
            Capsule(style: .continuous)
                .fill(AppColor.accentFill)
        }
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
