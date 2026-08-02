import SwiftUI

/// The app's one segmented control. The selection pill slides between
/// segments via `matchedGeometryEffect`, mirroring the system tab bar.
struct GlassSegmentedControl<T: Hashable & CustomStringConvertible>: View {
    let options: [T]
    @Binding var selected: T
    var namespace: Namespace.ID
    /// Optional override that returns a localized title for an option. When
    /// nil, falls back to `option.description` (verbatim — not localized).
    var label: ((T) -> LocalizedStringKey)?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(options, id: \.self) { option in
                Button {
                    guard selected != option else { return }
                    Haptics.selection()
                    withAnimation(AppAnimation.springSnappy) {
                        selected = option
                    }
                } label: {
                    optionLabel(for: option)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selected == option ? [.isButton, .isSelected] : .isButton
                )
            }
        }
        .padding(Spacing.xs)
        .glassControl(.capsule, interactive: false)
    }

    private func optionLabel(for option: T) -> some View {
        title(for: option)
            .font(AppFont.subheadline)
            .foregroundStyle(
                selected == option ? AppColor.textPrimary : AppColor.textSecondary
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: Spacing.minimumHitTarget)
            .background { selectionBackground(for: option) }
    }

    @ViewBuilder
    private func title(for option: T) -> some View {
        if let label {
            Text(label(option))
        } else {
            Text(option.description)
        }
    }

    /// The moving pill. It's a plain tinted capsule rather than a second
    /// glass surface — stacking `glassEffect` inside an already-glass track
    /// is what made the control read as a muddy grey slab on iOS 26.
    @ViewBuilder
    private func selectionBackground(for option: T) -> some View {
        if selected == option {
            Capsule(style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.18))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                }
                .matchedGeometryEffect(id: "segment", in: namespace)
        }
    }
}

#Preview {
    @Previewable @Namespace var ns
    @Previewable @State var selected = "Week"
    ZStack {
        AppColor.background.ignoresSafeArea()
        GlassSegmentedControl(
            options: ["Week", "Month", "3 Months"],
            selected: $selected,
            namespace: ns
        )
    }
}
