import SwiftUI

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
                    withAnimation(AppAnimation.springSnappy) {
                        selected = option
                    }
                } label: {
                    optionLabel(for: option)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.xs)
        .background {
            Capsule()
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    Capsule()
                        .fill(AppColor.cardOverlay)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .liquidGlass(.capsule)
    }

    @ViewBuilder
    private func optionLabel(for option: T) -> some View {
        if let label {
            Text(label(option))
                .font(AppFont.subheadline)
                .foregroundStyle(
                    selected == option ? AppColor.textPrimary : AppColor.textSecondary
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background { selectionBackground(for: option) }
        } else {
            Text(option.description)
                .font(AppFont.subheadline)
                .foregroundStyle(
                    selected == option ? AppColor.textPrimary : AppColor.textSecondary
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background { selectionBackground(for: option) }
        }
    }

    @ViewBuilder
    private func selectionBackground(for option: T) -> some View {
        if selected == option {
            Capsule()
                .fill(AppColor.accentPrimary.opacity(0.25))
                .overlay {
                    Capsule()
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
    .preferredColorScheme(.dark)
}
