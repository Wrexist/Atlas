import SwiftUI

struct ExportSection: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showShareSheet = false
    @State private var exportURL: URL?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Data Export", systemImage: "square.and.arrow.up")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                Text("Export your protocol history and tracking data")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)

                HStack(spacing: Spacing.md) {
                    GlassButton(title: "CSV", icon: "tablecells", style: .secondary) {
                        exportCSV()
                    }

                    GlassButton(title: "Backup", icon: "externaldrive.fill", style: .secondary) {
                        exportJSON()
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportCSV() {
        let csv = ExportService.shared.exportProtocolsCSV(
            protocols: dataStore.protocols,
            entries: dataStore.entries
        )
        let dateStr = Date().formatted(.iso8601.year().month().day())
        if let url = ExportService.shared.writeCSV(csv, filename: "peptidex-export-\(dateStr).csv") {
            exportURL = url
            showShareSheet = true
        }
    }

    private func exportJSON() {
        if let data = ExportService.shared.exportFullBackup(
            protocols: dataStore.protocols,
            entries: dataStore.entries,
            profile: dataStore.profile
        ) {
            let dateStr = Date().formatted(.iso8601.year().month().day())
            if let url = ExportService.shared.writeJSON(data, filename: "peptidex-backup-\(dateStr).json") {
                exportURL = url
                showShareSheet = true
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
