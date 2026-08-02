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
                    .font(AppFont.scaled(11, weight: .medium))
                    .foregroundStyle(AppColor.accentLight)
                + Text(" and ")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                + Text("tracking data")
                    .font(AppFont.scaled(11, weight: .medium))
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

                // Per-domain CSVs surface as a secondary row of
                // text buttons. The primary three above remain the
                // canonical "everything" exports; these are for
                // doctor-visit / nutritionist hand-offs that only
                // need one slice. Hidden when the relevant data is
                // empty so the row doesn't clutter a fresh install.
                domainExportsRow
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(urls: [url])
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .liquidGlassPresentation()
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    /// Routes a freshly-written export file to the share sheet, or raises
    /// the failure alert when the write returned nil (disk full / sandbox
    /// error). Previously these failures no-op'd silently and the user
    /// believed the export had succeeded.
    private func share(_ url: URL?) {
        guard let url else {
            exportError = "Couldn't write the export file. Check your available storage and try again."
            return
        }
        exportURL = url
        showShareSheet = true
    }

    private func exportCSV() {
        let csv = ExportService.shared.exportProtocolsCSV(
            protocols: dataStore.protocols,
            entries: dataStore.entries
        )
        let dateStr = Date().formatted(.iso8601.year().month().day())
        share(ExportService.shared.writeCSV(csv, filename: "atlas-export-\(dateStr).csv"))
    }

    /// Three text buttons stacked beneath the primary export row
    /// for the per-domain slices (labs / meals / outcomes). Each
    /// is gated on the user actually having data to share — no
    /// point offering "Export labs" to someone with zero entries.
    @ViewBuilder
    private var domainExportsRow: some View {
        let hasLabs = !dataStore.profile.labHistory.isEmpty
        let hasMeals = !dataStore.profile.mealHistory.isEmpty
        let hasOutcomes = !dataStore.profile.outcomeHistory.isEmpty
        if hasLabs || hasMeals || hasOutcomes {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Divider().background(AppColor.glassBorder).padding(.vertical, 2)
                Text("By section")
                    .font(AppFont.scaled(10, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.horizontal, 2)
                if hasLabs {
                    sliceButton(title: "Labs CSV", icon: "testtube.2") {
                        isPro ? exportLabsCSV() : (showPaywall = true)
                    }
                }
                if hasMeals {
                    sliceButton(title: "Meals CSV", icon: "fork.knife") {
                        isPro ? exportMealsCSV() : (showPaywall = true)
                    }
                }
                if hasOutcomes {
                    sliceButton(title: "Check-ins CSV", icon: "heart.text.square") {
                        isPro ? exportOutcomesCSV() : (showPaywall = true)
                    }
                }
            }
        }
    }

    private func sliceButton(title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 18)
                Text(title)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "square.and.arrow.up")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.45))
            }
        }
        .buttonStyle(.plain)
    }

    private func exportLabsCSV() {
        let csv = ExportService.shared.exportLabsCSV(labs: dataStore.profile.labHistory)
        let dateStr = Date().formatted(.iso8601.year().month().day())
        share(ExportService.shared.writeCSV(csv, filename: "atlas-labs-\(dateStr).csv"))
    }

    private func exportMealsCSV() {
        let csv = ExportService.shared.exportMealsCSV(meals: dataStore.profile.mealHistory)
        let dateStr = Date().formatted(.iso8601.year().month().day())
        share(ExportService.shared.writeCSV(csv, filename: "atlas-meals-\(dateStr).csv"))
    }

    private func exportOutcomesCSV() {
        let csv = ExportService.shared.exportOutcomesCSV(outcomes: dataStore.profile.outcomeHistory)
        let dateStr = Date().formatted(.iso8601.year().month().day())
        share(ExportService.shared.writeCSV(csv, filename: "atlas-checkins-\(dateStr).csv"))
    }

    private func exportJSON() {
        guard let data = ExportService.shared.exportFullBackup(
            protocols: dataStore.protocols,
            entries: dataStore.entries,
            profile: dataStore.profile
        ) else {
            exportError = "Couldn't prepare the backup. Please try again."
            return
        }
        let dateStr = Date().formatted(.iso8601.year().month().day())
        share(ExportService.shared.writeJSON(data, filename: "atlas-backup-\(dateStr).json"))
    }

    private func exportPDF() {
        do {
            let data = try ExportService.shared.exportPDF(
                protocols: dataStore.protocols,
                entries: dataStore.entries,
                profile: dataStore.profile
            )
            let dateStr = Date().formatted(.iso8601.year().month().day())
            if let url = ExportService.shared.writePDF(data, filename: "atlas-report-\(dateStr).pdf") {
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
    let activityItems: [Any]

    /// Convenience for the URL-only callers that pre-date the
    /// generalisation — preserves the original `ShareSheet(urls:)`
    /// initializer used by the export flow without forcing every
    /// caller to wrap their URLs in `[Any]`.
    init(urls: [URL]) {
        self.activityItems = urls
    }

    init(activityItems: [Any]) {
        self.activityItems = activityItems
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
