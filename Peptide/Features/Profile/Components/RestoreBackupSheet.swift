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
    @State private var pickedURL: URL?
    @State private var preview: BackupImportService.Preview?
    @State private var backup: AppBackup?
    @State private var errorMessage: String?
    @State private var resultPreview: BackupImportService.Preview?

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
                    case .pick: pickPhase
                    case .preview: previewPhase
                    case .confirming(let strategy): confirmPhase(strategy)
                    case .applying: applyingPhase
                    case .done: donePhase
                    case .failed: failedPhase
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.xl)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false,
                onCompletion: handleFilePicked
            )
        }
    }

    // MARK: - Phases

    private var pickPhase: some View {
        VStack(spacing: Spacing.lg) {
            HeroCard(
                icon: "tray.and.arrow.down.fill",
                title: "Restore from a backup",
                subtitle: "Pick a JSON file you previously exported from Atlas. Your current data is snapshotted first so you can undo the restore if needed."
            )
            Button {
                showingFileImporter = true
            } label: {
                PrimaryButtonLabel(title: "Pick a backup file", icon: "folder")
            }
            .buttonStyle(.plain)
        }
    }

    private var previewPhase: some View {
        VStack(spacing: Spacing.lg) {
            if let preview {
                HeroCard(
                    icon: "doc.text.magnifyingglass",
                    title: "Backup looks valid",
                    subtitle: "Exported \(preview.exportDate.formatted(date: .abbreviated, time: .shortened)). Choose how to apply it."
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
                    detail: "Wipes your current protocols, entries, and profile, then restores from the backup. A snapshot is taken first.",
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
                    ? "Your current data will be replaced. A snapshot of your current state is saved first — you can roll back from Settings if this turns out to be a mistake."
                    : "Your current data is kept; only items missing from your library are added."
            )
            VStack(spacing: Spacing.sm) {
                Button {
                    apply(strategy: strategy)
                } label: {
                    PrimaryButtonLabel(
                        title: strategy == .replace ? "Replace and restore" : "Merge and restore",
                        icon: "checkmark"
                    )
                }
                .buttonStyle(.plain)

                Button("Back") {
                    phase = .preview
                }
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
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
                subtitle: "Your data is back. A snapshot of the pre-restore state is kept under Settings for the next 5 days in case you need to roll back."
            )
            if let resultPreview {
                BackupSummaryCard(preview: resultPreview)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity)
                .background(AppColor.accentPrimary.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
        }
    }

    private var failedPhase: some View {
        VStack(spacing: Spacing.lg) {
            HeroCard(
                icon: "xmark.octagon.fill",
                title: "Restore failed",
                subtitle: errorMessage ?? "Something went wrong while reading the backup file."
            )
            Button("Try a different file") {
                pickedURL = nil
                errorMessage = nil
                phase = .pick
            }
            .buttonStyle(.plain)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(AppColor.accentPrimary.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
        }
    }

    // MARK: - Handlers

    private func handleFilePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            phase = .failed
        case .success(let urls):
            guard let url = urls.first else { return }
            pickedURL = url
            validatePickedFile(url)
        }
    }

    private func validatePickedFile(_ url: URL) {
        // Move the read + decode off the main actor so a 50 MB backup
        // doesn't freeze the UI while validation runs. The
        // security-scoped resource lifetime must cover the entire
        // read, so it's acquired inside the detached task and
        // released right after Data(contentsOf:) returns. The
        // decoded `Data` is sendable and crosses back to the main
        // actor cheaply.
        let target = url
        Task { @MainActor in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    () throws -> Data in
                    let scoped = target.startAccessingSecurityScopedResource()
                    defer { if scoped { target.stopAccessingSecurityScopedResource() } }
                    return try Data(contentsOf: target)
                }.value
                let (parsed, preview) = try BackupImportService.validate(data)
                self.backup = parsed
                self.preview = preview
                self.phase = .preview
            } catch let error as BackupImportService.ImportError {
                errorMessage = error.errorDescription
                phase = .failed
            } catch {
                errorMessage = error.localizedDescription
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
                errorMessage = error.errorDescription
                phase = .failed
            } catch {
                errorMessage = error.localizedDescription
                phase = .failed
            }
        }
    }
}

// MARK: - Sub-components

private struct HeroCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(AppColor.accentPrimary)
                .padding(.top, Spacing.sm)
            Text(title)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitle)
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
            row("Protocols", "\(preview.protocolsCount)")
            row("Entries", "\(preview.entriesCount)")
            row("Profile", preview.profileName)
            if preview.hasMealHistory  { row("Meal history",   "Included") }
            if preview.hasLabHistory   { row("Lab history",    "Included") }
            if preview.hasWeightHistory { row("Weight history", "Included") }
            // v1 backups carried no training data at all — say so
            // explicitly rather than letting "full backup" imply it.
            if preview.workoutSessionsCount > 0 {
                row("Workouts", "\(preview.workoutSessionsCount)")
            } else {
                row("Workouts", "Not in this backup")
            }
            if preview.routinesCount > 0 { row("Routines", "\(preview.routinesCount)") }
            if preview.customPeptidesCount > 0 { row("Custom compounds", "\(preview.customPeptidesCount)") }
            row("Backup version", preview.version)
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

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
        }
    }
}

private struct StrategyCard: View {
    enum Style { case primary, destructive }
    let title: LocalizedStringKey
    let detail: String
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
                        .font(AppFont.caption)
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

private struct PrimaryButtonLabel: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .bold))
            Text(title)
                .font(AppFont.headline)
        }
        .foregroundStyle(AppColor.onAccent)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.accentFill)
        }
    }
}
