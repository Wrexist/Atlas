import SwiftUI

/// Settings row mounted under `ExportSection` that opens the
/// `RestoreBackupSheet`. Pairs with the existing export affordance
/// so the round-trip lives in one logical place in Settings.
struct RestoreBackupEntryRow: View {
    let onTap: () -> Void

    @State private var latestRestorePoint: Date?

    var body: some View {
        GlassEntryRow(
            icon: "tray.and.arrow.down.fill",
            title: "Restore from backup",
            subtitle: subtitle,
            action: onTap
        )
        .accessibilityHint("Opens the restore-from-backup flow.")
        .onAppear { latestRestorePoint = RestorePointService.restorePoints().first?.createdAt }
    }

    /// Says when the newest automatic restore point was saved, so it's
    /// visible at a glance that the daily copy is running.
    private var subtitle: Text {
        guard let latestRestorePoint else { return Text("Your current data is copied first") }
        return Text("Restore point saved \(latestRestorePoint.formatted(.relative(presentation: .named))). Your current data is copied first.")
    }
}
