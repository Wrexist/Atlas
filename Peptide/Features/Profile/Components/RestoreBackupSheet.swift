import SwiftUI
import UniformTypeIdentifiers

/// Settings → Restore from Backup entry point. Three-step flow:
///
/// 1. **Pick** — file importer surfaces the system file picker. User
///    chooses a JSON backup exported from a prior Atlas install.
/// 2. **Preview** — `BackupImportService.validate` parses + bounds-
///    checks the file. The sheet shows counts (protocols, entries,
///    history sections present) and lets the user pick Replace vs
///    Merge.
/// 3. **Confirm + apply** — explicit second tap on the chosen
///    strategy. Apply runs synchronously on @MainActor (typical
///    backups are <10 MB so this completes in milliseconds), then
///    the sheet shows the success summary with a count of what was
///    restored.
///
/// Each terminal state surfaces an exit button. Errors at any step
/// render an error card with the user-actionable string from
/// `BackupImportService.ImportError.errorDescription`.
struct RestoreBackupSheet: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .pick
    @State private var showingFileImporter = false
    @State private var preview: BackupImportService.Preview?
    @State private var backup: AppBackup?
    @State private var errorMessage: String?
    @State private var resultPreview: BackupImportService.Preview?
    @State private var snapshots: [BackupSnapshotService.Info] = []

    private enum Phase: Equatable {
        case pick
        case preview
        case confirming(BackupImportService.Strategy)
        case applying
        case done
        case failed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    switch phase {
                    case .pick: pickPhase.transition(Self.phaseTransition)
                    case .preview: previewPhase.transition(Self.phaseTransition)
                    case .confirming(let strategy): confirmPhase(strategy).transition(Self.phaseTransition)
                    case .applying: applyingPhase.transition(Self.phaseTransition)
                    case .done: donePhase.transition(Self.phaseTransition)
                    case .failed: failedPhase.transition(Self.phaseTransition)
                    }
                }
                .appAnimation(AppAnimation.springSmooth, value: phase)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.xl)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase != .applying {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(phase == .applying)
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false,
                onCompletion: handleFilePicked
            )
        }
    }

    // MARK: - Phases

    /// Each step slides in from the trailing edge, reading as forward motion.
    private static let phaseTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .opacity
    )

    private var pickPhase: some View {
        VStack(spacing: Spacing.lg) {
            HeroCard(
                icon: "tray.and.arrow.down.fill",
                title: "Restore from a backup",
                subtitle: Text("Pick a JSON file you previously exported from Atlas. A safety copy of your current data is saved on this device first.")
            )
            PrimaryCTAButton(title: "Pick a backup file", icon: "folder", shape: .rounded) {
                showingFileImporter = true
            }
            if !snapshots.isEmpty {
                safetyCopyList
            }
        }
        .onAppear { snapshots = BackupSnapshotService.availableSnapshots() }
    }

    /// The pre-restore snapshots `apply` writes, offered back so a
    /// mistaken Replace can be undone.
    private var safetyCopyList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Restore a safety copy")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Saved on this device before each restore.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            ForEach(snapshots) { info in
                SafetyCopyRow(info: info) { validateSnapshot(info) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.md)
    }

    private var previewPhase: some View {
        VStack(spacing: Spacing.lg) {
            if let preview {
                HeroCard(
                    icon: "doc.text.magnifyingglass",
                    title: "Backup looks valid",
                    subtitle: Text("Exported \(preview.exportDate.formatted(date: .abbreviated, time: .shortened)). Choose how to apply it.")
                )
                BackupSummaryCard(preview: preview)
            }

            VStack(spacing: Spacing.sm) {
                StrategyCard(
                    title: "Merge with current data",
                    detail: "Adds any items not already in your library. Existing items are kept as-is. Safer.",
                    icon: "arrow.triangle.merge",
                    style: .primary,
                    onTap: { phase = .confirming(.merge) }
                )
                StrategyCard(
                    title: "Replace current data",
                    detail: "Wipes your current workouts, meals, protocols and profile, then restores from the backup. A snapshot is taken first.",
                    icon: "arrow.triangle.2.circlepath",
                    style: .destructive,
                    onTap: { phase = .confirming(.replace) }
                )
            }
        }
    }

    private func confirmPhase(_ strategy: BackupImportService.Strategy) -> some View {
        VStack(spacing: Spacing.lg) {
            HeroCard(
                icon: strategy == .replace ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                title: strategy == .replace ? "Confirm replace" : "Confirm merge",
                subtitle: strategy == .replace
                    ? Text("Your current data will be replaced. A safety copy of your current data is saved on this device first.")
                    : Text("Your current data is kept; only items missing from your library are added.")
            )
            VStack(spacing: Spacing.sm) {
                PrimaryCTAButton(
                    title: strategy == .replace ? "Replace and restore" : "Merge and restore",
                    icon: "checkmark",
                    shape: .rounded
                ) {
                    apply(strategy: strategy)
                }

                GlassButton(title: "Back", style: .ghost, isFullWidth: true) {
                    phase = .preview
                }
            }
        }
    }

    private var applyingPhase: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
                .padding(.top, Spacing.xl)
            Text("Restoring your data…")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var donePhase: some View {
        VStack(spacing: Spacing.lg) {
            HeroCard(
                icon: "checkmark.seal.fill",
                title: "Restore complete",
                subtitle: resultPreview?.safetyCopySaved == true
                    ? Text("Your data is back. A safety copy of your previous data is saved on this device.")
                    : Text("Your data is back. A safety copy of your previous data couldn't be saved."),
                bouncesOnAppear: true
            )
            if let resultPreview {
                BackupSummaryCard(preview: resultPreview)
            }
            PrimaryCTAButton(title: "Done", shape: .rounded) { dismiss() }
        }
    }

    private var failedPhase: some View {
        VStack(spacing: Spacing.lg) {
            HeroCard(
                icon: "xmark.octagon.fill",
                title: "Restore failed",
                subtitle: errorMessage.map { Text($0) }
                    ?? Text("Something went wrong while reading the backup file.")
            )
            PrimaryCTAButton(title: "Try a different file", icon: "folder", shape: .rounded) {
                errorMessage = nil
                phase = .pick
            }
        }
    }

    // MARK: - Handlers

    private func handleFilePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            AppLog.persistence.error("Backup file pick failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "Couldn't open that file. Try picking it again.")
            phase = .failed
        case .success(let urls):
            guard let url = urls.first else { return }
            validatePickedFile(url)
        }
    }

    private func validatePickedFile(_ url: URL) {
        // The security-scoped resource lifetime must cover the entire
        // read, so it's acquired inside the detached load and released
        // once the bytes are in.
        validate {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf: url)
        }
    }

    private func validateSnapshot(_ info: BackupSnapshotService.Info) {
        validate { try BackupSnapshotService.read(info) }
    }

    /// Moves the read + decode off the main actor so a 50 MB backup
    /// doesn't freeze the UI while validation runs. The decoded backup
    /// and preview are sendable and cross back to the main actor cheaply.
    private func validate(loading load: @escaping @Sendable () throws -> Data) {
        Task { @MainActor in
            do {
                let (parsed, preview) = try await Task.detached(priority: .userInitiated) {
                    () throws -> (backup: AppBackup, preview: BackupImportService.Preview) in
                    try BackupImportService.validate(load())
                }.value
                self.backup = parsed
                self.preview = preview
                self.phase = .preview
            } catch let error as BackupImportService.ImportError {
                AppLog.persistence.error("Backup rejected: \(String(describing: error), privacy: .public)")
                errorMessage = error.errorDescription
                phase = .failed
            } catch {
                AppLog.persistence.error("Backup read failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = String(localized: "Couldn't read that file. Make sure it's an Atlas backup and try again.")
                phase = .failed
            }
        }
    }

    private func apply(strategy: BackupImportService.Strategy) {
        guard let backup else { return }
        phase = .applying
        // Run on the next runloop so the spinner gets a paint cycle.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            do {
                let realized = try BackupImportService.apply(
                    backup,
                    strategy: strategy,
                    into: dataStore
                )
                resultPreview = realized
                phase = .done
                Haptics.success()
            } catch let error as BackupImportService.ImportError {
                AppLog.persistence.error("Backup restore rejected: \(String(describing: error), privacy: .public)")
                errorMessage = error.errorDescription
                phase = .failed
            } catch {
                AppLog.persistence.error("Backup restore failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = String(localized: "Couldn't restore this backup. Try again.")
                phase = .failed
            }
        }
    }
}

// MARK: - Sub-components

private struct HeroCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: Text
    /// One bounce when the card lands — the success beat on "Restore complete".
    var bouncesOnAppear = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(AppFont.scaled(38, weight: .light, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.accentPrimary)
                .symbolEffect(.bounce, value: hasAppeared)
                .padding(.top, Spacing.sm)
                .onAppear {
                    if bouncesOnAppear && !reduceMotion { hasAppeared = true }
                }
            Text(title)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            subtitle
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
    }
}

private struct BackupSummaryCard: View {
    let preview: BackupImportService.Preview

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // v1 backups carried no training data at all — say so
            // explicitly rather than letting "full backup" imply it.
            if preview.workoutSessionsCount > 0 {
                row("Workouts", count(preview.workoutSessionsCount))
            } else {
                row("Workouts", Text("Not in this backup"))
            }
            if preview.routinesCount > 0 { row("Routines", count(preview.routinesCount)) }
            if preview.hasMealHistory  { row("Meal history", Text("Included")) }
            row("Protocols", count(preview.protocolsCount))
            row("Entries", count(preview.entriesCount))
            row("Profile", Text(verbatim: preview.profileName))
            if preview.hasLabHistory   { row("Lab history", Text("Included")) }
            if preview.hasWeightHistory { row("Weight history", Text("Included")) }
            if preview.customPeptidesCount > 0 { row("Custom compounds", count(preview.customPeptidesCount)) }
            row("Backup version", Text(verbatim: preview.version))
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

    private func count(_ value: Int) -> Text {
        Text(value, format: .number)
    }

    private func row(_ label: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            value
                .font(AppFont.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
        }
    }
}

private struct SafetyCopyRow: View {
    let info: BackupSnapshotService.Info
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.createdAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(Int64(info.sizeBytes), format: .byteCount(style: .file))
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget, alignment: .leading)
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
        .accessibilityHint(Text("Shows what this safety copy holds before restoring it"))
    }
}

private struct StrategyCard: View {
    enum Style { case primary, destructive }
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let icon: String
    let style: Style
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(style == .destructive ? AppColor.destructive : AppColor.accentLight)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(detail)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(style == .destructive
                          ? AppColor.destructive.opacity(0.12)
                          : AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                style == .destructive
                                    ? AppColor.destructive.opacity(0.35)
                                    : AppColor.glassBorder,
                                lineWidth: 0.5
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}
