import SwiftUI

struct ExportSection: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showShareSheet = false
    @State private var showPaywall = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isPreparingBackup = false
    @State private var isPreparingPDF = false
    @State private var hasWorkouts = false
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

                Text("Export your workouts, meals, check-ins and protocols.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)

                // Three buttons overflow a row at large Dynamic Type.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.md) { primaryExports }
                    VStack(alignment: .leading, spacing: Spacing.sm) { primaryExports }
                }

                // Per-domain CSVs surface as a secondary row of
                // text buttons. The primary three above remain the
                // canonical "everything" exports; these are for
                // doctor-visit / nutritionist hand-offs that only
                // need one slice. Hidden when the relevant data is
                // empty so the row doesn't clutter a fresh install.
                domainExportsRow
            }
            .appAnimation(AppAnimation.settle, value: hasWorkouts)
        }
        .task(id: dataStore.revision) {
            hasWorkouts = dataStore.hasWorkoutHistory
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(urls: [url])
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .export)
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

    /// The protocol CSV is empty for anyone not running a protocol, so it
    /// only shows for those who are.
    @ViewBuilder
    private var primaryExports: some View {
        if !dataStore.protocols.isEmpty {
            GlassButton(title: "CSV", icon: "tablecells", style: .secondary) {
                isPro ? exportCSV() : (showPaywall = true)
            }
        }

        GlassButton(title: isPreparingBackup ? "Preparing…" : "Backup", icon: "externaldrive.fill", style: .secondary) {
            isPro ? exportJSON() : (showPaywall = true)
        }
        .disabled(isPreparingBackup)

        GlassButton(title: isPreparingPDF ? "Preparing…" : "PDF", icon: "doc.richtext", style: .secondary) {
            isPro ? exportPDF() : (showPaywall = true)
        }
        .disabled(isPreparingPDF)
    }

    private var dateStamp: String {
        ExportService.calendarDay(Date())
    }

    /// Routes a freshly-written export file to the share sheet, or raises
    /// the failure alert when the write returned nil (disk full / sandbox
    /// error). Previously these failures no-op'd silently and the user
    /// believed the export had succeeded.
    private func share(_ url: URL?) {
        guard let url else {
            exportError = String(localized: "Couldn't write the export file. Check your available storage and try again.")
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
        share(ExportService.shared.writeCSV(csv, filename: "atlas-export-\(dateStamp).csv"))
    }

    /// Text buttons stacked beneath the primary export row for the
    /// per-domain slices (workouts / labs / meals / outcomes). Each
    /// is gated on the user actually having data to share — no
    /// point offering "Export labs" to someone with zero entries.
    @ViewBuilder
    private var domainExportsRow: some View {
        let hasLabs = !dataStore.profile.labHistory.isEmpty
        let hasMeals = !dataStore.profile.mealHistory.isEmpty
        let hasOutcomes = !dataStore.profile.outcomeHistory.isEmpty
        if hasWorkouts || hasLabs || hasMeals || hasOutcomes {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Divider().overlay(AppColor.glassBorder).padding(.vertical, Spacing.xxs)
                Text("By section")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.horizontal, 2)
                if hasWorkouts {
                    sliceButton(title: "Workouts CSV", icon: "dumbbell.fill") {
                        isPro ? exportWorkoutsCSV() : (showPaywall = true)
                    }
                    .transition(.opacity)
                }
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
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "square.and.arrow.up")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: Spacing.minimumHitTarget)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.45))
            }
            .contentShape(.rect)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }

    /// Loads the exercise library first: before it loads, every name
    /// would export as "Unknown exercise".
    private func exportWorkoutsCSV() {
        Task {
            await ExerciseLibrary.shared.load()
            let library = ExerciseLibrary.shared
            let csv = ExportService.shared.exportWorkoutsCSV(
                sessions: dataStore.allWorkoutSessionsForBackup(),
                exerciseName: { library.displayName(for: $0) }
            )
            share(ExportService.shared.writeCSV(csv, filename: "atlas-workouts-\(dateStamp).csv"))
        }
    }

    private func exportLabsCSV() {
        let csv = ExportService.shared.exportLabsCSV(labs: dataStore.profile.labHistory)
        share(ExportService.shared.writeCSV(csv, filename: "atlas-labs-\(dateStamp).csv"))
    }

    private func exportMealsCSV() {
        let csv = ExportService.shared.exportMealsCSV(meals: dataStore.profile.mealHistory)
        share(ExportService.shared.writeCSV(csv, filename: "atlas-meals-\(dateStamp).csv"))
    }

    private func exportOutcomesCSV() {
        let csv = ExportService.shared.exportOutcomesCSV(outcomes: dataStore.profile.outcomeHistory)
        share(ExportService.shared.writeCSV(csv, filename: "atlas-checkins-\(dateStamp).csv"))
    }

    /// Snapshots the value types here, then encodes off the main thread:
    /// years of workout history otherwise froze the screen mid-tap.
    private func exportJSON() {
        let service = ExportService.shared
        let protocols = dataStore.protocols
        let entries = dataStore.entries
        let profile = dataStore.profile
        let workoutSessions = dataStore.allWorkoutSessionsForBackup()
        let routines = dataStore.routinesForBackup()
        let customExercises = dataStore.customExercisesForBackup()
        let personalRecords = dataStore.personalRecordsForBackup()
        let customPeptides = dataStore.customPeptides
        isPreparingBackup = true
        Task {
            let data = await Task.detached(priority: .userInitiated) {
                service.exportFullBackup(
                    protocols: protocols,
                    entries: entries,
                    profile: profile,
                    workoutSessions: workoutSessions,
                    routines: routines,
                    customExercises: customExercises,
                    personalRecords: personalRecords,
                    customPeptides: customPeptides
                )
            }.value
            isPreparingBackup = false
            guard let data else {
                exportError = String(localized: "Couldn't prepare the backup. Please try again.")
                return
            }
            share(service.writeJSON(data, filename: "atlas-backup-\(dateStamp).json"))
        }
    }

    /// Snapshots the value types here, then renders off the main thread:
    /// many protocols otherwise froze Settings after the tap.
    private func exportPDF() {
        let service = ExportService.shared
        let protocols = dataStore.protocols
        let entries = dataStore.entries
        let profile = dataStore.profile
        isPreparingPDF = true
        Task {
            defer { isPreparingPDF = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try service.exportPDF(protocols: protocols, entries: entries, profile: profile)
                }.value
                if let url = service.writePDF(data, filename: "atlas-report-\(dateStamp).pdf") {
                    exportURL = url
                    showShareSheet = true
                } else {
                    exportError = String(localized: "Couldn't write the PDF to disk.")
                }
            } catch {
                exportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onCompletion: (@MainActor (Error?) -> Void)? = nil

    /// Convenience for the URL-only callers that pre-date the
    /// generalisation — preserves the original `ShareSheet(urls:)`
    /// initializer used by the export flow without forcing every
    /// caller to wrap their URLs in `[Any]`.
    init(urls: [URL]) {
        self.activityItems = urls
    }

    init(activityItems: [Any], onCompletion: (@MainActor (Error?) -> Void)? = nil) {
        self.activityItems = activityItems
        self.onCompletion = onCompletion
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        let completion = onCompletion
        controller.completionWithItemsHandler = { _, _, _, error in
            Task { @MainActor in completion?(error) }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
