import SwiftUI

/// The app's one text field: a glass capsule with an optional leading
/// glyph and a clear button, or — with `axis: .vertical` — a rounded
/// glass box that grows with its text.
///
/// Type, line limits, capitalisation and submit behaviour come from the
/// environment, so set them on the field the way you would on a
/// `TextField` (`.font(AppFont.title2)`, `.lineLimit(3...6)`,
/// `.submitLabel(.done)`). Pass `focus` when the screen needs to move focus
/// itself; the accent ring follows it either way.
struct GlassTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var icon: String? = "magnifyingglass"
    var axis: Axis = .horizontal
    var characterLimit: Int?
    var focus: FocusState<Bool>.Binding?

    @FocusState private var ownFocus: Bool

    private var isFocused: FocusState<Bool>.Binding { focus ?? $ownFocus }

    private var shape: AnyShape {
        axis == .vertical
            ? AnyShape(RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous))
            : AnyShape(Capsule())
    }

    var body: some View {
        HStack(alignment: axis == .vertical ? .top : .center, spacing: Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                TextField(placeholder, text: $text, axis: axis)
                    .foregroundStyle(AppColor.textPrimary)
                    .tint(AppColor.accentPrimary)
                    .focused(isFocused)

                if let characterLimit {
                    Text("\(text.count)/\(characterLimit)")
                        .font(AppFont.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            if axis == .horizontal && !text.isEmpty {
                clearButton
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .modifier(GlassFieldSurface(axis: axis))
        .overlay {
            shape
                .stroke(AppColor.accentPrimary, lineWidth: 1)
                .opacity(isFocused.wrappedValue ? 1 : 0)
        }
        .appAnimation(AppAnimation.quick, value: isFocused.wrappedValue)
        .onChange(of: text) { _, newValue in
            guard let characterLimit, newValue.count > characterLimit else { return }
            text = String(newValue.prefix(characterLimit))
        }
    }

    private var clearButton: some View {
        Button {
            AppAnimation.with(AppAnimation.springSnappy) {
                text = ""
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: Spacing.minimumHitTarget,
                       height: Spacing.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Clear text")
    }
}

private struct GlassFieldSurface: ViewModifier {
    let axis: Axis

    func body(content: Content) -> some View {
        switch axis {
        case .vertical:
            content.glassSurface(cornerRadius: Spacing.controlCornerRadius)
        case .horizontal:
            content.glassSurfaceCapsule()
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            GlassTextField(placeholder: "Search peptides...", text: .constant(""))
            GlassTextField(placeholder: "Search peptides...", text: .constant("BPC"))
            GlassTextField(placeholder: "First name", text: .constant(""), icon: nil)
            GlassTextField(
                placeholder: "How did it go?",
                text: .constant("Felt strong on the top set."),
                icon: nil,
                axis: .vertical,
                characterLimit: 500
            )
            .lineLimit(3...6)
        }
        .padding(Spacing.screenPadding)
    }
}
