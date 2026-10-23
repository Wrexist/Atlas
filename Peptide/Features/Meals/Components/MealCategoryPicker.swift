import SwiftUI

/// Compact four-pill row for picking which meal a log belongs to.
/// Used inside the review phase of every logging flow (food library,
/// barcode scan, photo scan) so the user can override the auto-
/// detected category before tapping "Add to today".
///
/// The default selection is set by the caller via
/// `MealCategory.auto(for: Date())` — most users will accept it,
/// some will tap to override. Picker is presented inline in the
/// review card rather than as a separate sheet so the selection is
/// always visible alongside the macros being logged.
struct MealCategoryPicker: View {
    @Binding var selection: MealCategory

    @Namespace private var fillNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Which meal?")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            // One row of four when it fits; a 2×2 grid at accessibility
            // sizes so the names never truncate.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xs) { allPills }
                Grid(horizontalSpacing: Spacing.xs, verticalSpacing: Spacing.xs) {
                    GridRow { pills(MealCategory.allCases.prefix(2)) }
                    GridRow { pills(MealCategory.allCases.suffix(2)) }
                }
            }
        }
        .appSensoryFeedback(.selection, trigger: selection)
    }

    private var allPills: some View {
        pills(MealCategory.allCases[...])
    }

    private func pills(_ categories: ArraySlice<MealCategory>) -> some View {
        ForEach(categories) { category in
            pill(category)
        }
    }

    private func pill(_ category: MealCategory) -> some View {
        let active = (selection == category)
        let tint = category.tint
        return Button {
            AppAnimation.with(AppAnimation.springSnappy) {
                selection = category
            }
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: category.icon)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(active ? tint : AppColor.textSecondary)
                Text(category.displayName)
                    .font(AppFont.scaled(11, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? AppColor.textPrimary : AppColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, Spacing.xs)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background {
                if active {
                    tile(fill: tint.opacity(0.22), border: tint.opacity(0.6))
                        .matchedGeometryEffect(id: "selectedCategory", in: fillNamespace)
                }
            }
            .background {
                tile(fill: AppColor.surfaceSecondary.opacity(0.5), border: AppColor.glassBorder)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    private func tile(fill: Color, border: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
        return shape
            .fill(fill)
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
    }
}
