import SwiftUI

/// Settings row mounted under `ExportSection` that opens the
/// `RestoreBackupSheet`. Pairs with the existing export affordance
/// so the round-trip lives in one logical place in Settings.
struct RestoreBackupEntryRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(AppFont.scaled(18, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 36, height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppColor.accentPrimary.opacity(0.18))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Restore from backup")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Re-import a previously-exported JSON backup. A snapshot of your current data is taken first so you can roll back.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the restore-from-backup flow.")
    }
}
