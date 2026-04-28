import SwiftUI

struct ExportSection: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showShareSheet = false
    @State private var showPaywall = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    private var isPro: Bool { StoreService.shared.isProUser }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Label("Data Export", systemImage: "square.and.arrow.up")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    if !isPro {
                        ProBadge()
                    }
                }

                (Text("Export your ")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                + Text("protocol history")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.accentLight)
                + Text(" and ")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                + Text("tracking data")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.accentLight))

                HStack(spacing: Spacing.md) {
                    GlassButton(title: "CSV", icon: "tablecells", style: .secondary) {
                        isPro ? exportCSV() : (showPaywall = true)
                    }

                    GlassButton(title: "Backup", icon: "externaldrive.fill", style: .secondary) {
                        isPro ? exportJSON() : (showPaywall = true)
                    }

                    GlassButton(title: "PDF", icon: "doc.richtext", style: .secondary) {
                        isPro ? exportPDF() : (showPaywall = true)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(urls: [url])
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
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

    private func exportPDF() {
        do {
            let data = try ExportService.shared.exportPDF(
                protocols: dataStore.protocols,
                entries: dataStore.entries,
                profile: dataStore.profile
            )
            let dateStr = Date().formatted(.iso8601.year().month().day())
            if let url = ExportService.shared.writePDF(data, filename: "peptidex-report-\(dateStr).pdf") {
                exportURL = url
                showShareSheet = true
            } else {
                exportError = "Couldn't write the PDF to disk."
            }
        } catch {
            exportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
