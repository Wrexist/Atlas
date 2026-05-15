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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Which meal?")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            HStack(spacing: Spacing.xs) {
                ForEach(MealCategory.allCases) { category in
                    pill(category)
                }
            }
        }
    }

    private func pill(_ category: MealCategory) -> some View {
        let active = (selection == category)
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selection = category
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(active ? Color.white : AppColor.textSecondary)
                Text(category.displayName)
                    .font(.system(size: 11, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? AppColor.textPrimary : AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(active ? AppColor.accentPrimary.opacity(0.28) : AppColor.surfaceSecondary.opacity(0.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(
                                active ? AppColor.accentPrimary.opacity(0.65) : AppColor.glassBorder,
                                lineWidth: 1
                            )
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}
