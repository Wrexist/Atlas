import SwiftUI

/// Settings row mounted under `ExportSection` that opens the
/// `RestoreBackupSheet`. Pairs with the existing export affordance
/// so the round-trip lives in one logical place in Settings.
struct RestoreBackupEntryRow: View {
    let onTap: () -> Void

    var body: some View {
        GlassEntryRow(
            icon: "tray.and.arrow.down.fill",
            title: "Restore from backup",
            subtitle: Text("Re-import a previously-exported JSON backup. A safety copy of your current data is saved on this device first."),
            action: onTap
        )
        .accessibilityHint("Opens the restore-from-backup flow.")
    }
}
